//
//  FingerDetector.swift
//  VirtualBar
//
//  Created by Rio Ogino on 27/04/22.
//

import Foundation
import Vision


class FingerDetector {
  var handPoseRequest = VNDetectHumanHandPoseRequest()
  
  var gestureRecognizer = GestureRecognizer()
  
  var volume: Float? = nil
  var volumeControl: VolumeControl?
  var volumeScale: Float = 3.0
  
  var brightness: Float? = nil
  var brightnessControl: BrightnessControl?
  var brightnessScale: Float = 3.0
  
  var activeAreaSelector: ActiveAreaSelector
  
  init(activeAreaSelector: ActiveAreaSelector) {
    self.activeAreaSelector = activeAreaSelector
    handPoseRequest.maximumHandCount = 2
    do {
      volumeControl = try VolumeControl()
      brightnessControl = try BrightnessControl()
    } catch {
      print(error.localizedDescription)
    }
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
    
    let activeAreaTopOffset: Float = 0.05 // Look 5% above where the active area starts
    
    // Ignore area above active area - get rid of reflections being detected as hands
    let activeArea = ImageMean.activeArea.first ?? [-1, -1]
    let activeAreaTop = activeArea.x >= 0 ? max(0.0, activeArea.x - activeAreaTopOffset) : 0.0 // Allow fingers to extend slightly above the active area
    let yScale = 1.0 - activeAreaTop
    handPoseRequest.regionOfInterest = CGRect(
      x: 0.0,
      y: 0, // y = 0 is the bottom
      width: 1.0,
      height: 1.0 - Double(activeAreaTop)
    )
    
    var points: [simd_float3] = []
    
    do {
      try handler.perform([handPoseRequest])
      guard let results = handPoseRequest.results, results.count > 0 else {
        return []
      }

      
      let prev = gestureRecognizer.output()
      gestureRecognizer.input(results, activeAreaBottom: 1 - (activeArea.y - activeAreaTop) / (1 - activeAreaTop))
      let (gesture, delta) = gestureRecognizer.output()
      
      if gesture == .none {
        activeAreaSelector.unlockCurrentTopCandidate()
      }
      
      if let delta = delta {
        if prev.type == .none {
          // gesture began: get current state
          volume = volumeControl?.getVolume()
          brightness = try? brightnessControl?.get()
          activeAreaSelector.lockCurrentTopCandidate()
        } else {
          if gesture == .two {
            volumeControl?.setVolume(volume: volume! + delta * volumeScale)
          } else if gesture == .three && brightness != nil {
            try? brightnessControl?.set(brightness: brightness! + delta * brightnessScale)
          }
        }
        
        points.append(SIMD3<Float>(
          Float(gestureRecognizer.indexMovingAverage.output()) * 2 - 1,
          1 - (activeArea.x + activeArea.y),
          1
        ))

        points.append(SIMD3<Float>(
          Float(gestureRecognizer.middleMovingAverage.output()) * 2 - 1,
          1 - (activeArea.x + activeArea.y),
          1
        ))
        
        points.append(SIMD3<Float>(
          Float(gestureRecognizer.ringMovingAverage.output()) * 2 - 1,
          1 - (activeArea.x + activeArea.y),
          1
        ))
       
        if let start = gestureRecognizer.gestureState.startPosition {
          points.append(SIMD3<Float>(
            Float(start) * 2 - 1,
            1 - (activeArea.x + activeArea.y),
            0.5
          ))
        }
        
        if let avg = gestureRecognizer.currentPosition {
          points.append(SIMD3<Float>(
            Float(avg) * 2 - 1,
            1 - (activeArea.x + activeArea.y),
            0.3
          ))
        }
      }
      return points
      
      for hand in results {
        let observation = hand
        
        for finger in observation.availableJointsGroupNames {
          let finger = try observation.recognizedPoints(finger)
          for joint in observation.availableJointNames {
            if let point = finger[joint] {
              points.append(transform(point, yScale: yScale))
            }
          }
        }
//
//        let  indexFingerPoints = try observation.recognizedPoints(.indexFinger)
//        let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
//        guard let  indexTipPoint =  indexFingerPoints[.indexTip],
//              let middleTipPoint = middleFingerPoints[.middleTip] else {
//          continue
//        }
//
//        points.append(transform(indexTipPoint, yScale: yScale))
//        points.append(transform(middleTipPoint, yScale: yScale))
      }
      
      return points
      
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}

