import MetalKit


typealias float3 = SIMD3<Float>
typealias float4 = SIMD4<Float>


/*
 * Pipeline descriptor: object containing configuration for each mesh being rendered
 * Expensive to make; don't make a new one each frame
 */
func buildPartialPipelineDescriptor(
  vertex     vertexFunctionName: String = "vertex_main",
  fragment fragmentFunctionName: String = "fragment_main"
) -> MTLRenderPipelineDescriptor {
  let descriptor = MTLRenderPipelineDescriptor()
  descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
//  descriptor.depthAttachmentPixelFormat = .depth32Float
  descriptor.vertexFunction   = Renderer.library.makeFunction(name: vertexFunctionName)
  descriptor.fragmentFunction = Renderer.library.makeFunction(name: fragmentFunctionName)
  return descriptor
}
// Can optionally pass in constants to vertex/fragment functions
/*
 let functionConstants = MTLFunctionConstantValues()
 var someProperty = true
 functionConstants.setConstantValue(&someProperty, type: .bool, index: 0)
 
 descriptor.fragmentFunction = library.makeFunction(
 name: fragmentFunctionName,
 constantValues: functionConstants
 )
 constant bool someConstant [[function_constant(0)]];
 ...vertexOrfragmentFunction(
 bla someValueThatIsNotAccessedIfConstantIsFalse [[someDecorator(0)]] function_constant[[someConstant]]
 ) {
 if (someConstant) {
 // use someValueThatIsNotAccessedIfConstantIsFalse
 }
 }
 */

