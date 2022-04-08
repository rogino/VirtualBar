import MetalKit
import AVFoundation
import Vision

class Renderer: NSObject {
  static var device: MTLDevice!
  static var commandQueue: MTLCommandQueue!
  static var library: MTLLibrary!

//  let depthStencilState: MTLDepthStencilState
  var pipelineState: MTLRenderPipelineState!
  var renderables: [Renderable] = []
  
  let fingerDetector = FingerDetector()
  var fingerPoints: [simd_float3] = []
  
  static var aspect: Float = 1.0
  
  
  var cameraTexture: MTLTexture? = nil
  
  var cameraTextureCache: CVMetalTextureCache?

  public convenience init(metalView: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("No metal-capable device found")
    }
    self.init(metalView: metalView, device: device)
  }
  
  public init(metalView: MTKView, device: MTLDevice) {
    metalView.device = device
    metalView.clearColor = MTLClearColor(red: 0.5, green: 0, blue: 0, alpha: 1)
//    metalView.depthStencilPixelFormat = .depth32Float
    
    Self.aspect = Float(metalView.bounds.width)/Float(metalView.bounds.height)
    Self.device = device
    Self.commandQueue = device.makeCommandQueue()!
    Self.library = device.makeDefaultLibrary()
    
//    self.depthStencilState = Self.buildDepthStencilState()!
    
    super.init()
    metalView.delegate = self
    
    
    initForMetalCapture()
    
//    renderables.append(Sphere())
//    renderables.append(Triangle())
    renderables.append(ImageMean())
    renderables.append(FingerPointsRenderer())
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
    
//    renderEncoder.setDepthStencilState(depthStencilState)
    
    for renderable in renderables {
      if cameraTexture != nil,
         let imageMean = renderable as? ImageMean {
        imageMean.texture = cameraTexture
      }
      
      if let fingerPointsRenderer = renderable as? FingerPointsRenderer {
        fingerPointsRenderer.fingerPoints = fingerPoints
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
    
    fingerPoints = fingerDetector.detectFingers(sampleBuffer: sampleBuffer)
    
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
    
    self.cameraTexture = texture
  }
}


class FingerDetector {
  var handPoseRequest = VNDetectHumanHandPoseRequest()
  init() {
    handPoseRequest.maximumHandCount = 2
  }
  
  // Convert VN point point to float3, with z being confidence
  func transform(_ point: VNRecognizedPoint) -> simd_float3 {
    // Convert from [0, 1] to [-1, 1]
    let x: Float = Float(point.location.x) * 2 - 1
    let y: Float = Float(point.location.y) * 2 - 1
    
    return simd_float3(x, y, point.confidence)
  }
  
  
  func detectFingers(sampleBuffer: CMSampleBuffer) -> [simd_float3] {
    // https://developer.apple.com/videos/play/wwdc2020/10653/
    let handler = VNImageRequestHandler(
      cmSampleBuffer: sampleBuffer,
      orientation: .upMirrored,
      options: [:]
    )
    
    var points: [simd_float3] = []
    
    do {
      try handler.perform([handPoseRequest])
      guard let results = handPoseRequest.results, results.count > 0 else {
        return []
      }
      
      for hand in results {
        let observation = hand
        
        for finger in observation.availableJointsGroupNames {
          let finger = try observation.recognizedPoints(finger)
          for joint in observation.availableJointNames {
            if let point = finger[joint] {
              points.append(transform(point))
            }
          }
        }
        
        let  indexFingerPoints = try observation.recognizedPoints(.indexFinger)
        let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
        guard let  indexTipPoint =  indexFingerPoints[.indexTip],
              let middleTipPoint = middleFingerPoints[.middleTip] else {
          continue
        }

        points.append(transform(indexTipPoint))
        points.append(transform(middleTipPoint))
      }
      
      return points
      
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
