//
//  ActiveAreaSelector.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

import Foundation

  
public struct CandidateArea: CustomStringConvertible {
  let x1: Int
  let size: Int
  var x2: Int { x1 + size }
  var center: Float { Float(x1) + Float(size) / 2.0 }
  
  let centerBrightness: Float
  let weightedAveragedDerivative: Float
  var ranking: Int
  
  public var description: String {
    return String(format: "[%d to %d], brightness %.1f, weight %.7f", x1, x2, centerBrightness, weightedAveragedDerivative)
  }
}


private class CandidateAreaHistory: CustomStringConvertible {
  let x1MovingAverage: MovingAverage
  let x2MovingAverage: MovingAverage
  let centerBrightnessAverage: MovingAverage
  let weightedAveragedDerivativeAverage: MovingAverage
  
  var x1: Float { x1MovingAverage.output() }
  var x2: Float { x2MovingAverage.output() }
  var centerBrightness: Float { centerBrightnessAverage.output() }
  var weightedAveragedDerivative: Float { weightedAveragedDerivativeAverage.output() }
  
  var size: Float { x2 - x1 }
  var center: Float { (x1 + x2) / 2 }
  
  
  // Rank multiplier: when area shows up, don't want it to just immediately go to top
  init(initial: CandidateArea, rankMultiplier: Float = 1.0) {
    x1MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x1))
    x2MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x2))
    centerBrightnessAverage           = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.centerBrightness))
    weightedAveragedDerivativeAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.weightedAveragedDerivative))
  }
  
  func update(update: CandidateArea) {
    x1MovingAverage.input(Float(update.x1))
    x2MovingAverage.input(Float(update.x2))
    centerBrightnessAverage.input(update.centerBrightness)
    weightedAveragedDerivativeAverage.input(update.weightedAveragedDerivative)
  }
  
  func notFound(brightnessTendsTo: Float, weightedAverageTendsTo: Float) {
    centerBrightnessAverage.input(brightnessTendsTo)
    weightedAveragedDerivativeAverage.input(weightedAverageTendsTo)
  }
  
  
  var description: String {
    return String(format: "[%.2f to %.2f], brightness %.1f, weight %.7f", x1, x2, centerBrightness, weightedAveragedDerivative)
  }
  
}

public class ActiveAreaSelector {
  let LOG = true
  
  fileprivate var candidates: [CandidateAreaHistory] = []
  

  // For each sample in which the area is not found, the color tends to this value
  let brightnessTendsTo: Float = 0
  let weightedAverageTendsTo: Float = 0.001
  
  let initialRankMultiplier: Float = 5.0
  
  // Remove candidate areas after this point
  let maxRank: Float = 50
 
  // Areas can be += existing areas
  let maxDeviation: Float = 5
  
  let maxNumCandidates: Int = 4
  
  let maxWeightedAveragedDerivative: Float = 1e-4
  let minBrightness: Float = 0.3
  
  
  fileprivate static func sort(_ candidates: [CandidateAreaHistory]) -> [CandidateAreaHistory] {
    // Brighter color -> larger is good
    let colorSort  = candidates.sorted(by: { $0.centerBrightness > $1.centerBrightness })
    
    // Lower averaged weighted derivative -> smaller is good
    let weightSort = candidates.sorted(by: { $0.weightedAveragedDerivative < $1.weightedAveragedDerivative })
    
    // Sum the color and weight indexes, find the lowest
    let indexSumSort: [(weightIndex: Int, colorIndex: Int, sum: Int)] = colorSort.enumerated().map { (i, val) in
      let weightIndex = weightSort.firstIndex(where: { $0.x1 == val.x1 })!
      return (weightIndex: weightIndex, colorIndex: i, sum: weightIndex + i)
    }.sorted(by: { $0.sum == $1.sum ? $0.colorIndex < $1.colorIndex : $0.sum < $1.sum })
    // If sum of indices are the same, prefer color over weight
    
    let sortedMatches: [CandidateAreaHistory] = indexSumSort.enumerated().map { colorSort[$1.colorIndex] }
    
    return sortedMatches
  }
  
