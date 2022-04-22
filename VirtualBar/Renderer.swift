import MetalKit
import AVFoundation
import Vision

class Renderer: NSObject {
  static var device: MTLDevice!
  static var commandQueue: MTLCommandQueue!
  static var library: MTLLibrary!

  var pipelineState: MTLRenderPipelineState!
  
  var straightener: Straighten
  
  var renderables: [Renderable] = []
  
  let fingerDetector = FingerDetector()
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
    
    super.init()
    metalView.delegate = self
    
    
    initForMetalCapture()
    
//    renderables.append(Sphere())
//    renderables.append(Triangle())
    renderables.append(imageMean)
//    renderables.append(PlonkTexture())
    renderables.append(fingerPointsRenderer)
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
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    Self.aspect = Float(view.bounds.width)/Float(view.bounds.height)
  }
  
  func draw(in view: MTKView) {
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


class FingerDetector {
  var handPoseRequest = VNDetectHumanHandPoseRequest()
  init() {
    handPoseRequest.maximumHandCount = 2
  }
  
  // Convert VN point point to float3, with z being confidence
  func transform(_ point: VNRecognizedPoint, yScale: Float = 1.0) -> simd_float3 {
    // Convert from [0, 1] to [-1, 1]
    let x: Float = Float(point.location.x) * 2 - 1
    // For y, 0 and 1 refer to the point within the areaOfInterest, which may be smaller than the image
    // Hence, must scale to get it back into image coordinates
    let y: Float = Float(point.location.y) * yScale * 2 - 1
    
    return simd_float3(x, y, point.confidence)
  }
  
  
  func detectFingers(image: CGImage) -> [simd_float3] {
    let handler = VNImageRequestHandler(
      cgImage: image,
      orientation: .upMirrored,
      options: [:]
    )
    return detectFingers(handler: handler)
  }
  
  func detectFingers(sampleBuffer: CMSampleBuffer) -> [simd_float3] {
    let handler = VNImageRequestHandler(
      cmSampleBuffer: sampleBuffer,
      orientation: .upMirrored,
      options: [:]
    )
    
    return detectFingers(handler: handler)
  }
  
  private func detectFingers(handler: VNImageRequestHandler) -> [simd_float3] {
    // https://developer.apple.com/videos/play/wwdc2020/10653/
    
    // Ignore area above active area - get rid of reflections being detected as hands
    let first = ImageMean.activeArea.first ?? [-1, -1]
    let yTex = first.x >= 0 ? max(0.0, first.x - 0.05) : 0.0 // Allow fingers to extend slightly above the active area
    let yScale = 1.0 - yTex
    handPoseRequest.regionOfInterest = CGRect(
      x: 0.0,
      y: 0, // y = 0 is the bottom
      width: 1.0,
      height: 1.0 - Double(yTex)
    )
    
    var points: [simd_float3] = []
    
    do {
      try handler.perform([handPoseRequest])
      guard let results = handPoseRequest.results, results.count > 0 else {
        return []
      }
      
      for hand in results {
        let observation = hand
        
//        for finger in observation.availableJointsGroupNames {
//          let finger = try observation.recognizedPoints(finger)
//          for joint in observation.availableJointNames {
//            if let point = finger[joint] {
//              points.append(transform(point, yScale: yScale))
//            }
//          }
//        }
//        
        let  indexFingerPoints = try observation.recognizedPoints(.indexFinger)
        let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
        guard let  indexTipPoint =  indexFingerPoints[.indexTip],
              let middleTipPoint = middleFingerPoints[.middleTip] else {
          continue
        }

        points.append(transform(indexTipPoint, yScale: yScale))
        points.append(transform(middleTipPoint, yScale: yScale))
      }
      
      return points
      
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
