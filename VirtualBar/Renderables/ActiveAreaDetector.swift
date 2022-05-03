//
//  ActiveAreaDetector.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

public class ActiveAreaDetector {
//  enum WeightedAverageType {
//    case triangle, rect
//  }
  private static func weightedAverage(
    arr: [Float],
    min: Int, size: Int, // start at index for n elements
//    type: WeightedAverageType,
    minWeight: Float = 0,
    cutOffProportion: Float = 0.2 // Ignore first and last x/2 % of the area
  ) -> Float {
    let radius = Float(size - 1) / 2
    let center: Float = Float(min) + radius
    
//    func halfDistributionTriangle(t: Float) -> Float {
//      // t in [0, 1], where 1 is the center of the distribution
//      return t * (1 - minWeight) + minWeight
//    }
//
//    func halfDistributionCutoffTriangle(t: Float) -> Float {
//      return halfDistributionTriangle(t: max(Float(0), t - cutOffProportion))
//    }
//
    func halfDistributionCutoffRect(t: Float) -> Float {
      return t < cutOffProportion ? 0: 1
    }
    
    let denominator = size - 2 * Int(ceil(Float(size) * Float(cutOffProportion) / 2))
                                     
     return (min..<min + size).makeIterator().reduce(0) { current, i in
      let distanceFromCenter = abs(Float(i) - center) / radius
      let t = 1 - distanceFromCenter
//      let weight = type == .triangle ?
//        halfDistributionCutoffTriangle(t: t):
//        halfDistributionCutoffRect(t: t)
      let weight = halfDistributionCutoffRect(t: t)
      
      return current + arr[i] * arr[i] * weight
    } / Float(denominator)
  }


  public static func detectCandidateAreas(
    sobelOutput: [Float],
    squashOutput: [Float],
    threshold: Float,
    sizeRange: ClosedRange<Int>
  ) -> [CandidateArea] {
    var current: (x: Int, size: Int) = (x: 0, size: 0)
    var candidateMatches: [CandidateArea] = []
    
    // Idea: touch bar area is very smooth. Hence, find areas with a low derivative that are the correct height
    for (i, val) in sobelOutput.enumerated() {
      if val < threshold {
        current.size += 1
      } else {
        if sizeRange.contains(current.size) {
          candidateMatches.append(CandidateArea(
            x1: current.x,
            size: current.size,
            // Idea: key rows can get detected, so use the squash map to get the color of the area
            // The active area will be the lightest area - keys are black while the body is grey,
            // so this should prevent a key row from being detected as a false positive
            centerBrightness: squashOutput[current.x + current.size / 2],
            // Idea: use weighted derivative quantify amount of variance
            weightedAveragedDerivative: Self.weightedAverage(
              arr: sobelOutput,
              min: current.x,
              size: current.size
//              type: .rect
            ),
            ranking: -1
          ))
        }
        current = (x: i, size: 0)
      }
    }
    
    
    return candidateMatches
  }
}
