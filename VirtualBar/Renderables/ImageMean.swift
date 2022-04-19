import MetalKit
import MetalPerformanceShaders


public typealias float2 = SIMD2<Float>

public class ImageMean: Renderable {
  public var texture: MTLTexture!
  public static var threshold: Float = 0.03
  public static var activeAreaHeightFractionRange: ClosedRange<Float> = 0.04...0.053
  
  var computedTexture: MTLTexture!
  
  
  var squashTextureBuffer: MTLTexture?
  var sobelTextureBuffer: MTLTexture?
  var cpuImageColumnBuffer: UnsafeMutablePointer<SIMD4<UInt8>>?
//  var symmetryOutputBuffer: MTLBuffer?
  
  let pipelineState: MTLRenderPipelineState
//  let lineOfSymmetryPSO: MTLComputePipelineState
  var threshold: Float = 0
  
  var vertices: [Float] = [
    -1.0,  1.0,
     1.0, -1.0,
    -1.0, -1.0,
     
    -1.0,  1.0,
     1.0,  1.0,
     1.0, -1.0
  ]

  var textureCoordinates: [Float] = [
    0.0, 0.0,
    1.0, 1.0,
    0.0, 1.0,
    
    0.0, 0.0,
    1.0, 0.0,
    1.0, 1.0
  ]
  
  public static var activeArea: [float2] = []
    
  init() {
    let textureLoader = MTKTextureLoader(device: Renderer.device)
    do {
      texture = try textureLoader.newTexture(
        name: "test", // File in .xcassets texture set
        scaleFactor: 1.0,
        bundle: Bundle.main,
        options: nil
      )
    } catch let error { fatalError(error.localizedDescription) }
    pipelineState = Self.makePipeline()
//    lineOfSymmetryPSO = Self.makeLineOfSymmetryPipeline()
  }
  
  
  func makeImageBuffers(texture: MTLTexture) {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: 1,
      height: texture.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    
    guard let squashTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor),
          let  sobelTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor)
    else {
      fatalError()
      
    }
    self.squashTextureBuffer = squashTextureBuffer
    self.sobelTextureBuffer = sobelTextureBuffer
    
//    self.symmetryOutputBuffer = Renderer.device.makeBuffer(
//      length: texture.height * MemoryLayout<Float>.stride,
//      options: .storageModeShared
//    )
//    if (self.symmetryOutputBuffer == nil) {
//      fatalError()
//    }
    
    cpuImageColumnBuffer = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
  }
  
  func runMPS(texture: MTLTexture) {
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }
    if squashTextureBuffer == nil || squashTextureBuffer?.height != texture.height {
      makeImageBuffers(texture: texture)
    }

    let squashShader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
    squashShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: squashTextureBuffer!
    )
    
    let derivativeShader = MPSImageSobel(device: Renderer.device)
    derivativeShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: squashTextureBuffer!,
      destinationTexture: sobelTextureBuffer!
    )
    
//    detectLineOfSymmetry(commandBuffer: commandBuffer, sobelTextureBuffer: sobelTextureBuffer!);
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    // Squash + Sobel + simple symmetry compute: ~1.3 ms
//    print("GPU Full Pipeline Duration:", CFAbsoluteTimeGetCurrent() - startTime)
    
    
    Self.copyTexture(source: sobelTextureBuffer!, destination: cpuImageColumnBuffer!)

    let sobelOutputFloat: [Float] = Self.copyPixelsToArray(
      source: cpuImageColumnBuffer!,
      length: texture.height
    ).map {
      var float: SIMD4<Float> = SIMD4<Float>($0)
      float.w = 0
      float /= 255
      return dot(float, float)
    }
    
    Self.copyTexture(source: squashTextureBuffer!, destination: cpuImageColumnBuffer!)
    let squashOutputFloat: [Float] = Self.copyPixelsToArray(
      source: cpuImageColumnBuffer!,
      length: texture.height
    ).map {
      var float: SIMD4<Float> = SIMD4<Float>($0)
      float.w = 0
      float /= 255
      return dot(float, float)
    }

    Self.activeArea = Self.detectActiveArea(
      sobelOutput: sobelOutputFloat,
      squashOutput: squashOutputFloat,
      threshold: Self.threshold,
      sizeRange: Self.activeAreaHeightFractionRange
    )
  }
  
  // Copies single column image from MTLTexture to a CPU buffer with the correct amount of memory allocated
  static func copyTexture(source: MTLTexture, destination: UnsafeMutablePointer<SIMD4<UInt8>>) {
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes
    source.getBytes(
      destination,
      bytesPerRow: MemoryLayout<SIMD4<UInt8>>.stride,
      from: MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: 1, height: source.height, depth: 1)
      ),
      mipmapLevel: 0
    )
  }
  
  static func copyPixelsToArray<T>(source: UnsafeMutablePointer<T>, length: Int) -> [T] {
    var output: [T] = []
    var pointer = source
    
    for _ in 0..<length {
      output.append(pointer.pointee)
      pointer = pointer.advanced(by: 1)
    }
    
    return output
  }
  
  static func triangleWeightedAverage(arr: [Float], min: Int, size: Int, minWeight: Float = 0) -> Float {
    let radius = Float(size - 1) / 2
    let center: Float = Float(min) + radius
    
    func halfDistributionTriangle(t: Float) -> Float {
      // t in [0, 1], where 1 is the center of the distribution
      return t * (1 - minWeight) + minWeight
    }
    
    func halfDistributionCutoffTriangle(t: Float) -> Float {
      let cutOff: Float = 0.2 // Ignore first and last 10% of the image
      return halfDistributionTriangle(t: max(Float(0), t - cutOff))
    }
    
    func halfDistributionCutoffRect(t: Float) -> Float {
      let cutOff: Float = 0.2 // Ignore first and last 10% of the image
      return t < cutOff ? 0: 1
    }
    
    return (min..<min + size).makeIterator().reduce(0) { current, i in
      let distanceFromCenter = abs(Float(i) - center) / radius
      let t = 1 - distanceFromCenter
//      let weight = halfDistributionCutoffTriangle(t: t)
      let weight = halfDistributionCutoffRect(t: t)
      return current + arr[i] * weight
    } / Float(size)
  }

  
  static func detectActiveArea(
    sobelOutput: [Float],
    squashOutput: [Float],
    threshold: Float,
    sizeRange sizeRangeFraction: ClosedRange<Float>
  ) -> [float2] {
    let imageHeight: Float = Float(sobelOutput.count)
    let sizeRange = Int(floor(sizeRangeFraction.lowerBound * imageHeight))...Int(ceil(sizeRangeFraction.upperBound * imageHeight))
   
    // Idea: touch bar area is very smooth. Hence, find areas with a low derivative that are the correct height
    var current: (x: Int, size: Int) = (x: 0, size: 0)
    var possibleMatches: [(x: Int, size: Int)] = []
    
    for (i, val) in sobelOutput.enumerated() {
      if val < threshold {
        current.size += 1
      } else {
        if sizeRange.contains(current.size) {
          possibleMatches.append(current)
        }
        current = (x: i, size: 0)
      }
    }
    
    // Idea: key rows can get detected, so use the squash map to get the color of the area
    // The active area will be the lightest area - keys are black while the body is grey,
    // so this should prevent a key row from being detected as a false positive
    let coloredMatches = possibleMatches.map {
      return (
        x1: $0.x,
        x2: $0.x + $0.size,
        color: squashOutput[$0.x + $0.size / 2],
        weightedAverage: Self.triangleWeightedAverage(arr: sobelOutput, min: $0.x, size: $0.size)
     )
    }
     
    let coloredSortedMatches = coloredMatches.sorted(by: { $0.color > $1.color })
    
    let weightSortedMatches = coloredMatches.sorted(by: { $0.weightedAverage < $1.weightedAverage })
    
    return weightSortedMatches.map {[
//    return coloredSortedMatches.map {[
      Float($0.x1) / Float(sobelOutput.count),
      Float($0.x2) / Float(sobelOutput.count)
    ]}
  }
  
    
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_image_mean",
      fragment: "fragment_image_mean"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
