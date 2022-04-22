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
  
  let centerColor: Float
  let weightedAveragedDerivative: Float
  var ranking: Int
  
  public var description: String {
    return String(format: "[%d to %d], color %.1f, weight %.7f", x1, x2, centerColor, weightedAveragedDerivative)
  }
}


private class CandidateAreaHistory: CustomStringConvertible {
  let x1MovingAverage: MovingAverage
  let x2MovingAverage: MovingAverage
  let centerColorAverage: MovingAverage
  let weightedAveragedDerivativeAverage: MovingAverage
  
  var x1: Float { x1MovingAverage.output() }
  var x2: Float { x2MovingAverage.output() }
  var centerColor: Float { centerColorAverage.output() }
  var weightedAveragedDerivative: Float { weightedAveragedDerivativeAverage.output() }
  
  var size: Float { x2 - x1 }
  var center: Float { (x1 + x2) / 2 }
  
  
  // Rank multiplier: when area shows up, don't want it to just immediately go to top
  init(initial: CandidateArea, rankMultiplier: Float = 1.0) {
    x1MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x1))
    x2MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x2))
    centerColorAverage                = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.centerColor))
    weightedAveragedDerivativeAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.weightedAveragedDerivative))
  }
  
  func update(update: CandidateArea) {
    x1MovingAverage.input(Float(update.x1))
    x2MovingAverage.input(Float(update.x2))
    centerColorAverage.input(update.centerColor)
    weightedAveragedDerivativeAverage.input(update.weightedAveragedDerivative)
  }
  
  func notFound(colorTendsTo: Float, weightedAverageTendsTo: Float) {
    centerColorAverage.input(colorTendsTo)
    weightedAveragedDerivativeAverage.input(weightedAverageTendsTo)
  }
  
  
  var description: String {
    return String(format: "[%.2f to %.2f], color %.1f, weight %.7f", x1, x2, centerColor, weightedAveragedDerivative)
  }
  
}

public class ActiveAreaSelector {
  fileprivate var candidates: [CandidateAreaHistory] = []
 
  // Each sample the area is not found, the color tends to this value
  let colorTendsTo: Float = 0
  let weightedAverageTendsTo: Float = 0.001
  
  let initialRankMultiplier: Float = 5.0
  
  // Remove candidate areas after this point
  let maxRank: Float = 50
 
  // Areas can be += existing areas
  let maxDeviation: Float = 5
  
  let maxNumCandidates: Int = 4
  
  
  fileprivate static func sort(_ candidates: [CandidateAreaHistory]) -> [CandidateAreaHistory] {
    // Brighter color -> larger is good
    let colorSort  = candidates.sorted(by: { $0.centerColor > $1.centerColor })
    
    // Lower averaged weighted derivative -> smaller is good
    let weightSort = candidates.sorted(by: { $0.weightedAveragedDerivative < $1.weightedAveragedDerivative })
    
    // Sum the color and weight indexes, find the lowest
    let indexSumSort: [(weightIndex: Int, colorIndex: Int, sum: Int)] = colorSort.enumerated().map { (i, val) in
      let weightIndex = weightSort.firstIndex(where: { $0.x1 == val.x1 })!
      return (weightIndex: weightIndex, colorIndex: i, sum: weightIndex + i)
    }.sorted(by: { $0.sum == $1.sum ? $0.colorIndex < $1.colorIndex : $0.sum < $1.sum })
    // If sum of indices are the same, prefer color over weight
    
    let sortedMatches: [CandidateAreaHistory] = indexSumSort.enumerated().map {
      let match = colorSort[$1.colorIndex]
//      match.ranking = $0
      return match
    }
    
    return sortedMatches
  }
  
  func update(candidates newCandidates: [CandidateArea], sizeRange: ClosedRange<Int>?) {
    print()
    print()
    print(newCandidates.count, "candidates received")
    var sortedCandidates = newCandidates.sorted(by: { $0.center < $1.center })
    sortedCandidates.forEach { print($0) }
    print()
    for current in candidates {
      let index = sortedCandidates.firstIndex(where: { current.center - maxDeviation < $0.center && $0.center < current.center + maxDeviation })
      if (index == nil) {
        current.notFound(colorTendsTo: colorTendsTo, weightedAverageTendsTo: weightedAverageTendsTo)
        continue
      }
      let match = sortedCandidates.remove(at: index!)
      
      print("New candidate merged with", current)
      current.update(update: match)
    }
    
    print(sortedCandidates.count, "new candidates")
    for newCandidate in sortedCandidates {
      candidates.append(CandidateAreaHistory(initial: newCandidate, rankMultiplier: initialRankMultiplier))
    }
   
    
    // Sorted by rank
    candidates = Self.sort(candidates)
    if candidates.count > maxNumCandidates {
      print("Removed \(candidates.count - maxNumCandidates) worst candidates")
      candidates = Array(candidates[0..<maxNumCandidates])
    }
    
    var i = 0
    while true {
      if candidates.isEmpty || i >= candidates.count {
        break
      }
      let current = candidates[i]
      /*
      if current.ranking > maxRank {
        print("Removal, rank:", candidates[i])
        candidates.remove(at: i)
      } else */ if sizeRange != nil && (
        current.size < Float(sizeRange!.lowerBound) ||
        current.size > Float(sizeRange!.upperBound)
      ) {
        print("Removal, size:", candidates[i].size, candidates[i])
        candidates.remove(at: i)
      } else {
        i += 1
      }
    }
    
    
    // Duplicate removal. Keep those with highest rank
    i = 0
    while true {
      if candidates.isEmpty || i >= candidates.count - 1 {
        break
      }
      let candidate = candidates[i]
      
      var j = i + 1
      while j < candidates.count {
        let dup = candidates[j]
        if dup.x2 < candidate.x1 || candidate.x2 < dup.x1 {
          j += 1
          continue
        }
        print(String(format: "Removal, overlap [%.1f, %.1f] with [%.1f, %.1f]:", dup.x1, dup.x2, candidate.x1, candidate.x2), dup.description)
        candidates.remove(at: j)
      }
      i += 1
    }
    
    print("Current state")
    candidates.enumerated().forEach {
     print($0, $1)
    }
    
  }
  
  func getActiveArea() -> (x1: Float, x2: Float)? {
    if candidates.isEmpty {
      return nil
    }
    
//    let bestCandidate = candidates.min(by: { $0.ranking < $1.ranking })!
    let bestCandidate = candidates.first!
    return (x1: bestCandidate.x1, x2: bestCandidate.x2)
  }
  
  func getAllAreasSorted() -> [SIMD2<Float>] {
//    let sorted = candidates.sorted(by: { $0.ranking < $1.ranking })
    
    return candidates.map { SIMD2<Float>( $0.x1, $0.x2 )}
  }
}
