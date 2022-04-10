import MetalKit

public class FingerPointsRenderer: Renderable {
  
  public var fingerPoints: [simd_float3] = []
  
  let pipelineState: MTLRenderPipelineState
  
  public init() {
    pipelineState = Self.makePipeline()
  }
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_finger_points",
      fragment: "fragment_finger_points"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    guard fingerPoints.count > 0 else { return }
    renderEncoder.setVertexBytes(
      &fingerPoints,
      length: MemoryLayout<simd_float3>.stride * fingerPoints.count,
      index: 0
    )
    renderEncoder.setTriangleFillMode(.lines)
    renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: fingerPoints.count)
  }
}
