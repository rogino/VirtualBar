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
  
  var activeArea: [Float] = [-1, -1]
    
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

    var chosen: (x: Int, size: Int) = (x: -1, size: -1)
    var current: (x: Int, size: Int) = (x: 0, size:  0)
    
    var pointer = sobelCpuBuffer
    for i in 0..<texture.height {
      let val = (
        Float(pointer.pointee.x) +
        Float(pointer.pointee.y) +
        Float(pointer.pointee.z)
      ) / 3
      
      if val < threshold {
        current.size += 1
      } else {
        if chosen.size < current.size {
          chosen = current
          current = (x: i, size: 0)
        }
      }
      
      pointer = pointer.advanced(by: 1)
    }
          
    activeArea = [
       Float(chosen.x)               / Float(texture.height),
       Float(chosen.x + chosen.size) / Float(texture.height)
    ]
//    print(chosen)
    sobelCpuBuffer.deallocate()
    
    return sobelTextureBuffer
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
//    print(bla)
    renderEncoder.setFragmentBytes(&bla, length: MemoryLayout<Float>.stride, index: 3)
    
    
    renderEncoder.setFragmentBytes(
      &activeArea,
      length: MemoryLayout<Float>.stride * activeArea.count,
      index: 4
    )
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 2)
  }
}
