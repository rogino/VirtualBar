import MetalKit
import MetalPerformanceShaders

func toRad(deg: Float) -> Float {
  return deg * Float.pi / 180
}


extension HoughConfig {
  mutating func updateBufferSize(pixelFormat: MTLPixelFormat) throws {
//  https://stackoverflow.com/questions/62449741/how-to-set-up-byte-alignment-from-a-mtlbuffer-to-a-2d-mtltexture
    let alignment = Renderer.device.minimumLinearTextureAlignment(for: pixelFormat)
    
    func roundUp(n: Int, alignment: Int) -> Int {
      return ((n + alignment - 1) / alignment) * alignment;
    }
    var width = Int(ceil(length(float2(imageSize)) / rStep))
    if (pixelFormat == .r16Uint) {
      let bitsPerPixel = MemoryLayout<UInt16>.stride
      let bytesPerRow = bitsPerPixel * width
      let alignedBytesPerRow = roundUp(n: bytesPerRow, alignment: alignment)
      if (alignedBytesPerRow % bitsPerPixel != 0) {
        throw fatalError()
      }
      width = alignedBytesPerRow / bitsPerPixel
    } else {
      throw fatalError()
    }
    
    bufferSize = SIMD2<Int32>(
      Int32(width),
      Int32(ceil(2 * thetaRange / thetaStep))
    )
  }
}

public class Straighten: Renderable {
  public var texture: MTLTexture!
//  public static var threshold: Float = 0.03
//  public static var activeAreaHeightFractionRange: ClosedRange<Float> = 0.04...0.053
  
//  var computedTexture: MTLTexture!
 
  // this section of the left half of texture used in averaging. right is symmetrical
  var halfSampleTextureSize: (Float, Float) = (0.2, 0.4)
  
  func getPixelCoordinatesForHalfSample(
    textureWidth: Int
  ) -> CopyLeftRightConfig {
    let halfSize = halfSampleTextureSize
    
    let leftLeft  = Int(floor(Float(textureWidth) * halfSize.0))
    let leftRight = Int( ceil(Float(textureWidth) * halfSize.1))
    let width = leftRight - leftLeft
    
    let rightLeft = Int(floor(Float(textureWidth) * (1 - halfSize.1)))
    return CopyLeftRightConfig(
      leftX: ushort(leftLeft),
      rightX: ushort(rightLeft),
      width: ushort(width)
    )
  }
  
  
  var  leftSampleTexture: MTLTexture?
  var rightSampleTexture: MTLTexture?
  var straightenCopyPSO: MTLComputePipelineState
  
  
  var cannyTextureBuffer: MTLTexture?
  var houghOutputBuffer: MTLBuffer?
  var houghTexture: MTLTexture?
  var cpuImageColumnBuffer: UnsafeMutablePointer<SIMD4<UInt8>>?
  var symmetryOutputBuffer: MTLBuffer?
  
  let pipelineState: MTLRenderPipelineState
  
  //  let houghComputePSO: MTLComputePipelineState
//  let houghClearComputePSO: MTLComputePipelineState
  var threshold: Float = 0
  