//  static func makeLineOfSymmetryPipeline() -> MTLComputePipelineState {
//    guard let function = Renderer.library.makeFunction(name: "line_of_symmetry") else {
//      fatalError("Could not make line of symmetry compute function")
//    }
//    do {
//      return try Renderer.device.makeComputePipelineState(function: function);
//    } catch {
//      print(error.localizedDescription)
//      fatalError("Failed to create compute pipeline state for symmetry")
//    }
//  }
//
//  func detectLineOfSymmetry(commandBuffer: MTLCommandBuffer, sobelTextureBuffer: MTLTexture) {
//    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
//      fatalError("Failed to create compute encoder for symmetry")
//    }
//
//    computeEncoder.setComputePipelineState(lineOfSymmetryPSO)
//    
//    var args = LineOfSymmetryArgs(deadzone: 100);
//
//    computeEncoder.setTexture(sobelTextureBuffer, index: 0);
//    computeEncoder.setBuffer(symmetryOutputBuffer, offset: 0, index: 0);
//    computeEncoder.setBytes(&args, length: MemoryLayout<LineOfSymmetryArgs>.stride, index: 1);
//
//    let threadsPerGroup = MTLSize(
//      width: min(lineOfSymmetryPSO.threadExecutionWidth, sobelTextureBuffer.height),
//      height: 1,
//      depth: 1
//    )
//
//    let threadsPerGrid = MTLSize(width: sobelTextureBuffer.height, height: 1, depth: 1)
//    // Optimization: set grid size to height - 2 * deadzone
//    computeEncoder.dispatchThreads(
//      threadsPerGrid,
//      threadsPerThreadgroup: threadsPerGroup
//    )
//    computeEncoder.endEncoding()
//  }
//
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    runMPS(texture: texture)
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.setVertexBytes(
      &vertices,
      length: MemoryLayout<Float>.stride * vertices.count,
      index: 0
    )
    renderEncoder.setVertexBytes(
      &textureCoordinates,
      length: MemoryLayout<Float>.stride * textureCoordinates.count,
      index: 1
    )
    renderEncoder.setFragmentTexture(texture, index: 0)
    
    renderEncoder.setFragmentTexture(squashTextureBuffer, index: 1)
    renderEncoder.setFragmentTexture(sobelTextureBuffer, index: 2)
    
    renderEncoder.setFragmentBytes(
      &Self.threshold,
      length: MemoryLayout<Float>.stride,
      index: 3
    )
    
    if Self.activeArea.isEmpty {
      Self.activeArea = [[-1, -1]]
      // Dies if empty array passed. Not sure how to solve it
    }
    
    renderEncoder.setFragmentBytes(
      &Self.activeArea,
      length: MemoryLayout<float2>.stride * Self.activeArea.count,
      index: 4
    )
    
    var count: Int = Self.activeArea.count
    renderEncoder.setFragmentBytes(
      &count,
      length: MemoryLayout<Int>.stride,
      index: 5
    )
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 2)
  }
}
