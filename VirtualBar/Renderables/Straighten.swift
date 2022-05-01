import MetalKit
import MetalPerformanceShaders

public class Straighten {
  // this section of the left half of texture used in averaging. right is symmetrical
  var halfSampleTextureSize: (Float, Float) = (0.2, 0.4)
  
  // Max angle to correct
  var maxCorrectionAngleDegrees: Float = 2
  
  
  var movingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 20, initialValue: 0.0)
  
  static var enableStraightening: Bool = true
  static var detectedAngle: String = ""
  
  func makeStraightenParams(
    textureWidth: Int
  ) -> StraightenParams {
    let halfSize = halfSampleTextureSize
    
    let leftLeft  = Int(floor(Float(textureWidth) * halfSize.0))
    let leftRight = Int( ceil(Float(textureWidth) * halfSize.1))
    let width = leftRight - leftLeft
    
    let rightLeft = Int(floor(Float(textureWidth) * (1 - halfSize.1)))
    
    let deltaBetweenCenters = Float(rightLeft - leftLeft)
    let maxYOffset = max(1, tan(maxCorrectionAngleDegrees * Float.pi / 180) * deltaBetweenCenters)
     
    return StraightenParams(
      leftX: ushort(leftLeft),
      rightX: ushort(rightLeft),
      width: ushort(width),
      offsetYMin: Int16(-maxYOffset),
      offsetYMax: Int16( maxYOffset)
    )
  }
  
  var       rowMeanTexture: MTLTexture?
  var         deltaTexture: MTLTexture?
  var deltaAveragedTexture: MTLTexture?
  var deltaAveragedCPU: UnsafeMutablePointer<Float>?
  var    straightenedImage: MTLTexture?
  
  var straightenMeanPSO: MTLComputePipelineState
  var straightenDeltaSquaredPSO: MTLComputePipelineState
  var rowSquashEncoder: MPSUnaryImageKernel
  var colSquashEncoder: MPSUnaryImageKernel
  
  
  var cannyTextureBuffer: MTLTexture?
  var houghOutputBuffer: MTLBuffer?
  var houghTexture: MTLTexture?
  var symmetryOutputBuffer: MTLBuffer?
  
  let straightenOutputPSO: MTLRenderPipelineState
  
    
  init() {
    straightenOutputPSO = Self.makeStraightenOutputPSO()
    straightenMeanPSO = Self.makeStraightenMeanPSO()
    straightenDeltaSquaredPSO = Self.makeStraightenDeltaSquaredPSO()
    rowSquashEncoder = MPSImageReduceRowMean(device: Renderer.device)
    colSquashEncoder = MPSImageReduceColumnMean(device: Renderer.device)
  }
  
  static func makeStraightenMeanPSO() -> MTLComputePipelineState {
    do {
      guard let function = Renderer.library.makeFunction(name: "straighten_mean_left_right") else { fatalError() }
      return try Renderer.device.makeComputePipelineState(function: function)
    } catch {
      fatalError()
    }
  }

  
  static func makeStraightenDeltaSquaredPSO() -> MTLComputePipelineState {
    do {
      guard let function = Renderer.library.makeFunction(name: "straighten_left_right_delta_squared") else { fatalError() }
      return try Renderer.device.makeComputePipelineState(function: function)
    } catch {
      fatalError()
    }
  }
  
  static func makeStraightenOutputPSO() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_plonk_texture",
      fragment: "fragment_straighten"
    )
