import MetalKit
import MetalPerformanceShaders

public class ImageMean: Renderable {
  let texture: MTLTexture!
  let computedTexture: MTLTexture!
  
  let rectMesh: MTKMesh!
  let pipelineState: MTLRenderPipelineState
  
  var threshold: Float = 0
  
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

    computedTexture = Self.runMPS(texture: texture)
    
    let (mdlMesh, mtkMesh) = Self.genRectMesh()
    self.rectMesh = mtkMesh
    pipelineState = Self.makePipeline(mdlMesh: mdlMesh)
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

    let shader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
//    let shader = MPSImageMedian(device: Renderer.device, kernelDiameter: 51)
//    var shader = MPSImageGaussianBlur(device: Renderer.device, sigma: 10)
//    var transform: Float = 1.2
//    var shader = MPSImageCanny(device: Renderer.device)
    shader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: destination
    )
    
    let shader2 = MPSImageSobel(device: Renderer.device)
    guard let destination2 = Renderer.device.makeTexture(descriptor: descriptor) else { fatalError() }
    
    shader2.encode(
      commandBuffer: commandBuffer,
      sourceTexture: destination,
      destinationTexture: destination2
    )
    commandBuffer.commit()
    
    return destination2
  }
  
//  static func runNonMps(descriptor: MTLTextureDescriptor, texture: MTLTexture) -> MTLTexture {
//    guard let destination = Renderer.device.makeTexture(descriptor: descriptor),
//          let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
//    else { fatalError() }
//
//    let descriptor = MTLComputePipelineDescriptor()
//    Renderer.library.makeFunction(name: "mean_filter")
//
//    let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//    computeEncoder.setComputePipelineState(tessellationPipelineState)
//    computeEncoder.setBytes(&edgeFactors,
//                            length: MemoryLayout<Float>.size * edgeFactors.count,
//                            index: 0)
//    computeEncoder.setBytes(&insideFactors,
//                            length: MemoryLayout<Float>.size * insideFactors.count,
//                            index: 1)
//    computeEncoder.setBuffer(tessellationFactorsBuffer, offset: 0, index: 2)
//    computeEncoder.dispatchThreadgroups(MTLSizeMake(patchCount, 1, 1), threadsPerThreadgroup: MTLSizeMake(width, 1, 1))
//    computeEncoder.endEncoding()
//

//    let kernel = Renderer.device.makeComputePipelineState(function: <#T##MTLFunction#>)
//    return nil;
//  }
  
  
  static func genRectMesh() -> (MDLMesh, MTKMesh) {
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let mdlMesh = MDLMesh(
      boxWithExtent: [2, 2, 0],
      segments: [1, 1, 1],
      inwardNormals: false,
      geometryType: .triangles,
      allocator: allocator
    )
    
    do {
      let mtkMesh = try MTKMesh(mesh: mdlMesh, device: Renderer.device)
      return (mdlMesh, mtkMesh)
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  static func makePipeline(mdlMesh: MDLMesh) -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_image_mean",
      fragment: "fragment_image_mean"
    )
    pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)

    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }

  }
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.setVertexBuffer(rectMesh.vertexBuffers.first!.buffer, offset: 0, index: 0)
    renderEncoder.setFragmentTexture(computedTexture, index: 1)
    renderEncoder.setFragmentTexture(texture, index: 2)
    
    threshold = (threshold + 0.001).truncatingRemainder(dividingBy: 1)
    var bla = threshold.truncatingRemainder(dividingBy: 0.2) + 0.25
    print(bla)
    renderEncoder.setFragmentBytes(&bla, length: MemoryLayout<Float>.stride, index: 3)
    
    let submesh = rectMesh.submeshes.first!
    renderEncoder.drawIndexedPrimitives(
      type: .triangle,
      indexCount: submesh.indexCount,
      indexType: submesh.indexType,
      indexBuffer: submesh.indexBuffer.buffer,
      indexBufferOffset: submesh.indexBuffer.offset
    )
  }
}
