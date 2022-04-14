import MetalKit
import MetalPerformanceShaders

public class ImageMean: Renderable {
  public var texture: MTLTexture!
  var computedTexture: MTLTexture!
  
  
  var squashTextureBuffer: MTLTexture?
  var sobelTextureBuffer: MTLTexture?
  var symmetryOutputBuffer: MTLBuffer?
  
  
  let pipelineState: MTLRenderPipelineState
  let lineOfSymmetryPSO: MTLComputePipelineState
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
  
  var activeArea: (Float, Float) = (-1, -1)
    
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
    lineOfSymmetryPSO = Self.makeLineOfSymmetryPipeline()
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
    
    self.symmetryOutputBuffer = Renderer.device.makeBuffer(
      length: texture.height * MemoryLayout<Float>.stride,
      options: .storageModeShared
    )
    if (self.symmetryOutputBuffer == nil) {
      fatalError()
    }
  }
  
  func runMPS(texture: MTLTexture) -> MTLTexture {
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
    
    detectLineOfSymmetry(commandBuffer: commandBuffer, sobelTextureBuffer: sobelTextureBuffer!);
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    // Squash + Sobel + simple symmetry compute: 13 ms
    print("GPU Full Pipeline Duration:", CFAbsoluteTimeGetCurrent() - startTime)
    
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes

//    let sobelCpuBuffer = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
//    sobelTextureBuffer!.getBytes(
//      sobelCpuBuffer,
//      bytesPerRow: MemoryLayout<SIMD4<UInt8>>.stride,
//      from: MTLRegion(
//        origin: MTLOrigin(x: 0, y: 0, z: 0),
//        size: MTLSize(width: 1, height: texture.height, depth: 1)
//      ),
//      mipmapLevel: 0
//    )
//
//    var pointer = sobelCpuBuffer
//
//    var output: [Float] = []
//    for _ in 0..<texture.height {
//      let val = (
//        Float(pointer.pointee.x) +
//        Float(pointer.pointee.y) +
//        Float(pointer.pointee.z)
//      ) / 3
//      output.append(val)
//      pointer = pointer.advanced(by: 1)
//    }
//    sobelCpuBuffer.deallocate()
    
    var pointer = symmetryOutputBuffer!.contents().bindMemory(to: Float.self, capacity: texture.height)
    
    var output: [Float] = []
    var min: (i: Int, v: Float) = (i: -1, v: Float.infinity)
    for i in 0..<texture.height {
      if pointer.pointee < min.v {
        min = (i: i, v: pointer.pointee)
      }
      pointer = pointer.advanced(by: 1)
    }
    activeArea = (
      Float(min.i - 3) / Float(texture.height),
      Float(min.i + 3) / Float(texture.height)
    )
    
//    activeArea = Self.detectActiveArea(sobelOutput: output)
//    activeArea = Self.detectLineOfSymmetry(sobelOutput: output)
    return sobelTextureBuffer!
  }
  
  
  
  static func makeLineOfSymmetryPipeline() -> MTLComputePipelineState {
    guard let function = Renderer.library.makeFunction(name: "line_of_symmetry") else {
      fatalError("Could not make line of symmetry compute function")
    }
    do {
      return try Renderer.device.makeComputePipelineState(function: function);
    } catch {
      print(error.localizedDescription)
      fatalError("Failed to create compute pipeline state for symmetry")
      
    }
  }
  
  func detectLineOfSymmetry(commandBuffer: MTLCommandBuffer, sobelTextureBuffer: MTLTexture) {
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
      fatalError("Failed to create compute encoder for symmetry")
    }
    
    computeEncoder.setComputePipelineState(lineOfSymmetryPSO)
    
    var args = LineOfSymmetryArgs(deadzone: 100);
    
    computeEncoder.setTexture(sobelTextureBuffer, index: 0);
    computeEncoder.setBuffer(symmetryOutputBuffer, offset: 0, index: 0);
    computeEncoder.setBytes(&args, length: MemoryLayout<LineOfSymmetryArgs>.stride, index: 1);
    
    let threadsPerGroup = MTLSize(
      width: min(lineOfSymmetryPSO.threadExecutionWidth, sobelTextureBuffer.height),
      height: 1,
      depth: 1
    )
    
    let threadsPerGrid = MTLSize(width: sobelTextureBuffer.height, height: 1, depth: 1)
    // Optimization: set grid size to height - 2 * deadzone
    computeEncoder.dispatchThreads(
      threadsPerGrid,
      threadsPerThreadgroup: threadsPerGroup
    )
    computeEncoder.endEncoding()
  }
  
  static func detectActiveArea(
    sobelOutput: [Float],
    threshold: Float = 5,
    sizeRange: ClosedRange<Int> = 30...50
  ) -> (Float, Float) {
    var current: (x: Int, size: Int) = (x: 0, size:  0)
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
          
    
    if possibleMatches.isEmpty {
      return (-1, -1)
    } else {
      let chosen = possibleMatches.max(by: { $0.size > $1.size })!
      
      return (
        Float(chosen.x)                   / Float(sobelOutput.count),
        Float(chosen.x + chosen.size + 1) / Float(sobelOutput.count)
      )
    }
  }
  
  static func detectLineOfSymmetry(
    sobelOutput: [Float]
  ) -> (Float, Float) {
    let startTime = CFAbsoluteTimeGetCurrent()
    var variances: [(Int, Float)] = []
    let deadZone = 100 // First and last n values will not be used as center
    sobelOutput.enumerated().forEach { (center, _) in
      if center < deadZone || sobelOutput.count - center - 1 < deadZone {
        return
      }
      let n = min(center, sobelOutput.count - center - 1)
      var sum: Float = 0
      for i in 1...n {
        let delta = sobelOutput[center + i] - sobelOutput[center - i]
        sum += delta * delta
      }
      variances.append((center, sum / Float(n)))
    }
    
    variances = variances.sorted(by: { $0.1 < $1.1 })
    print("CPU Time:", CFAbsoluteTimeGetCurrent() - startTime) // ~40 ms
    print(variances[..<30])
    return (
      Float(variances[0].0 - 3) / Float(sobelOutput.count),
      Float(variances[0].0 + 3) / Float(sobelOutput.count)
    )
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
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    computedTexture = runMPS(texture: texture)
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
    
    renderEncoder.setFragmentTexture(computedTexture, index: 1)
    renderEncoder.setFragmentTexture(texture, index: 2)
    threshold = (threshold + 0.001).truncatingRemainder(dividingBy: 1)
    var bla = threshold.truncatingRemainder(dividingBy: 0.25) + 0.05
    bla = 1;
//    print(bla)
    renderEncoder.setFragmentBytes(&bla, length: MemoryLayout<Float>.stride, index: 3)
    
    
    renderEncoder.setFragmentBytes(
      &activeArea,
      length: MemoryLayout<Float>.stride * 2,
      index: 4
    )
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 2)
  }
}
