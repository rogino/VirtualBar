//
//  ActiveAreaSelector.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

import Foundation

  
public struct CandidateArea {
  let x1: Int
  let size: Int
  var x2: Int { x1 + size }
  var center: Float { Float(x1) + Float(size) / 2.0 }
  
  let centerColor: Float
  let weightedAveragedDerivative: Float
  var ranking: Int
}


private class CandidateAreaHistory: CustomStringConvertible {
  let x1MovingAverage: MovingAverage
  let x2MovingAverage: MovingAverage
  let  rankingAverage: MovingAverage
  
  var      x1: Float { x1MovingAverage.output() }
  var      x2: Float { x2MovingAverage.output() }
  var ranking: Float {  rankingAverage.output() }
  
  var size: Float { x2 - x1 }
  var center: Float { (x1 + x2) / 2 }
  
  
  // Rank multiplier: when area shows up, don't want it to just immediately go to top
  init(initial: CandidateArea, rankMultiplier: Float = 1.0) {
    x1MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x1))
    x2MovingAverage = ExponentialWeightedMovingAverage(alpha: 0.05, invalidUntilNSamples: 0, initialValue: Float(initial.x2))
     rankingAverage = ExponentialWeightedMovingAverage(alpha: 0.10, invalidUntilNSamples: 0, initialValue: Float(initial.ranking) * rankMultiplier)
  }
  
  func update(update: CandidateArea) {
    x1MovingAverage.input(Float(update.x1))
    x2MovingAverage.input(Float(update.x2))
     rankingAverage.input(Float(update.ranking))
  }
  
  func notFound(rankTendsTo: Float) {
    rankingAverage.input(rankTendsTo)
  }
  
  
  var description: String {
    return String(format: "[%.2f to %.2f], rank %.1f", x1, x2, ranking)
  }
  
}

public class ActiveAreaSelector {
  fileprivate var candidates: [CandidateAreaHistory] = []
 
  // Each sample the area is not found, the rank tends to this value
  let rankAging: Float = 100
  
  let initialRankMultiplier: Float = 5.0
  
  // Remove candidate areas after this point
  let maxRank: Float = 50
 
  // Areas can be += existing areas
  let maxDeviation: Float = 5
  
  
  func update(candidates newCandidates: [CandidateArea], sizeRange: ClosedRange<Int>?) {
    print(newCandidates.count, "candidates received")
    var sortedCandidates = newCandidates.sorted(by: { $0.center < $1.center })
    for current in candidates {
      let index = sortedCandidates.firstIndex(where: { current.center - maxDeviation < $0.center && $0.center < current.center + maxDeviation })
      if (index == nil) {
        current.notFound(rankTendsTo: rankAging)
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
    
    var i = 0
    while true {
      if candidates.isEmpty || i >= candidates.count {
        break
      }
      let current = candidates[i]
      if current.ranking > maxRank {
        print("Removal, rank:", candidates[i])
        candidates.remove(at: i)
      } else if sizeRange != nil && (
        current.size < Float(sizeRange!.lowerBound) ||
        current.size > Float(sizeRange!.upperBound)
      ) {
        print("Removal, size:", candidates[i].size, candidates[i])
        candidates.remove(at: i)
      } else {
        i += 1
      }
    }
    
    
    candidates = candidates.sorted(by: { $0.ranking < $1.ranking })
    
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
        print(String(format: "Removal, overlap [%.1f, %.1f] with rank %.1f [%.1f, %.1f]:", dup.x1, dup.x2, candidate.ranking, candidate.x1, candidate.x2), dup.description)
        candidates.remove(at: j)
      }
      
      i += 1
    }
    
  }
  
  func getActiveArea() -> (x1: Float, x2: Float)? {
    if candidates.isEmpty {
      return nil
    }
    
    let bestCandidate = candidates.min(by: { $0.ranking < $1.ranking })!
    return (x1: bestCandidate.x1, x2: bestCandidate.x2)
  }
  
  func getAllAreasSorted() -> [SIMD2<Float>] {
    let sorted = candidates.sorted(by: { $0.ranking < $1.ranking })
    
    return sorted.map { SIMD2<Float>( $0.x1, $0.x2 )}
  }
}
