import MetalKit
import AVFoundation

class Renderer: NSObject {
  static var device: MTLDevice!
  static var commandQueue: MTLCommandQueue!
  static var library: MTLLibrary!

  var pipelineState: MTLRenderPipelineState!
  
  var straightener: Straighten
  
  var renderables: [Renderable] = []
  
  let fingerDetector: FingerDetector
  var fingerPoints: [simd_float3] = []
  
  static var aspect: Float = 1.0
  
  var cameraTexture: MTLTexture? = nil
  var straightenedCameraTexture: MTLTexture? = nil
  
  var cameraTextureCache: CVMetalTextureCache?
  
  var imageMean: ImageMean
  var fingerPointsRenderer: FingerPointsRenderer

  public convenience init(metalView: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("No metal-capable device found")
    }
    self.init(metalView: metalView, device: device)
  }
  
  public init(metalView: MTKView, device: MTLDevice) {
    metalView.device = device
    metalView.clearColor = MTLClearColor(red: 0, green: 0.4, blue: 0, alpha: 1)
//    metalView.depthStencilPixelFormat = .depth32Float
    
    Self.aspect = Float(metalView.bounds.width)/Float(metalView.bounds.height)
    Self.device = device
    Self.commandQueue = device.makeCommandQueue()!
    Self.library = device.makeDefaultLibrary()
    
//    self.depthStencilState = Self.buildDepthStencilState()!
    
    self.straightener = Straighten()
    self.imageMean = ImageMean()
    self.fingerPointsRenderer = FingerPointsRenderer()
    
    self.fingerDetector = FingerDetector(activeAreaSelector: imageMean.activeAreaSelector)
    
    originalTexture = imageMean.texture!
    super.init()
    metalView.delegate = self
    
    
    initForMetalCapture()
    
//    renderables.append(Sphere())
//    renderables.append(Triangle())
    renderables.append(imageMean)
//    renderables.append(PlonkTexture())
    renderables.append(fingerPointsRenderer)
    
    // Create textures
    do {
      try straightener.makeTextureBuffers(texture: originalTexture)
    } catch {}
    
  }

  // Library: set of metal functions
  static func makeLibraryInline(_ code: String) -> MTLLibrary {
    do {
      return try Self.device.makeLibrary(source: code, options: nil)
    } catch let error {
      fatalError(error.localizedDescription)
    }
  }

  static func buildDepthStencilState() -> MTLDepthStencilState? {
    let descriptor = MTLDepthStencilDescriptor()
    descriptor.depthCompareFunction = .less
    descriptor.isDepthWriteEnabled = true
    return Renderer.device.makeDepthStencilState(descriptor: descriptor)
  }
  
  let originalTexture: MTLTexture
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    Self.aspect = Float(view.bounds.width)/Float(view.bounds.height)
  }
  
  func draw(in view: MTKView) {
    imageMean.texture = straightener.straighten(image: originalTexture, angle: -Float.pi * 1.5/180)
    guard
      let descriptor = view.currentRenderPassDescriptor,
      let commandBuffer = Renderer.commandQueue.makeCommandBuffer(),
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
        return
    }
    commandBuffer.label = "Main command bufffer"
    
//    renderEncoder.setDepthStencilState(depthStencilState)
    
    for renderable in renderables {
      if straightenedCameraTexture != nil {
        if let plonkTexture = renderable as? PlonkTexture {
          plonkTexture.texture = straightenedCameraTexture
        }
      }
      renderable.draw(renderEncoder: renderEncoder)
    }

    renderEncoder.endEncoding()
    guard let drawable = view.currentDrawable else {
      return
    }
    commandBuffer.present(drawable)
    
    commandBuffer.commit()
  }
  
  func processFrame(texture: MTLTexture, cmSample: CMSampleBuffer) {
    self.cameraTexture = texture
    self.straightenedCameraTexture = straightener.straighten(image: texture)
    fingerPoints = fingerDetector.detectFingers(sampleBuffer: cmSample)
    
    self.imageMean.texture = straightenedCameraTexture
    self.fingerPointsRenderer.fingerPoints = fingerPoints
  }
  
  func processFrame(texture: MTLTexture, cgImage: CGImage) {
    self.cameraTexture = texture
    self.straightenedCameraTexture = straightener.straighten(image: texture)
    fingerPoints = fingerDetector.detectFingers(image: cgImage)
    
    self.imageMean.texture = straightenedCameraTexture
    self.fingerPointsRenderer.fingerPoints = fingerPoints
  }
}


extension Renderer: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      print("Buffer dropped")
  }
  
  func initForMetalCapture() {
    guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, Self.device, nil, &cameraTextureCache) == kCVReturnSuccess else {
      fatalError("Could not create texture cache")
    }
  }
  
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//    print("Buffer outputted")
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      fatalError("Conversion from CMSampleBuffer to CVImageBuffer failed")
    }
    
    let width = CVPixelBufferGetWidth(imageBuffer)
    let height = CVPixelBufferGetHeight(imageBuffer)
    
    
    var imageTexture: CVMetalTexture?
    let result = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      cameraTextureCache!,
      imageBuffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &imageTexture
    )

    guard
      let unwrappedImageTexture = imageTexture,
      let texture = CVMetalTextureGetTexture(unwrappedImageTexture),
      result == kCVReturnSuccess
    else {
      fatalError("Failed to get camera MTLTexture")
    }
    
    processFrame(texture: texture, cmSample: sampleBuffer)
  }
}


