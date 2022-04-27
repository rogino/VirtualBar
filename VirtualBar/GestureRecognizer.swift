//
//  GestureRecognizer.swift
//  VirtualBar
//
//  Created by Rio Ogino on 23/04/22.
//

import Vision


public enum GestureType: CaseIterable {
  // In reverse order of priority
  case none, two, three
}

enum GestureChange {
  case noChange, begin, end
}

struct GestureState {
  let historySize: Int = 6
  let startThreshold: Int = 4
  let stopThreshold: Int = 3
  
  var startPosition: Float? = nil
  var history: [GestureType] = []
  var gestureType: GestureType = .none
  // To start a gesture, at least {startThreshold} out of the previous {historySize} frames must
  // have detected two (or three) fingers. To end, {stopThreshold} frames in the history must be
  // .none
  
  mutating func tick(detected: GestureType, startPosition: Float? = nil) -> GestureChange {
    history.append(detected)
    
    if history.count > historySize {
      history.removeFirst()
    }
    
    let counts: [GestureType: Int] = Dictionary(history.map({ ($0, 1) }), uniquingKeysWith: { $0 + $1 })
    
    var stateChange: GestureChange = .noChange
    
    if gestureType == .none {
      // May need to start the gesture now
      for gesture in GestureType.allCases.reversed().filter({ $0 != .none }) {
        if (counts[gesture] ?? 0) >= startThreshold {
          gestureType = gesture
          stateChange = .begin
          self.startPosition = startPosition
          break
        }
      }
    } else {
      // Too many non-gesture frames detected
      if (counts[.none] ?? 0) >= stopThreshold {
        gestureType = .none
        stateChange = .end
        self.startPosition = nil
      }
    }
    
    return stateChange
  }
}

/**
 In first m frames, if n of them have three fingers then three finger gesture. Else if n of them have two fingers, then two finger gesture. Initialize start position then
 
 If fewer than n out of m ticks contain two fingers (even if three finger gesture), then end the gesture and reset state
 */

public class GestureRecognizer {
  
  var gestureState: GestureState
  
  let movingAverageAlpha: Float = 0.3
  var  indexMovingAverage: MovingAverage
  var middleMovingAverage: MovingAverage
  var   ringMovingAverage: MovingAverage
  
  init() {
    indexMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
    middleMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
    ringMovingAverage = ExponentialWeightedMovingAverage(alpha: movingAverageAlpha)
    
    gestureState = GestureState()
  }
  
  // Minimum finger point confidence
  var minConfidence: Float = 0.6
  
  // Finger tip location not always accurate, so increase active area by this factor
  var activeAreaFudgeScale: Float = 1.2
  
  // for gesture to be detected as three finger, difference between (index and middle
  // fingers average) and ring finger's y values can be a maximum of this.
  // Negative means ring finger // must be *above* index and middle average
  let maxRingDeltaY: Float = 0.03
  
  
  public var currentPosition: Float? {
    switch gestureState.gestureType {
    case .two:
      return (middleMovingAverage.output() + indexMovingAverage.output()) / 2
    case .three:
      return (middleMovingAverage.output() + indexMovingAverage.output() + ringMovingAverage.output()) / 3
    default:
      return nil
    }
  }
  
  public func output() -> (type: GestureType, delta: Float?) {
    var delta: Float? = nil
    if let currentPosition = currentPosition,
       let startPosition = gestureState.startPosition {
      delta = currentPosition - startPosition
    }
    
    return (type: gestureState.gestureType, delta: delta)
  }
  
  
  // Returns dict where keys are a subset of `points`, containing only those present in
  // the hand and where the point is in the required position and meets the confidence requirements
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
    // Need to increase size of active area due to inaccuracies in detector
    let minY = 1 - (1 - activeAreaBottom) * activeAreaFudgeScale
    
    // TODO multiple hand detection
    for hand in results.count > 0 ? [results.first!]: [] {
      let fingerTips = tryGetFingerTips(
        hand: hand,
        minConfidence: minConfidence,
        minY: Double(minY)
      )
      
      let tipXPositions = fingerTips.mapValues({ Float($0.x) })
      
      func averageX(_ points: [VNHumanHandPoseObservation.JointName]) -> Float {
        return tipXPositions.reduce(Float(0), {
          $0 + (points.contains($1.key) ? $1.value: 0)
        }) / Float(points.count)
      }
      
      var detectedGesture: GestureType = .none
      var position: Float? = nil
      
      if fingerTips.keys.contains(.indexTip) && fingerTips.keys.contains(.middleTip) {
        detectedGesture = .two
        position = averageX([.indexTip, .middleTip])
        if fingerTips.keys.contains(.ringTip) {
          let indexMiddleAvgY = (fingerTips[.indexTip]!.y + fingerTips[.middleTip]!.y) / 2
          let ringY = fingerTips[.ringTip]!.y
          // Tip detection can be quite inaccurate but is consistent within a frame, so
          // ring finger often detected as being inside active area. Bending the ring finger
          // more leads to hand not being detected, so this needed to avoid detecting a two
          // finger gesture as a three finger one
          if Float(indexMiddleAvgY - ringY) <= maxRingDeltaY {
            detectedGesture = .three
            position = averageX([.indexTip, .middleTip, .ringTip])
          }
//          print(Float(indexMiddleAvgY - ringY), detectedGesture)
        }
      }
      
      switch gestureState.tick(detected: detectedGesture, startPosition: position) {
      case .begin:
        if [.two, .three].contains(gestureState.gestureType) {
          indexMovingAverage.set(tipXPositions[.indexTip]!)
          middleMovingAverage.set(tipXPositions[.middleTip]!)
          if gestureState.gestureType == .three {
            ringMovingAverage.set(tipXPositions[.ringTip]!)
          }
        }
        break
      case .noChange:
        if gestureState.gestureType == .none {
          break
        }
        if let x = tipXPositions[.indexTip] {
          indexMovingAverage.input(x)
        }
        if let x = tipXPositions[.middleTip] {
          middleMovingAverage.input(x)
        }
        if let x = tipXPositions[.ringTip] {
          ringMovingAverage.input(x)
        }
        break
      case .end:
        break
      }
    }
  }
  
  func isRightHand(hand: VNHumanHandPoseObservation) -> Bool? {
    //    if
    return nil
  }
}