  func update(candidates newCandidates: [CandidateArea], sizeRange: ClosedRange<Int>?) {
    var sortedCandidates = newCandidates.sorted(by: { $0.center < $1.center })
    
    if LOG {
      print("\n")
      print(newCandidates.count, "candidates received")
      sortedCandidates.forEach { print($0) }
      print()
    }
    
    for current in candidates {
      let index = sortedCandidates.firstIndex(where: { current.center - maxDeviation < $0.center && $0.center < current.center + maxDeviation })
      if (index == nil) {
        current.notFound(brightnessTendsTo: brightnessTendsTo, weightedAverageTendsTo: weightedAverageTendsTo)
        continue
      }
      // Remove from array so that we can determine which ones are new and which ones can be merged
      let match = sortedCandidates.remove(at: index!)
      if LOG {
        print("New candidate merged with", current)
      }
      current.update(update: match)
    }
    
    if LOG {
      print(sortedCandidates.count, "new candidates")
    }
    
    for newCandidate in sortedCandidates {
      candidates.append(CandidateAreaHistory(initial: newCandidate, rankMultiplier: initialRankMultiplier))
    }
   
    // Sorted by rank, best first
    candidates = Self.sort(candidates)
    
    // Cut down number of candidates
    if candidates.count > maxNumCandidates {
      if LOG {
        print("Removed \(candidates.count - maxNumCandidates) worst candidates")
      }
      candidates = Array(candidates[0..<maxNumCandidates])
    }
    
    removeBadCandidates(sizeRange: sizeRange == nil ? nil: Float(sizeRange!.lowerBound)...Float(sizeRange!.upperBound))
    removeOverlappingCandidates()
    
    if LOG {
      print("Current state")
      candidates.enumerated().forEach { print($0, $1) }
    }
  }
  
  private func removeBadCandidates(sizeRange: ClosedRange<Float>?) {
    // Remove candidates where the size is not within the range,
    // or where the brightness too low or weighted averaged derivative too high
    // Must be sorted by rank, highest-ranked first
    var i = 0
    
    while true {
      if candidates.isEmpty || i >= candidates.count {
        break
      }
      let current = candidates[i]
      if current.centerBrightness < minBrightness {
        if LOG {
          print("Removal, color:", candidates[i])
        }
        candidates.remove(at: i)
      } else if current.weightedAveragedDerivative > maxWeightedAveragedDerivative {
        if LOG {
          print("Removal, weighted averaged derivative:", candidates[i])
        }
        candidates.remove(at: i)
      } else if sizeRange != nil && (
        current.size < sizeRange!.lowerBound ||
        current.size > sizeRange!.upperBound
      ) {
        if LOG {
          print("Removal, size:", candidates[i].size, candidates[i])
        }
        candidates.remove(at: i)
      } else {
        i += 1
      }
    }
  }

  private func removeOverlappingCandidates() {
    // Removing overlapping sections
    // Must be sorted by rank, highest-first
    // These overlaps do not update the kept-candidate's values
    var i = 0
    while true {
      if candidates.isEmpty || i >= candidates.count - 1 {
        break
      }
      let candidate = candidates[i]
      
      var j = i + 1
      while j < candidates.count {
        let dup = candidates[j]
        if dup.x2 < candidate.x1 || candidate.x2 < dup.x1 {
          // Not overlapping
          j += 1
          continue
        }
        if LOG {
          print(String(format: "Removal, overlap [%.1f, %.1f] with [%.1f, %.1f]:", dup.x1, dup.x2, candidate.x1, candidate.x2), dup.description)
        }
        candidates.remove(at: j)
      }
      i += 1
    }
  }

  
  func getActiveArea() -> (x1: Float, x2: Float)? {
    if candidates.isEmpty {
      return nil
    }
    
    let bestCandidate = candidates.first!
    return (x1: bestCandidate.x1, x2: bestCandidate.x2)
  }
  
  func getAllAreasSorted() -> [SIMD2<Float>] {
    return candidates.map { SIMD2<Float>( $0.x1, $0.x2 )}
  }
}
