import MetalKit
import MetalPerformanceShaders


public typealias float2 = SIMD2<Float>

public class ImageMean: Renderable {
  public var texture: MTLTexture!
  public static var threshold: Float = 0.02
  public static var activeAreaHeightFractionRange: ClosedRange<Float> = 0.04...0.06
  
  var computedTexture: MTLTexture!
  
  
  var squashTextureBuffer: MTLTexture?
  var sobelTextureBuffer: MTLTexture?
  var cpuImageColumnBuffer: UnsafeMutablePointer<SIMD4<UInt8>>?
//  var symmetryOutputBuffer: MTLBuffer?
  
  let pipelineState: MTLRenderPipelineState
//  let lineOfSymmetryPSO: MTLComputePipelineState
  var threshold: Float = 0
  
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
    else { fatalError() }
    
    squashTextureBuffer.label = "Squash texture buffer"
    sobelTextureBuffer.label = "Sobel texture buffer"
    self.squashTextureBuffer = squashTextureBuffer
    self.sobelTextureBuffer = sobelTextureBuffer
    
    cpuImageColumnBuffer = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
  }
  
  func runMPS(texture: MTLTexture) {
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }
    commandBuffer.label = "Active area detection"
    if squashTextureBuffer == nil || squashTextureBuffer?.height != texture.height {
      makeImageBuffers(texture: texture)
    }

    commandBuffer.pushDebugGroup("MPS row reduce + sobel")
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
    
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    commandBuffer.popDebugGroup()
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
    
    let squashOutput4UInt8: [SIMD4<UInt8>] = Self.copyPixelsToArray(
      source: cpuImageColumnBuffer!,
      length: texture.height
    )
    
    let squashOutputFloat: [Float] = squashOutput4UInt8.map {
      var float: SIMD4<Float> = SIMD4<Float>($0)
      float.w = 0
      float /= 255
      return dot(float, float)
    }

    Self.activeArea = Self.detectActiveArea(
      sobelOutput: sobelOutputFloat,
      squashOutput: squashOutputFloat,
      squashOutput4UInt8: squashOutput4UInt8,
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
      return current + arr[i] * arr[i] * weight
    } / Float(size)
  }

  
  struct CandidateArea {
    let x1: Int
    let size: Int
    var x2: Int { x1 + size }
    
    let centerColor: Float
    let weightedAveragedDerivative: Float
    var ranking: Int
  }
  
  static func detectActiveArea(
    sobelOutput: [Float],
    squashOutput: [Float],
    squashOutput4UInt8: [SIMD4<UInt8>],
    threshold: Float,
    sizeRange sizeRangeFraction: ClosedRange<Float>
  ) -> [float2] {
    let imageHeight: Float = Float(sobelOutput.count)
    let sizeRange = Int(floor(sizeRangeFraction.lowerBound * imageHeight))...Int(ceil(sizeRangeFraction.upperBound * imageHeight))
   
    var current: (x: Int, size: Int) = (x: 0, size: 0)
    var candidateMatches: [CandidateArea] = []
    
    // Idea: touch bar area is very smooth. Hence, find areas with a low derivative that are the correct height
    for (i, val) in sobelOutput.enumerated() {
      if val < threshold {
        current.size += 1
      } else {
        if sizeRange.contains(current.size) {
          candidateMatches.append(CandidateArea(
            x1: current.x,
            size: current.size,
            // Idea: key rows can get detected, so use the squash map to get the color of the area
            // The active area will be the lightest area - keys are black while the body is grey,
            // so this should prevent a key row from being detected as a false positive
            centerColor: squashOutput[current.x + current.size / 2],
            // Idea: use weighted derivative quantify amount of variance
            weightedAveragedDerivative: Self.triangleWeightedAverage(arr: sobelOutput, min: current.x, size: current.size),
            ranking: -1
          ))
        }
        current = (x: i, size: 0)
      }
    }
    
    
    let colorSortedMatches = candidateMatches.sorted(by: { $0.centerColor > $1.centerColor })
    let weightSortedMatches = candidateMatches.sorted(by: { $0.weightedAveragedDerivative < $1.weightedAveragedDerivative })
    
    // Sum the color and weight indexes, find the lowest
    let indexWeighted: [(weightIndex: Int, colorIndex: Int, sum: Int)] = colorSortedMatches.enumerated().map { (i, val) in
      let weightIndex = weightSortedMatches.firstIndex(where: { $0.x1 == val.x1 })!
      return (weightIndex: weightIndex, colorIndex: i, sum: weightIndex + i)
    }.sorted(by: { $0.sum == $1.sum ? $0.colorIndex < $1.colorIndex : $0.sum < $1.sum }) // Prefer color over weight
    
    candidateMatches = indexWeighted.enumerated().map {
      var match = colorSortedMatches[$1.colorIndex]
      match.ranking = $0
      return match
    }
    
    return candidateMatches.map {[
      Float($0.x1) / Float(sobelOutput.count),
      Float($0.x2) / Float(sobelOutput.count)
    ]}
//
//    return weightSortedMatches.map {[
////    return coloredSortedMatches.map {[
//      Float($0.x1) / Float(sobelOutput.count),
//      Float($0.x2) / Float(sobelOutput.count)
//    ]}
  }
  
    
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_plonk_texture_mirrored_horizontal",
      fragment: "fragment_image_mean"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    runMPS(texture: texture)
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
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
    
    renderEncoder.setFragmentTexture(texture, index: 0)
        
    
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
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