  var houghConfig = HoughConfig(
    thetaRange: toRad(deg: 4),
    thetaStep: toRad(deg: 0.1),
    rStep: 1.0,
    imageSize: [0, 0],
    bufferSize: [0, 0]
  )
  
    
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
//    MTLComm
//    houghClearComputePSO = Self.makeHoughClearComputePipeline()
  }
  
  static func makeStraightenCopyPSO() -> MTLComputePipelineState {
    do {
      guard let function = Renderer.library.makeFunction(name: "copy_left_right_samples") else { fatalError() }
      return try Renderer.device.makeComputePipelineState(function: function)
    } catch {
      fatalError()
    }
  }
  
  
  func makeLeftRightSampleImageBuffers(texture: MTLTexture) throws {
    let pixelRange = getPixelCoordinatesForHalfSample(textureWidth: texture.width)
    let pixelWidth = pixelRange.width
    
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
//      pixelFormat: .rgba16Float,
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
  }
  
  func straightenImage(/*commandBuffer: MTLCommandBuffer, */image: MTLTexture) throws {
//          let encoder = commandBuffer.makeBlitCommandEncoder(
//            descriptor: MTLBlitPassDescriptor()
//          ) else { fatalError() }
//
    if leftSampleTexture == nil || leftSampleTexture!.height != image.height {
      try makeLeftRightSampleImageBuffers(texture: texture)
    }
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer() else {
      return
    }
    
    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return }
        
    var config = getPixelCoordinatesForHalfSample(textureWidth: image.width)
    computeEncoder.setComputePipelineState(straightenCopyPSO)
    computeEncoder.setBytes(
      &config,
      length: MemoryLayout<CopyLeftRightConfig>.stride,
      index: 0
    )
    
    computeEncoder.setTexture(image, index: 0)
    computeEncoder.setTexture(leftSampleTexture, index: 1)
    computeEncoder.setTexture(rightSampleTexture, index: 2)
    
    let threadsPerThreadgroup = MTLSize(
      width: min(
        Int(config.width),
        straightenCopyPSO.maxTotalThreadsPerThreadgroup
      ),
      height: 1,
      depth: 1
    )
    
    computeEncoder.dispatchThreads(
      MTLSize(
        width: image.height,
        height: 2,
        depth: 1
      ),
      threadsPerThreadgroup: threadsPerThreadgroup
    )

    computeEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
  }

  static func makeHoughComputePipeline() -> MTLComputePipelineState {
    do {
      let function = Renderer.library.makeFunction(name: "kernel_hough")!
      return try Renderer.device.makeComputePipelineState(function: function)
    } catch {
      fatalError()
    }
  }
  
  static func makeHoughClearComputePipeline() -> MTLComputePipelineState {
    do {
      let function = Renderer.library.makeFunction(name: "kernel_hough_clear")!
      return try Renderer.device.makeComputePipelineState(function: function)
    } catch {
      fatalError()
    }
  }
  

//
//  func runHough(commandBuffer: MTLCommandBuffer, texture: MTLTexture) {
//    commandBuffer.pushDebugGroup("Hough")
//    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
//    else { return }
//    let threadsPerGroup = MTLSize(
//      width: houghComputePSO.threadExecutionWidth,
//      height: houghComputePSO.maxTotalThreadsPerThreadgroup / houghComputePSO.threadExecutionWidth,
//      depth: 1
//    )
//
//    computeEncoder.setComputePipelineState(houghClearComputePSO)
//    computeEncoder.setBytes(&houghConfig, length: MemoryLayout<HoughConfig>.stride, index: 0)
//    computeEncoder.setBuffer(houghOutputBuffer, offset: 0, index: 1)
//    computeEncoder.dispatchThreads(
//      MTLSize(
//        width: Int(houghConfig.bufferSize.x),
//        height: Int(houghConfig.bufferSize.y),
//        depth: 1
//      ),
//      threadsPerThreadgroup: threadsPerGroup
//    )
//
//
//    computeEncoder.setComputePipelineState(houghComputePSO)
//    computeEncoder.setTexture(texture, index: 0)
//
//    computeEncoder.dispatchThreads(
//      MTLSize(
//        width: texture.width,
//        height: texture.height,
//        depth: 1
//      ),
//      threadsPerThreadgroup: threadsPerGroup
//    )
//
//    computeEncoder.endEncoding()
//    commandBuffer.popDebugGroup()
////    commandBuffer.addCompletedHandler { _ in
////      houghOutputTexture = texture
////    }
////    commandBuffer.commit()
////    commandBuffer.waitUntilCompleted()
//  }
//
//
//  func makeImageBuffers(texture: MTLTexture) {
//    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
////      pixelFormat: .a8Unorm, // Fails with 'texture format 1  must be writable.'
//      pixelFormat: .r16Float,
//      width: texture.width,
//      height: texture.height,
//      mipmapped: false
//    )
//    descriptor.usage = [.shaderWrite, .shaderRead]
//
//    guard let cannyTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor)
//    else {
//      fatalError()
//    }
//    cannyTextureBuffer.label = "Canny"
//    self.cannyTextureBuffer = cannyTextureBuffer
//
//
//    houghConfig.imageSize = [Int32(texture.width), Int32(texture.height)]
//    do {
//      try houghConfig.updateBufferSize(pixelFormat: .r16Uint)
//    } catch {
//      fatalError()
//    }
//
//    houghOutputBuffer = Renderer.device.makeBuffer(
//      length: MemoryLayout<UInt16>.stride * Int(houghConfig.bufferSize.x) * Int(houghConfig.bufferSize.y)
//    )!
//    houghOutputBuffer?.label = "Hough output"
//
//    let houghTextureDescriptor = MTLTextureDescriptor()
//    houghTextureDescriptor.pixelFormat = .r16Uint
//    houghTextureDescriptor.width = Int(houghConfig.bufferSize.x)
//    houghTextureDescriptor.height = Int(houghConfig.bufferSize.y)
//    print("Hough size", houghConfig.bufferSize)
//    houghTextureDescriptor.storageMode = houghOutputBuffer!.storageMode
//    houghTexture = houghOutputBuffer!.makeTexture(
//      descriptor: houghTextureDescriptor,
//      offset: 0,
//      bytesPerRow: Int(houghConfig.bufferSize.x) * MemoryLayout<UInt16>.stride
//    )
//    houghTexture?.label = "Hough texture"
//  }
  
