/// Copyright (c) 2022 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import SwiftUI
import MetalKit
import AVFoundation

struct MetalView: View {
  @State private var metalView = MTKView()
  @State private var renderer: Renderer?
 
  let useLiveCamera = true
  @State private var captureSession = AVCaptureSession()
  @State private var videoFeed: VideoFeed?

  var body: some View {
    MetalViewRepresentable(metalView: $metalView)
      .onAppear {
        renderer = Renderer(metalView: metalView)
        
        var displayId: CGDirectDisplayID = 0;
        var displayService: io_service_t = 0;
        let err = getInternalDisplayIdAndService(&displayId, &displayService);
        if err != 0 {
          print(err);
        } 
        var brightness: Float = -1;
        print(getBrightness(displayId, displayService, &brightness))
        print(brightness)
        brightness = max(0, brightness - 0.1)
        print(setBrightness(displayId, displayService, brightness))
        if useLiveCamera {
          checkCameraPermission()
        } else {
          videoFeed = VideoFeed(
            renderer: renderer!,
            videoPath: "/Users/rioog/Documents/MetalTutorial/virtualbar/hand_gesture_data/Movie on 26-04-22 at 13.46.mov"
          )
        }
      }.onDisappear {
        if useLiveCamera {
          captureSession.stopRunning()
          videoFeed?.stop()
        }
      }
  }
  
  
}

extension MetalView {
  func setupCaptureSession() {
    captureSession.sessionPreset = .qHD960x540
//    captureSession.sessionPreset = .vga640x480
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



#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#elseif os(iOS)
typealias ViewRepresentable = UIViewRepresentable
#endif

struct MetalViewRepresentable: ViewRepresentable {
  @Binding var metalView: MTKView

  #if os(macOS)
  func makeNSView(context: Context) -> some NSView {
    metalView
  }
  func updateNSView(_ uiView: NSViewType, context: Context) {
    updateMetalView()
  }
  #elseif os(iOS)
  func makeUIView(context: Context) -> MTKView {
    metalView
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    updateMetalView()
  }
  #endif

  func updateMetalView() {
  }
}

struct MetalView_Previews: PreviewProvider {
  static var previews: some View {
    VStack {
      MetalView()
      Text("Metal View")
    }
  }
}
