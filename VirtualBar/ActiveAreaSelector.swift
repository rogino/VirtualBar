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


private class CandidateAreaHistory: CustomStringConvertible, Identifiable {
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
  
  var xAlpha: Float = 0.05
  var centerBrightnessAlpha: Float = 0.05
  var weightedAveragedDerivativeAlpha: Float = 0.05
  
  let id = UUID()
  
  // Rank multiplier: when area shows up, don't want it to just immediately go to top
  init(initial: CandidateArea, rankMultiplier: Float = 1.0) {
    x1MovingAverage = ExponentialWeightedMovingAverage(alpha: xAlpha, initialValue: Float(initial.x1))
    x2MovingAverage = ExponentialWeightedMovingAverage(alpha: xAlpha, initialValue: Float(initial.x2))
    centerBrightnessAverage           = ExponentialWeightedMovingAverage(alpha: centerBrightnessAlpha, initialValue: Float(initial.centerBrightness))
    weightedAveragedDerivativeAverage = ExponentialWeightedMovingAverage(alpha: weightedAveragedDerivativeAlpha, initialValue: Float(initial.weightedAveragedDerivative))
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
    return String(format: "[%.2f to %.2f], brightness %.3f, weight %.7f", x1, x2, centerBrightness, weightedAveragedDerivative)
  }
  
}

public class ActiveAreaSelector {
  let LOG = true
  static let ONLY_USE_COLOR_SORT = false
  static let ONLY_USE_DERIVATIVE_SORT = false
  
  fileprivate var candidates: [CandidateAreaHistory] = []
  

  // For each sample in which the area is not found, the color tends to this value
  let brightnessTendsTo: Float = 0
  let weightedAverageTendsTo: Float = 0.001
  
  let initialRankMultiplier: Float = 5.0
  
  // Areas can be += existing areas
  let maxCenterPositionDeviation: Float = 5
  
  let maxNumCandidates: Int = 4
  
  let maxWeightedAveragedDerivative: Float = 1e-4
  let minBrightness: Float = 0.1
  
  var lockedCandidateId: UUID? = nil
  
  fileprivate static func sort(_ candidates: [CandidateAreaHistory]) -> [CandidateAreaHistory] {
    // Brighter color -> larger is good
    let colorSort  = candidates.sorted(by: { $0.centerBrightness > $1.centerBrightness })
    if ONLY_USE_COLOR_SORT {
      print("WARNING: ONLY USING BRIGHTNESS FOR RANKING")
      return colorSort
    }
    
    // Lower averaged weighted derivative -> smaller is good
    let weightSort = candidates.sorted(by: { $0.weightedAveragedDerivative < $1.weightedAveragedDerivative })
    
    if ONLY_USE_DERIVATIVE_SORT {
      print("WARNING: ONLY USING DERIVATIVE FOR RANKING")
      return weightSort
    }
    
    // Sum the color and weight indexes, find the lowest
    let indexSumSort: [(weightIndex: Int, colorIndex: Int, sum: Int)] = colorSort.enumerated().map { (i, val) in
      let weightIndex = weightSort.firstIndex(where: { $0.x1 == val.x1 })!
      return (weightIndex: weightIndex, colorIndex: i, sum: weightIndex + i)
    }.sorted(by: { $0.sum == $1.sum ? $0.colorIndex < $1.colorIndex : $0.sum < $1.sum })
    // If sum of indices are the same, prefer color over weight
    
    let sortedMatches: [CandidateAreaHistory] = indexSumSort.enumerated().map { colorSort[$1.colorIndex] }
    
    return sortedMatches
  }
  
  fileprivate static func moveLockedCandidateToTop(_ candidates: inout [CandidateAreaHistory], lockedCandidateId: UUID?) {
    guard let lockedCandidateId = lockedCandidateId else {
      return
    }
    
    let lockedCandidate = candidates.enumerated().first(where: { $0.element.id == lockedCandidateId })
    assert(lockedCandidate != nil)
    let index = lockedCandidate!.offset
    if index != 0 {
      candidates.remove(at: index)
      candidates.insert(lockedCandidate!.element, at: 0)
    }
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
      let index = sortedCandidates.firstIndex(where: { current.center - maxCenterPositionDeviation < $0.center && $0.center < current.center + maxCenterPositionDeviation })
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
    if LOG && lockedCandidateId != nil {
      print("Locked candidate native rank: \(candidates.enumerated().first(where: { $0.element.id == lockedCandidateId })?.offset.description ?? "WARNING: LOCKED CANDIDATE NOT FOUND")")
    }
    Self.moveLockedCandidateToTop(&candidates, lockedCandidateId: lockedCandidateId)
    
    // Cut down number of candidates
    if candidates.count > maxNumCandidates {
      if LOG {
        print("Removed \(candidates.count - maxNumCandidates) worst candidates")
      }
      candidates.removeLast(candidates.count - maxNumCandidates)
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
      if lockedCandidateId != nil && lockedCandidateId == current.id {
        i += 1
        continue
      }
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
  
  // Prevent top candidate from being changed
  func lockCurrentTopCandidate() {
    lockedCandidateId = candidates.first?.id
    if LOG && candidates.first != nil {
      print("Locking current top candidate, \(candidates.first!)")
    }
  }
  
  
  func unlockCurrentTopCandidate() {
    if lockedCandidateId == nil {
      return
    }
    if LOG {
      assert(candidates.first != nil && candidates.first!.id == lockedCandidateId)
      print("Unlocking current top candidate, \(candidates.first!)")
    }
    lockedCandidateId = nil
    candidates = Self.sort(candidates)
  }
}