//  func runMPS(texture: MTLTexture) {
//    let startTime = CFAbsoluteTimeGetCurrent()
//    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
//    else { fatalError() }
//    commandBuffer.pushDebugGroup("Canny")
//    if cannyTextureBuffer == nil || cannyTextureBuffer?.height != texture.height {
//      makeImageBuffers(texture: texture)
//    }
//
//    let cannyShader: MPSUnaryImageKernel = (device: Renderer.device)
//    cannyShader.encode(
//      commandBuffer: commandBuffer,
//      sourceTexture: texture,
//      destinationTexture: cannyTextureBuffer!
//    )
//    commandBuffer.popDebugGroup()
//
////    let derivativeShader = MPSImageSobel(device: Renderer.device)
////    derivativeShader.encode(
////      commandBuffer: commandBuffer,
////      sourceTexture: squashTextureBuffer!,
////      destinationTexture: sobelTextureBuffer!
////    )
//
//    runHough(commandBuffer: commandBuffer, texture: cannyTextureBuffer!)
//    commandBuffer.commit()
//
//    commandBuffer.waitUntilCompleted()
//    // Squash + Sobel + simple symmetry compute: ~1.3 ms
////    print("GPU Full Pipeline Duration:", CFAbsoluteTimeGetCurrent() - startTime)
//
//    return
//
//  }
  
  // Copies single column image from MTLTexture to a CPU buffer with the correct amount of memory allocated
  static func copyTexture(source: MTLTexture, destination: UnsafeMutablePointer<SIMD4<UInt8>>) {
    // https://developer.apple.com/documentation/metal/mtltexture/1515751-getbytes
    source.getBytes(
      destination,
      bytesPerRow: MemoryLayout<SIMD4<UInt8>>.stride,
      from: MTLRegion(
        origin: MTLOrigin(x: 0, y: 0, z: 0),
        size: MTLSize(width: 1, height: source.height, depth: 1)
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
    do {
      try straightenImage(image: texture)
    } catch {
      fatalError()
    }
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    
    renderEncoder.setFragmentTexture(texture, index: 0)
    renderEncoder.setFragmentTexture(leftSampleTexture, index: 1)
    renderEncoder.setFragmentTexture(rightSampleTexture, index: 2)
//    renderEncoder.setFragmentBuffer(houghTexture, offset: 0, index: 1)
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
