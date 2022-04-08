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
  
  static func runMPS(texture: MTLTexture) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat, // pixel format in example set to R8Unorm (only red channel). RGBA8Unorm causes crash
      width: 1, // texture.width,
      height: texture.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    
    guard let destination = Renderer.device.makeTexture(descriptor: descriptor),
          let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }

    let squashShader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
    squashShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: destination
    )
    
    let derivativeShader = MPSImageSobel(device: Renderer.device)
    guard let destination2 = Renderer.device.makeTexture(descriptor: descriptor) else { fatalError() }
    
    derivativeShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: destination,
      destinationTexture: destination2
    )
    commandBuffer.commit()
    
    return destination2
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
    computedTexture = Self.runMPS(texture: texture)
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
    var bla = threshold.truncatingRemainder(dividingBy: 0.2) + 0.25
//    print(bla)
    renderEncoder.setFragmentBytes(&bla, length: MemoryLayout<Float>.stride, index: 3)
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 2)
  }
}
