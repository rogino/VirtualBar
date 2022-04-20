//
//  PlonkTexture.swift
//  VirtualBar
//
//  Created by Rio Ogino on 20/04/22.
//

import MetalKit

public class PlonkTexture: Renderable {
  public var texture: MTLTexture?
  
  let pipelineState: MTLRenderPipelineState
  
  public static var activeArea: [float2] = []
    
  init() {
    pipelineState = Self.makePipeline()
  }
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_plonk_texture",
      fragment: "fragment_plonk_texture"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.setFragmentTexture(texture, index: 0)
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
