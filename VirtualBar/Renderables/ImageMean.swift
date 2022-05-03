import MetalKit
import MetalPerformanceShaders


public typealias float2 = SIMD2<Float>

public class ImageMean: Renderable {
  private var _texture: MTLTexture!
  
  public var texture: MTLTexture! {
    set {
      self._texture = newValue
      runMPS(texture: newValue)
    }
    get {
      return self._texture
    }
  }
  public static var threshold: Float = 0.02
  public static var activeAreaHeightFractionRange: ClosedRange<Float> = 0.04...0.06
  
  func activeAreaHeightRange(imageHeight: Int) -> ClosedRange<Int> {
    let fraction = Self.activeAreaHeightFractionRange
    return Int(floor(fraction.lowerBound * Float(imageHeight)))...Int(ceil(fraction.upperBound * Float(imageHeight)))
  }
  
  var computedTexture: MTLTexture!
  
  
  var squashTextureBuffer: MTLTexture?
  var sobelTextureBuffer: MTLTexture?
  var cpuImageColumnBufferFloat: UnsafeMutablePointer<Float>?
  var cpuImageColumnBuffer4UInt8: UnsafeMutablePointer<SIMD4<UInt8>>?
  
  let pipelineState: MTLRenderPipelineState
  var threshold: Float = 0
  
  let activeAreaSelector = ActiveAreaSelector()
  
  public static var activeArea: [float2] = []
    
  init() {
    let textureLoader = MTKTextureLoader(device: Renderer.device)
    do {
      _texture = try textureLoader.newTexture(
        name: "test", // File in .xcassets texture set
        scaleFactor: 1.0,
        bundle: Bundle.main,
        options: nil
      )
    } catch let error { fatalError(error.localizedDescription) }
    pipelineState = Self.makePipeline()
    runMPS(texture: _texture)
  }
  
  
  func makeImageBuffers(texture: MTLTexture) {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: texture.pixelFormat,
      width: 1,
      height: texture.height,
      mipmapped: false
    )
    descriptor.usage = [.shaderWrite, .shaderRead]
    
    guard let squashTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor) else {
      fatalError()
    }
    
    descriptor.pixelFormat = .r32Float
    guard let sobelTextureBuffer = Renderer.device.makeTexture(descriptor: descriptor) else {
      fatalError()
    }
    
    squashTextureBuffer.label = "Squash texture buffer"
    sobelTextureBuffer.label = "Sobel texture buffer"
    self.squashTextureBuffer = squashTextureBuffer
    self.sobelTextureBuffer = sobelTextureBuffer
    
    cpuImageColumnBufferFloat  = UnsafeMutablePointer<Float>.allocate(capacity: texture.height)
    cpuImageColumnBuffer4UInt8 = UnsafeMutablePointer<SIMD4<UInt8>>.allocate(capacity: texture.height)
  }
  
  func runMPS(texture: MTLTexture) {
    let startTime = CFAbsoluteTimeGetCurrent()
    guard let commandBuffer = Renderer.commandQueue.makeCommandBuffer()
    else { fatalError() }
    commandBuffer.label = "Active area detection"
    if squashTextureBuffer == nil || squashTextureBuffer?.height != texture.height {
      makeImageBuffers(texture: texture)
    }

    commandBuffer.pushDebugGroup("MPS row reduce + sobel")
    let squashShader: MPSUnaryImageKernel = MPSImageReduceRowMean(device: Renderer.device)
    squashShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: texture,
      destinationTexture: squashTextureBuffer!
    )
    
    let derivativeShader = MPSImageSobel(device: Renderer.device)
    derivativeShader.encode(
      commandBuffer: commandBuffer,
      sourceTexture: squashTextureBuffer!,
      destinationTexture: sobelTextureBuffer!
    )
    
    commandBuffer.commit()
    
    commandBuffer.waitUntilCompleted()
    commandBuffer.popDebugGroup()
    // Squash + Sobel + simple symmetry compute: ~1.3 ms
//    print("GPU Full Pipeline Duration:", CFAbsoluteTimeGetCurrent() - startTime)
    
    Straighten.copyTexture(source: squashTextureBuffer!, destination: cpuImageColumnBuffer4UInt8!)
    
    let squashOutput: [Float] = (Straighten.copyPixelsToArray(
      source: cpuImageColumnBuffer4UInt8!,
      length: texture.height
    ) as [SIMD4<UInt8>]).map({
      let val = float3(Float($0.x), Float($0.y), Float($0.z))/255
      return length(val)/3
    })
    
    
    Straighten.copyTexture(source: sobelTextureBuffer!, destination: cpuImageColumnBufferFloat!)

    let sobelOutput: [Float] = Straighten.copyPixelsToArray(
      source: cpuImageColumnBufferFloat!,
      length: texture.height
    )
    
//    var variance

    let sizeRange = self.activeAreaHeightRange(imageHeight: texture.height)
    let candidateAreas = ActiveAreaDetector.detectCandidateAreas(
      sobelOutput: sobelOutput,
      squashOutput: squashOutput,
      threshold: Self.threshold,
      sizeRange: sizeRange
    )
    
    activeAreaSelector.update(candidates: candidateAreas, sizeRange: sizeRange)
    let currentBestGuess = activeAreaSelector.getActiveArea()
    
    if currentBestGuess == nil {
      Self.activeArea = []
    } else {
      Self.activeArea = activeAreaSelector.getAllAreasSorted().map {[
        $0[0] / Float(sobelOutput.count),
        $0[1] / Float(sobelOutput.count)
//        ($0[1] + ($0[1] - $0[0]) * GestureRecognizer().activeAreaFudgeScale) / Float(sobelOutputFloat.count)
      ]}
    }
  }
  
  
  static func makePipeline() -> MTLRenderPipelineState {
    let pipelineDescriptor = buildPartialPipelineDescriptor(
      vertex: "vertex_plonk_texture_mirrored_horizontal",
      fragment: "fragment_image_mean"
    )
    do {
      let pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      return pipelineState
    } catch let error { fatalError(error.localizedDescription) }
  }
  
  
  
  public func draw(renderEncoder: MTLRenderCommandEncoder) {
    renderEncoder.setRenderPipelineState(pipelineState)
    
    renderEncoder.setTriangleFillMode(.fill)
    renderEncoder.setFragmentTexture(squashTextureBuffer, index: 1)
    renderEncoder.setFragmentTexture(sobelTextureBuffer, index: 2)
    
    renderEncoder.setFragmentBytes(
      &Self.threshold,
      length: MemoryLayout<Float>.stride,
      index: 3
    )
    
    if Self.activeArea.isEmpty {
      Self.activeArea = [[-1, -1]]
      // Dies if empty array passed. Not sure how to solve it
    }
    
    renderEncoder.setFragmentTexture(texture, index: 0)
        
    
    renderEncoder.setFragmentBytes(
      &Self.activeArea,
      length: MemoryLayout<float2>.stride * Self.activeArea.count,
      index: 4
    )
    
    var count: Int = Self.activeArea.count
    renderEncoder.setFragmentBytes(
      &count,
      length: MemoryLayout<Int>.stride,
      index: 5
    )
   
    
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
  }
}
