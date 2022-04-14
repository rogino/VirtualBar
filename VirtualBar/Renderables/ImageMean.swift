import MetalKit
import MetalPerformanceShaders

public class ImageMean: Renderable {
  public var texture: MTLTexture!
  var computedTexture: MTLTexture!
  
  let pipelineState: MTLRenderPipelineState
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
  }
  
  func runMPS(texture: MTLTexture) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: 1,
      height: texture.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    
    guard let squashTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor),
          let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }

    let squashShader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
    squashShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: squashTextureBuffer
    )
    
    let derivativeShader = MPSImageSobel(device: Renderer.device)
    guard let sobelTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor) else { fatalError() }
    
    derivativeShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: squashTextureBuffer,
      destinationTexture: sobelTextureBuffer
    )
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes

    let sobelCpuBuffer = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
    sobelTextureBuffer.getBytes(
      sobelCpuBuffer,
      bytesPerRow: MemoryLayout<SIMD4<UInt8>>.stride,
      from: MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: 1, height: texture.height, depth: 1)
      ),
      mipmapLevel: 0
    )

    var pointer = sobelCpuBuffer
    
    var output: [Float] = []
    for _ in 0..<texture.height {
      let val = (
        Float(pointer.pointee.x) +
        Float(pointer.pointee.y) +
        Float(pointer.pointee.z)
      ) / 3
      output.append(val)
      pointer = pointer.advanced(by: 1)
    }
    sobelCpuBuffer.deallocate()
    
//    activeArea = Self.detectActiveArea(sobelOutput: output)
    activeArea = Self.detectLineOfSymmetry(sobelOutput: output)
    return sobelTextureBuffer
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
