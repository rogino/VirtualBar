//
//  Video.swift
//  VirtualBar
//
//  Created by Rio Ogino on 22/04/22.
//

import AVFoundation
import MetalKit

class VideoFeed {
//  static let videoPath: URL = URL.init(fileURLWithPath: "/Users/rioog/Documents/MetalTutorial/virtualbar/hand_gesture_data/Movie on 21-04-22 at 18.32.mov")
  static let videoPath: URL = URL.init(fileURLWithPath: "/Users/rioog/Documents/MetalTutorial/virtualbar/hand_gesture_data/Movie on 22-04-22 at 12.01.mov")
  static let slowDown: Double = 100.0
  
  let frameRate: Int32 = 30
  var currentTime: Float64 = 0
  let duration: Float64
  let asset: AVAsset
  let generator: AVAssetImageGenerator
  let textureLoader: MTKTextureLoader
  
  let frameRange: ClosedRange<Double> = (8.0)...(20.0)
  
  var timer: Timer? = nil
  let renderer: Renderer
  
  init(renderer: Renderer) {
    // https://stackoverflow.com/questions/42665271/swift-get-all-frames-from-video
    asset = AVAsset(url: Self.videoPath)
    duration = CMTimeGetSeconds(asset.duration)
    generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceAfter = .zero
    generator.requestedTimeToleranceBefore = .zero
    
    self.renderer = renderer
    textureLoader = MTKTextureLoader(device: Renderer.device)
    
    self.timer = Timer.scheduledTimer(
      timeInterval: Self.slowDown / Double(frameRate),
      target: self,
      selector: #selector(timerCallback),
      userInfo: nil,
      repeats: true
    )
    
    currentTime = frameRange.lowerBound

  }
  
  @objc func timerCallback() {
    let out = generateFrame()
    renderer.processFrame(texture: out.0, cgImage: out.1)
  }
  
  func stop() {
    timer?.invalidate()
    currentTime = frameRange.lowerBound
  }
  
  func generateFrame() -> (MTLTexture, CGImage) {
    print("FRAME", currentTime)
    let time: CMTime = CMTimeMakeWithSeconds(currentTime, preferredTimescale: frameRate)
    currentTime += 1 / Double(frameRate)
    if currentTime > duration || currentTime > frameRange.upperBound {
      currentTime = frameRange.lowerBound
    }
    
    do {
      let image = try generator.copyCGImage(at: time, actualTime: nil)
      let mtlImage = try textureLoader.newTexture(cgImage: image)
      return (mtlImage, image)
    } catch {
      print("FAILED")
      print(error.localizedDescription)
      currentTime = frameRange.lowerBound
      return generateFrame()
    }
  }
}
