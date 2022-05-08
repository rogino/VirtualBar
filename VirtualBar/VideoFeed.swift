//
//  Video.swift
//  VirtualBar
//
//  Created by Rio Ogino on 22/04/22.
//

import AVFoundation
import MetalKit

class VideoFeed {
//  let videoPath: URL = URL.init(fileURLWithPath: "/Users/rioog/Documents/MetalTutorial/virtualbar/hand_gesture_data/Movie on 21-04-22 at 18.32.mov")
  var videoPath: URL = URL.init(fileURLWithPath: "/Users/rioog/Documents/MetalTutorial/virtualbar/hand_gesture_data/Movie on 22-04-22 at 12.01.mov")
  let slowDown: Double
  
  let frameRate: Int32 = 30
  var currentTime: Float64 = 0
  let duration: Float64
  let asset: AVAsset
  let generator: AVAssetImageGenerator
  let textureLoader: MTKTextureLoader
  
  var frameRange: ClosedRange<Double>? = (8.0)...(20.0)
  
  var timer: Timer? = nil
  let renderer: Renderer
  
  init(renderer: Renderer, videoPath: String? = nil, frameRange: ClosedRange<Double>? = nil, slowDown: Double = 1.0) {
    // https://stackoverflow.com/questions/42665271/swift-get-all-frames-from-video
    if videoPath != nil {
      self.videoPath = URL.init(fileURLWithPath: videoPath!)
      self.frameRange = nil
    }
    if frameRange != nil {
      self.frameRange = frameRange!
    }
    self.slowDown = slowDown
    asset = AVAsset(url: self.videoPath)
    duration = CMTimeGetSeconds(asset.duration)
    generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceAfter = .zero
    generator.requestedTimeToleranceBefore = .zero
    
    self.renderer = renderer
    textureLoader = MTKTextureLoader(device: Renderer.device)
    
    self.timer = Timer.scheduledTimer(
      timeInterval: slowDown / Double(frameRate),
      target: self,
      selector: #selector(timerCallback),
      userInfo: nil,
      repeats: true
    )
    
    currentTime = self.frameRange?.lowerBound ?? 0
  }
  
  @objc func timerCallback() {
    let out = generateFrame()
    renderer.processFrame(texture: out.0, cgImage: out.1)
  }
  
  func stop() {
    timer?.invalidate()
    currentTime = frameRange?.lowerBound ?? 0
  }
  
  func generateFrame() -> (MTLTexture, CGImage) {
    print("FRAME", currentTime)
    let time: CMTime = CMTimeMakeWithSeconds(currentTime, preferredTimescale: frameRate)
    currentTime += 1 / Double(frameRate)
    if currentTime > duration || (frameRange != nil && currentTime > frameRange!.upperBound) {
      currentTime = frameRange?.lowerBound ?? 0
    }
    
    do {
      let image = try generator.copyCGImage(at: time, actualTime: nil)
      let mtlImage = try textureLoader.newTexture(cgImage: image)
      return (mtlImage, image)
    } catch {
      print("FAILED")
      print(error.localizedDescription)
      currentTime = frameRange?.lowerBound ?? 0
      return generateFrame()
    }
  }
}
