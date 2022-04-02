import Foundation
import MetalKit

struct VertexColorPair {
  let vertex: float3;
  let color: float4;
  init(_ vertex: float3, rgba color: float4) {
    self.vertex = vertex;
    self.color = color;
  }
  init(_ vertex: float3, rgb color: float3) {
    self.vertex = vertex;
    self.color = float4(color, 1);
  }
}

func makeEqTriangle(center: SIMD2<Float>, sideWidth size: Float) -> [float3] {
  func rotateAroundPoint(point: SIMD2<Float>, center: SIMD2<Float>, angle: Float) -> SIMD2<Float> {
//    let translation = simd_float3x3(rows: [
//      [1, 0, -center[0]],
//      [0, 1, -center[1]],
//      [0, 0,          1]
//    ])
//    let result = translation.inverse * simd_float3x3([
//      [cos(angle), -sin(angle), 0],
//      [sin(angle),  cos(angle), 0],
//      [0,                   0,  1]
//    ]) * translation * SIMD3<Float>(point, 1)
//    return [result.x, result.y]
    
    let cosine = cos(angle)
    let sine   = sin(angle)
    return center + (simd_float2x2([[cosine, -sine], [sine, cosine]]) * (point - center))
  }
  
  let radius = size / (2 * sin(Float.pi / 3))
  let top: SIMD2<Float> = [center.x, center.y + radius];
  let left  = rotateAroundPoint(point: top, center: center, angle: -Float.pi * 2 / 3)
  let right = rotateAroundPoint(point: top, center: center, angle:  Float.pi * 2 / 3)
  
  return [top, left, right].map { [$0.x, $0.y, 0] }
}

public class Triangle: Renderable {
  var verticesAndColors: [VertexColorPair]
  var primitivesBuffer: MTLBuffer?
  let pipelineDescriptor: MTLRenderPipelineDescriptor
  
  var timer: Float = 0

  public init() {
    let vertices = makeEqTriangle(center: SIMD2<Float>(0, 0), sideWidth: 1)
    verticesAndColors = [
      VertexColorPair(vertices[0], rgb: [1, 0, 0]),
      VertexColorPair(vertices[1], rgb: [0, 1, 0]),
      VertexColorPair(vertices[2], rgb: [0, 0, 1]),
    ]
    pipelineDescriptor = buildPartialPipelineDescriptor(vertex: "vertex_triangle", fragment: "fragment_triangle")
    primitivesBuffer = Renderer.device.makeBuffer(
      bytes: &verticesAndColors,
      length: MemoryLayout<VertexColorPair>.stride * verticesAndColors.count
    )
  }
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setVertexBuffer(primitivesBuffer, offset: 0, index: 0)
    
    timer += 0.01
    let angle = timer.truncatingRemainder(dividingBy: Float.pi * 2)
    
    let rotation: float4x4 = float4x4(rows: [
      [cos(angle), -sin(angle), 0, 0],
      [sin(angle),  cos(angle), 0, 0],
      [         0,           0, 1, 0],
      [         0,           0, 0, 1]
    ])
    
    var scale: float4x4 = matrix_identity_float4x4
    if (Renderer.aspect < 1) { scale.columns.1[1] *= Renderer.aspect }
    
    else { scale.columns.0[0] /= Renderer.aspect }
    var transform = scale * rotation
    
    renderEncoder.setVertexBytes(&transform, length: MemoryLayout<float4x4>.stride, index: 1)
   
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      renderEncoder.setRenderPipelineState(pipelineState)
    } catch let error { fatalError(error.localizedDescription) }

    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verticesAndColors.count)
  }
}
