//
//  GestureRecognizer.swift
//  VirtualBar
//
//  Created by Rio Ogino on 23/04/22.
//

import Vision

public class GestureRecognizer {
  var gestureStartPositition: Float? = nil
  
  // In previous {historySize} frames, gesture must have been detected in previous {isGesturingThreshold} frames
  let historySize: Int = 6
  let isGesturingThreshold: Int = 3
  
  var historyState: Int = 0
  
  var indexMovingAverage: MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.3, invalidUntilNSamples: 0, initialValue: 0)
  var middleMovingAverage: MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.3, invalidUntilNSamples: 0, initialValue: 0)
  
  var minConfidence: Float = 0.6
  
  // Finger tip location not always accurate, so increase active area by this factor
  var activeAreaFudgeScale: Float = 1.8
  
  
  
  public func output() -> Float? {
    if historyState >= isGesturingThreshold && gestureStartPositition != nil {
      let currentPosition = (middleMovingAverage.output() + indexMovingAverage.output()) / 2
      return currentPosition - gestureStartPositition!
    }
    return nil
  }
  
  
  // Bottom of active area, as fraction of search space. Bottom is 0, top is 1
  public func input(_ results: [VNHumanHandPoseObservation], activeAreaBottom: Float) {
    historyState = max(historyState - 1, -1)
    // Subtract 1 since easier to do it here. Add 2 if fingers in correct place detected
    
    if historyState < isGesturingThreshold && gestureStartPositition != nil {
      gestureStartPositition = nil
    }
    
    let minY = 1 - (1 - activeAreaBottom) * activeAreaFudgeScale
    
    for hand in results.count > 0 ? [results.first!]: [] {
      do {
        let tip2 = try hand.recognizedPoint(.indexTip)
        let tip3 = try hand.recognizedPoint(.middleTip)
        
        if tip2.confidence < minConfidence || tip3.confidence < minConfidence {
          continue
        }
        
        if Float(tip2.y) < minY || Float(tip3.y) < minY {
          continue
        }
        
        historyState = min(historyState + 2, historySize)
        
        if historyState < isGesturingThreshold {
          // reset moving average
          indexMovingAverage.set(Float(tip2.x))
          middleMovingAverage.set(Float(tip3.x))
        }
        
        indexMovingAverage.input(Float(tip2.x))
        middleMovingAverage.input(Float(tip3.x))
        
        if historyState >= isGesturingThreshold && gestureStartPositition == nil {
          // begin gesture
          gestureStartPositition = Float(tip3.x + tip2.x) / 2
        }
      } catch {
        print(error.localizedDescription)
      }
    }
  }
  
  func isRightHand(hand: VNHumanHandPoseObservation) -> Bool? {
//    if
    return nil
  }
}