//    pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  static func makeStraightenRenderPassDescriptor(outputTexture: MTLTexture) -> MTLRenderPassDescriptor {
    let renderPassDescriptor = MTLRenderPassDescriptor()
    
    let attachment = renderPassDescriptor.colorAttachments[0]
    attachment?.texture = outputTexture
    
    attachment?.loadAction = .dontCare
    attachment?.storeAction = .store
    return renderPassDescriptor
  }
  
  func makeTextureBuffers(texture: MTLTexture) throws {
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: texture.width,
      height: texture.height,
      mipmapped: false
    )
    textureDescriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
    
    straightenedImage = Renderer.device.makeTexture(descriptor: textureDescriptor)
    if straightenedImage == nil {
      fatalError()
    }
    straightenedImage?.label = "Straightened image"
    
    
    textureDescriptor.usage = [.shaderWrite, .shaderRead]
    let params = makeStraightenParams(textureWidth: texture.width)
    textureDescriptor.width = 2
    
    rowMeanTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    
    if rowMeanTexture == nil {
      fatalError()
    }
    rowMeanTexture?.label = "Left/right row mean texture"
    
    // range(i) x image height
    textureDescriptor.pixelFormat = .r16Float // HALF
    textureDescriptor.width = Int(1 + params.offsetYMax - params.offsetYMin) // symmetrical around offset y=0
    deltaTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    
    if deltaTexture == nil {
      fatalError()
    }
    deltaTexture?.label = "Delta sample texture"
    
    // range(i) x 1
    textureDescriptor.pixelFormat = .r32Float // FLOAT
    textureDescriptor.height = 1
    deltaAveragedTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    if deltaAveragedTexture == nil {
      fatalError()
    }
    deltaAveragedTexture?.label = "Delta averaged texture"
    
    deltaAveragedCPU = UnsafeMutablePointer<Float>.allocate(capacity: textureDescriptor.width)
  }
  
  
  func straightenCalculateLeftRightMean(commandBuffer: MTLCommandBuffer, image: MTLTexture, params: StraightenParams) {
    commandBuffer.pushDebugGroup("Straighten; find L/R mean")
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
        
    var params = params
    computeEncoder.setComputePipelineState(straightenMeanPSO)
    computeEncoder.setBytes(
      &params,
      length: MemoryLayout<StraightenParams>.stride,
      index: 0
    )
    
    computeEncoder.setTexture(image, index: 0)
    computeEncoder.setTexture(rowMeanTexture, index: 1)
    
    let threadsPerThreadgroup = MTLSize(
      width: min(
        Int(image.height),
        straightenMeanPSO.maxTotalThreadsPerThreadgroup
      ),
      height: 1,
      depth: 1
    )
    
    computeEncoder.dispatchThreads(
      MTLSize(
        width: image.height,
        height: 2, // one thread for left/right
        depth: 1
      ),
      threadsPerThreadgroup: threadsPerThreadgroup
    )
    
    commandBuffer.popDebugGroup()
    computeEncoder.endEncoding()
  }
  
  func straightenCalculateDeltaSquared(commandBuffer: MTLCommandBuffer, image: MTLTexture, params: StraightenParams) {
    commandBuffer.pushDebugGroup("Find L/R per-row deltas")
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
    
    computeEncoder.setComputePipelineState(straightenDeltaSquaredPSO)
    var params = params;
    computeEncoder.setBytes(
      &params,
      length: MemoryLayout<StraightenParams>.stride,
      index: 0
    )
    
    computeEncoder.setTexture(deltaTexture, index: 0)
    computeEncoder.setTexture(rowMeanTexture, index: 1)

    let threadsPerThreadgroup = MTLSize(
      width: min(
        Int(image.height),
        straightenDeltaSquaredPSO.maxTotalThreadsPerThreadgroup
      ),
      height: 1,
      depth: 1
    )
    
    computeEncoder.dispatchThreads(
      MTLSize(
        width: image.height,
        height: Int(1 + params.offsetYMax - params.offsetYMin), // Each thread calculates a single delta with a given offset. + 1 as zero offset is calculated as well
        depth: 1
      ),
      threadsPerThreadgroup: threadsPerThreadgroup
    )
    computeEncoder.endEncoding()
    
    commandBuffer.popDebugGroup()
  }
  
  func determineStraightenTransform(image: MTLTexture) throws -> simd_float3x3 {
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer() else {
      fatalError()
    }
    commandBuffer.label = "Determine straightening angle"
    if rowMeanTexture == nil || rowMeanTexture!.height != image.height {
      try makeTextureBuffers(texture: image)
    }
    
    // Copy segments from the left and right sides of the image into their own textures
    let params = makeStraightenParams(textureWidth: image.width)
    straightenCalculateLeftRightMean(commandBuffer: commandBuffer, image: image, params: params)
    
    // Calculate the difference squared between the left and right halves of the image
    // Do this multiple times by sliding/offsetting the right image up/down by a few pixels
    straightenCalculateDeltaSquared(commandBuffer: commandBuffer, image: image, params: params)
    
    // For each offset, determine the average difference. Due to the presence of strong horizontal lines,
    // this should be lowest when you have the correct angle
    commandBuffer.pushDebugGroup("MPS col reduce")
    // Not sure why, but finding average changes values from [0, 1] to around [0, 30]
    colSquashEncoder.encode(
      commandBuffer: commandBuffer,
      sourceTexture: deltaTexture!,
      destinationTexture: deltaAveragedTexture!
    )
    commandBuffer.popDebugGroup()
    
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    Self.copyTexture(source: deltaAveragedTexture!, destination: deltaAveragedCPU!)
    let averageDelta = Self.copyPixelsToArray(source: deltaAveragedCPU!, length: deltaTexture!.width)
      .enumerated().map({ $0.1 * Float(image.height) / ((Float(image.height) - 2 * abs(Float(params.offsetYMin) + Float($0.0)))) })
    // Textures initialized to 0. Top and bottom i pixels are ignored since the two images do not overlap
    // with the offset, so correct this
    let angle = calculateCorrectionAngle(avgDelta: averageDelta, params: params)
    
    movingAverage.input(angle)
    
    let averagedAngle = movingAverage.output()
    Self.detectedAngle = String(format: "%.1f", averagedAngle * 180 / Float.pi)
    
    return createRotationMatrix(angle: averagedAngle, aspectRatio: Float(image.width) / Float(image.height))
  }
  
  func calculateCorrectionAngle(avgDelta: [Float], params: StraightenParams) -> Float {
    let dx = Float(params.rightX - params.leftX)
    let sortedAngles: [(angle: Float, delta: Float)] = avgDelta.enumerated().map { (i, delta) in
      let dy: Float = Float(params.offsetYMin) + Float(i)
      let angle = atan2(-dy, dx)
      return (angle: angle, delta: delta)
    }.sorted(by: { $0.delta < $1.delta })
    
    // TODO somehow detect when not viewing a keyboard
    return sortedAngles.first!.angle
  }
  
  func createRotationMatrix(angle: Float, aspectRatio: Float = Float(16.0/9.0)) -> simd_float3x3 {
    let rotation = float3x3(rows: [
      [cos(angle), -sin(angle), 0],
      [sin(angle),  cos(angle), 0],
      [        0,            0, 1]
    ])
    
    let translation = float3x3(rows: [
      [1, 0, 0.5],
      [0, 1, 0.5],
      [0, 0, 1  ]
    ])
    
    var aspect = float3x3(1)
    aspect.columns.0.x = aspectRatio
    
    return translation * aspect.inverse * rotation * aspect * translation.inverse
  }

  // Copies image from MTLTexture to a CPU buffer with the correct amount of memory allocated
  static func copyTexture<T>(source: MTLTexture, destination: UnsafeMutablePointer<T>) {
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes
    source.getBytes(
      destination,
      bytesPerRow: source.bufferBytesPerRow,
      from: MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: source.width, height: source.height, depth: 1)
      ),
      mipmapLevel: 0
    )
  }
  
  static func copyPixelsToArray<T>(source: UnsafeMutablePointer<T>, length: Int) -> [T] {
    var output: [T] = []
    var pointer = source
    
    for _ in 0..<length {
      output.append(pointer.pointee)
      pointer = pointer.advanced(by: 1)
    }
    
    return output
  }
  
  
  
  public func straighten(image: MTLTexture, angle: Float? = nil) -> MTLTexture {
    if !Self.enableStraightening {
      return image
    }
    
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer() else {
      fatalError()
    }
    commandBuffer.label = "Straighten image"
    
    var transform = float3x3(1) // identity
    
    if angle != nil {
      transform = createRotationMatrix(angle: angle!, aspectRatio: Float(image.width) / Float(image.height))
    } else {
      do {
        transform = try determineStraightenTransform(image: image)
      } catch {
        fatalError()
      }
    }
    commandBuffer.pushDebugGroup("Straighten image transform")
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(
      descriptor: Self.makeStraightenRenderPassDescriptor(outputTexture: straightenedImage!)
    ) else { fatalError() }
    
    renderEncoder.setRenderPipelineState(straightenOutputPSO)
    
    renderEncoder.setTriangleFillMode(.fill)
    
    renderEncoder.setFragmentTexture(image, index: 0)
    renderEncoder.setFragmentBytes(
      &transform,
      length: MemoryLayout<simd_float3x3>.stride,
      index: 0
    )
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    
    renderEncoder.endEncoding()
    commandBuffer.commit()
//    let time = CFAbsoluteTimeGetCurrent()
    commandBuffer.waitUntilCompleted()
//    print("Straighten rendering took \(CFAbsoluteTimeGetCurrent() - time)")
    commandBuffer.popDebugGroup()
    
    return straightenedImage!
  }
}
