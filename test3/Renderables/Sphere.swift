import MetalKit

public class Sphere: Renderable {
  let mtkMesh: MTKMesh
  let pipelineState: MTLRenderPipelineState
  
  public init() {
    let allocator = MTKMeshBufferAllocator(device: Renderer.device)
    let mdlMesh = MDLMesh(
      sphereWithExtent: [0.5, 0.5, 0.5],
      segments: [40, 40],
      inwardNormals: false,
      geometryType: .triangles,
      allocator: allocator
    )
    do {
      mtkMesh = try MTKMesh(mesh: mdlMesh, device: Renderer.device)
    } catch let error { fatalError(error.localizedDescription) }

    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_minimal_indexed",
      fragment: "fragment_minimal_red"
    )
    pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)

    do {
      pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    

    renderEncoder.setTriangleFillMode(.lines)
    for (i, vertexBuffer) in mtkMesh.vertexBuffers.enumerated() {
      renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: 0, index: i)
    }
    for submesh in mtkMesh.submeshes {
      renderEncoder.drawIndexedPrimitives(
        type: .triangle,
        indexCount: submesh.indexCount,
        indexType: submesh.indexType,
        indexBuffer: submesh.indexBuffer.buffer,
        indexBufferOffset: submesh.indexBuffer.offset
      )
    }
  }
}

