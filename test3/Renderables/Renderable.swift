import MetalKit

public protocol Renderable {
  func draw(renderEncoder: MTLRenderCommandEncoder)
}
