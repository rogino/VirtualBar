//
//  Hough.swift
//  VirtualBar
//
//  Created by Rio Ogino on 8/05/22.
//

import Foundation
import MetalPerformanceShaders

class Hough {
  var cannyEncoder: MPSImageCanny
  var cannyTexture: MTLTexture?
  var outTexture: MTLTexture?
  
  let pso: MTLRenderPipelineState
  
  init() {
    cannyEncoder = MPSImageCanny(device: Renderer.device)
    pso = Self.makePSO()
  }
  
  static func makePSO() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "hough_vertex",
      fragment: "hough_fragment"
    )
    pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  func makeTextureBuffers(input: MTLTexture) throws {
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float,
      width: input.width,
      height: input.height,
      mipmapped: false
    )
    textureDescriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
    
    outTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    if outTexture == nil {
      fatalError()
    }
    outTexture?.label = "Hough out image"
   
    
    textureDescriptor.usage = [.shaderWrite, .shaderRead]
    cannyTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    if cannyTexture == nil {
      fatalError()
    }
    cannyTexture?.label = "Canny"
  }
  
  func run(image: MTLTexture) {
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer() else {
      fatalError()
    }
    
    if cannyTexture == nil || cannyTexture!.height != image.height {
      try! makeTextureBuffers(input: image)
    }
    
    cannyEncoder.encode(commandBuffer: commandBuffer, sourceTexture: image, destinationTexture: cannyTexture!)
    
//    let blitCommendEncoder = commandBuffer.makeBlitCommandEncoder()
//    blitCommendEncoder?.copy
    
    let renderPassDescriptor = MTLRenderPassDescriptor()
    let attachment = renderPassDescriptor.colorAttachments[0]
    attachment?.texture = outTexture
    attachment?.loadAction = .clear
    attachment?.storeAction = .store
    
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
      return
    }
    renderEncoder.setRenderPipelineState(pso)
    
    renderEncoder.setVertexTexture(cannyTexture, index: 0)
    
    let vertexCount = image.width * image.height * 2
    renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }
}
