import MetalKit
import AVFoundation

class ViewController: LocalViewController {
  var renderer: Renderer?
  var captureSession = AVCaptureSession()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    guard let metalView = view as? MTKView else {
      fatalError("metal view not set up in storyboard")
    }
    renderer = Renderer(metalView: metalView)
    checkCameraPermission()
  }
}

extension ViewController {
  func setupCaptureSession() {
    captureSession.sessionPreset = .qHD960x540
    guard let device = AVCaptureDevice.default(for: .video) else {
      fatalError("AVCaptureDevice not found")
    }
    
    // https://navoshta.com/metal-camera-part-1-camera-session/
    captureSession.beginConfiguration()
    guard let captureInput = try? AVCaptureDeviceInput(device: device) else {
      fatalError("Could not get device input")
    }
    
    captureSession.addInput(captureInput)
    let outputData = AVCaptureVideoDataOutput()
    outputData.videoSettings = [
//      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    
    let captureSessionQueue = DispatchQueue(label: "CameraSessionQueue", attributes: [])
    outputData.setSampleBufferDelegate(renderer, queue: captureSessionQueue)
    
    if !captureSession.canAddOutput(outputData) {
      fatalError("Could not add output")
    }
    captureSession.addOutput(outputData)
    captureSession.commitConfiguration()
    
    captureSession.startRunning()
  }
  
  override func viewWillDisappear() {
    captureSession.stopRunning()
  }
  
  
  func checkCameraPermission() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: // The user has previously granted access to the camera.
        self.setupCaptureSession()
      
      case .notDetermined: // The user has not yet been asked for camera access.
        AVCaptureDevice.requestAccess(for: .video) { granted in
          if granted {
            self.setupCaptureSession()
          }
        }
      
      case .denied: // The user has previously denied access.
        fatalError("Camera access denied")

      case .restricted: // The user can't grant access due to restrictions.
        fatalError("Camera access restricted")
      @unknown default:
        fatalError("Camera access: unknown error")
    }
  }
}
