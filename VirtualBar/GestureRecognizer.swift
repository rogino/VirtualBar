//
//  GestureRecognizer.swift
//  VirtualBar
//
//  Created by Rio Ogino on 23/04/22.
//

import Vision


public class GestureRecognizer {
  struct GestureState {
    var startPosition: Float? = nil
    let historySize: Int = 6
    let threshold: Int = 3
    // In previous {historySize} frames, gesture must have been detected in previous {threshold} frames
    
    var state: Int = 0
    
    // Assume gesture *not found* on each tick; increment by 2 if found
    mutating func tick() {
      state = max(state - 1, -1)
      // min of -1 since -1 + 1 = 1
      
      if state < threshold && startPosition != nil {
        startPosition = nil
      }
    }
    
    var shouldBeGesturing: Bool { state >= threshold }
    var       isGesturing: Bool { state >= threshold && startPosition != nil }
    
    mutating func found(startPosition: Float) {
      state = max(state + 2, historySize)
   
      if shouldBeGesturing && !isGesturing {
//        historyState >= isGesturingThreshold && gestureStartPositition == nil {
          // begin gesture
        self.startPosition = startPosition
      }
    }
  }
  
  var twoFinger: GestureState
  let twoFingerPoints: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip]
  
  var threeFinger: GestureState
  let threeFingerPoints: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip]
  
  let movingAverageAlpha: Float = 0.3
  var indexMovingAverage: MovingAverage
  var middleMovingAverage: MovingAverage
  var ringMovingAverage: MovingAverage
  
  init() {
     indexMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
    middleMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
      ringMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
    
      twoFinger = GestureState()
    threeFinger = GestureState()
  }
  
  var minConfidence: Float = 0.6
  
  // Finger tip location not always accurate, so increase active area by this factor
  var activeAreaFudgeScale: Float = 1.8
  
  
  public func output() -> Float? {
    if threeFinger.isGesturing {
      print("THREE FINGER")
      let currentPosition = (middleMovingAverage.output() + indexMovingAverage.output() + ringMovingAverage.output()) / 3
      return currentPosition - threeFinger.startPosition!
    } else if twoFinger.isGesturing {
      print("TWO FINGER")
      let currentPosition = (middleMovingAverage.output() + indexMovingAverage.output()) / 2
      return currentPosition - twoFinger.startPosition!
    }
    return nil
  }
  
  
  func tryGetFingerTips(
    hand: VNHumanHandPoseObservation,
    minConfidence: VNConfidence = 0,
    minY: Double = 0,
    points: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip]
  ) -> [VNHumanHandPoseObservation.JointName: VNRecognizedPoint] {
    var dict: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint] = [:]
    for pointName in points {
      do {
        let point = try hand.recognizedPoint(pointName)
        if minConfidence <= point.confidence && minY <= point.y {
          dict[pointName] = point
        }
      } catch {}
    }
    
    return dict
  }
  
  // Bottom of active area, as fraction of search space. Bottom is 0, top is 1
  public func input(_ results: [VNHumanHandPoseObservation], activeAreaBottom: Float) {
      twoFinger.tick()
    threeFinger.tick()
    let minY = 1 - (1 - activeAreaBottom) * activeAreaFudgeScale
    
    // TODO multiple hand detection
    for hand in results.count > 0 ? [results.first!]: [] {
      let fingerTips = tryGetFingerTips(
        hand: hand,
        minConfidence: minConfidence,
        minY: Double(minY)
      )
      
      let tipXPositions = fingerTips.mapValues({ Float($0.x) })
      
      func averageX(points: [VNHumanHandPoseObservation.JointName]) -> Float {
        return tipXPositions.reduce(Float(0), {
          $0 + (points.contains($1.key) ? $1.value: 0)
        }) / Float(points.count)
        
      }
      if twoFingerPoints.allSatisfy(fingerTips.keys.contains) {
        if !twoFinger.isGesturing {
          // Fell below threshold at some point in the past
          indexMovingAverage.set(tipXPositions[.indexTip]!)
          middleMovingAverage.set(tipXPositions[.middleTip]!)
        } else {
           indexMovingAverage.input(tipXPositions[.indexTip]!)
          middleMovingAverage.input(tipXPositions[.middleTip]!)
        }
        twoFinger.found(startPosition: averageX(points: threeFingerPoints))
                            
        if fingerTips.keys.contains(.ringTip) {
          if !threeFinger.isGesturing {
            ringMovingAverage.reset()
          } else {
            ringMovingAverage.input(tipXPositions[.ringTip]!)
          }
            
          threeFinger.found(startPosition: averageX(points: threeFingerPoints))
        }
      }
//    }
      
//      do {
//        let tipIndex = try hand.recognizedPoint(.indexTip)
//        let tipMiddle = try hand.recognizedPoint(.middleTip)
//
//        if tipIndex.confidence < minConfidence || tipMiddle.confidence < minConfidence {
//          continue
//        }
//
//        if Float(tipIndex.y) < minY || Float(tipMiddle.y) < minY {
//          continue
//        }
//
//        historyState = min(historyState + 2, historySize)
//
//        if historyState < isGesturingThreshold {
//          // reset moving average
//          indexMovingAverage.set(Float(tipIndex.x))
//          middleMovingAverage.set(Float(tipMiddle.x))
//        }
//
//        indexMovingAverage.input(Float(tipIndex.x))
//        middleMovingAverage.input(Float(tipMiddle.x))
//
//        if historyState >= isGesturingThreshold && gestureStartPositition == nil {
//          // begin gesture
//          gestureStartPositition = Float(tipMiddle.x + tipIndex.x) / 2
//        }
//      } catch {
//        print(error.localizedDescription)
//      }
    }
  }
  
  func isRightHand(hand: VNHumanHandPoseObservation) -> Bool? {
//    if
    return nil
  }
}
