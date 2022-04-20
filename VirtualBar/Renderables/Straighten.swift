import MetalKit
import MetalPerformanceShaders

public class Straighten: Renderable {
  public var texture: MTLTexture!
  
  // this section of the left half of texture used in averaging. right is symmetrical
  var halfSampleTextureSize: (Float, Float) = (0.2, 0.4)
  
  // Max angle to correct
  var maxCorrectionAngleDegrees: Float = 4
  
  func straightenParams(
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
  
  var    leftSampleTexture: MTLTexture?
  var   rightSampleTexture: MTLTexture?
  var  leftAveragedTexture: MTLTexture?
  var rightAveragedTexture: MTLTexture?
  var         deltaTexture: MTLTexture?
  var deltaAveragedTexture: MTLTexture?
  var deltaAveragedCPU: UnsafeMutablePointer<Float>?
  
  var straightenCopyPSO: MTLComputePipelineState
  var straightenDeltaSquaredPSO: MTLComputePipelineState
  var rowSquashEncoder: MPSUnaryImageKernel
  var colSquashEncoder: MPSUnaryImageKernel
  
  
  var cannyTextureBuffer: MTLTexture?
  var houghOutputBuffer: MTLBuffer?
  var houghTexture: MTLTexture?
  var symmetryOutputBuffer: MTLBuffer?
  
  let pipelineState: MTLRenderPipelineState
  
    
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
    straightenCopyPSO = Self.makeStraightenCopyPSO()
    straightenDeltaSquaredPSO = Self.makeStraightenDeltaSquaredPSO()
    rowSquashEncoder = MPSImageReduceRowMean(device: Renderer.device)
    colSquashEncoder = MPSImageReduceColumnMean(device: Renderer.device)
  }
  
  static func makeStraightenCopyPSO() -> MTLComputePipelineState {
    do {
      guard let function = Renderer.library.makeFunction(name: "copy_left_right_samples") else { fatalError() }
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
  
  
  func makeTextureBuffers(texture: MTLTexture) throws {
    let params = straightenParams(textureWidth: texture.width)
    let pixelWidth = params.width
    
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: Int(pixelWidth),
      height: texture.height,
      mipmapped: false
    )
    textureDescriptor.usage = [.shaderWrite, .shaderRead]
    
    leftSampleTexture  = Renderer.device.makeTexture(descriptor: textureDescriptor)
    rightSampleTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)
    
    if leftSampleTexture == nil || rightSampleTexture == nil {
      fatalError()
    }
    leftSampleTexture?.label = "Left sample texture"
    rightSampleTexture?.label = "Right sample texture"
    
    
    // 1 x image height
    textureDescriptor.width = 1;
    leftAveragedTexture  = Renderer.device.makeTexture(descriptor: textureDescriptor)
    rightAveragedTexture = Renderer.device.makeTexture(descriptor: textureDescriptor)

    if leftAveragedTexture == nil || rightAveragedTexture == nil {
      fatalError()
    }
    leftSampleTexture?.label = "Left averaged sample texture"
    rightSampleTexture?.label = "Right averaged sample texture"
    
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
  
  
  func straightenCopyLR(commandBuffer: MTLCommandBuffer, image: MTLTexture, params: StraightenParams) {
    commandBuffer.pushDebugGroup("Copying L/R")
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
        
    var params = params
    computeEncoder.setComputePipelineState(straightenCopyPSO)
    computeEncoder.setBytes(
      &params,
      length: MemoryLayout<StraightenParams>.stride,
      index: 0
    )
    
    computeEncoder.setTexture(image, index: 0)
    computeEncoder.setTexture(leftSampleTexture, index: 1)
    computeEncoder.setTexture(rightSampleTexture, index: 2)
    
    // TODO do averaging in here? Use memory barriers for each threadgroup, atomically find average, write to thread id 0 position
    // In second pass sum averages from threadgroups divide
    let threadsPerThreadgroup = MTLSize(
      width: min(
        Int(params.width),
        straightenCopyPSO.maxTotalThreadsPerThreadgroup
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
    
    computeEncoder.endEncoding()
    commandBuffer.popDebugGroup()
  }
  
  func straightenCalculateDeltaSquared(commandBuffer: MTLCommandBuffer, image: MTLTexture, params: StraightenParams) {
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
    
    commandBuffer.pushDebugGroup("Delta")
    computeEncoder.setComputePipelineState(straightenDeltaSquaredPSO)
    var params = params;
    computeEncoder.setBytes(
      &params,
      length: MemoryLayout<StraightenParams>.stride,
      index: 0
    )
    
    computeEncoder.setTexture(deltaTexture, index: 0)
    computeEncoder.setTexture(leftAveragedTexture, index: 1)
    computeEncoder.setTexture(rightAveragedTexture, index: 2)

    let threadsPerThreadgroup = MTLSize(
      width: min(
        Int(image.height),
        straightenCopyPSO.maxTotalThreadsPerThreadgroup
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
  
  func straightenImage(image: MTLTexture) throws -> simd_float3x3 {
    if leftSampleTexture == nil || leftSampleTexture!.height != image.height {
      try makeTextureBuffers(texture: texture)
    }
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer() else {
      return simd_float3x3(1)
    }
    
    let params = straightenParams(textureWidth: texture.width)
    straightenCopyLR(commandBuffer: commandBuffer, image: image, params: params)
    
    commandBuffer.pushDebugGroup("MPS row reduce")
    rowSquashEncoder.encode(
      commandBuffer: commandBuffer,
      sourceTexture: leftSampleTexture!,
      destinationTexture: leftAveragedTexture!
    )
    rowSquashEncoder.encode(
      commandBuffer: commandBuffer,
      sourceTexture: rightSampleTexture!,
      destinationTexture: rightAveragedTexture!
    )
    commandBuffer.popDebugGroup()
    
    straightenCalculateDeltaSquared(commandBuffer: commandBuffer, image: image, params: params)
    
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
    let angle = calculateCorrectionAngle(avgDelta: averageDelta, params: params)
    
    return createRotationMatrix(angle: angle)
  }
  
  func calculateCorrectionAngle(avgDelta: [Float], params: StraightenParams) -> Float {
    let dx = Float(params.rightX - params.leftX)
    let sortedAngles: [(angle: Float, delta: Float)] = avgDelta.enumerated().map { (i, delta) in
      let dy: Float = Float(params.offsetYMin) + Float(i)
      let angle = atan2(-dy, dx)
      return (angle: angle, delta: delta)
    }.sorted(by: { $0.delta < $1.delta })
    return sortedAngles.first!.angle
  }
  
  func createRotationMatrix(angle: Float) -> simd_float3x3 {
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
    
    return translation * rotation * translation.inverse
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
  
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_straighten",
      fragment: "fragment_straighten"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    var transform = float3x3(1) // identity
    do {
      transform = try straightenImage(image: texture)
    } catch {
      fatalError()
    }
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    
    renderEncoder.setFragmentTexture(texture, index: 0)
    renderEncoder.setFragmentBytes(
      &transform,
      length: MemoryLayout<simd_float3x3>.stride,
      index: 0
    )
    renderEncoder.setFragmentTexture(leftAveragedTexture, index: 1)
    renderEncoder.setFragmentTexture(rightAveragedTexture, index: 2)
    renderEncoder.setFragmentTexture(deltaAveragedTexture, index: 3)
//    renderEncoder.setFragmentTexture(deltaTexture, index: 3)
//    renderEncoder.setFragmentBuffer(houghTexture, offset: 0, index: 1)
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
