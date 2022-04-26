//
//  ExponentialWeightedMovingAverage.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

public class ExponentialWeightedMovingAverage: MovingAverage {
  private let alpha: Double
  private let invalidUntilNSamples: UInt16
  private let initialValue: Float
  
  private var numSamples: Int = 0
  private var currentAverage: Double
  
  public convenience init(alpha: Float, initialValue: Float = 0) {
    self.init(alpha: Double(alpha), invalidUntilNSamples: 0, initialValue: initialValue)
  }
  
  public init(alpha: Double, invalidUntilNSamples: UInt16, initialValue: Float) {
    assert(0 <= alpha && alpha <= 1)
    self.alpha = alpha
    self.invalidUntilNSamples = invalidUntilNSamples
    
    self.initialValue = initialValue
    self.currentAverage = Double(initialValue)
  }
  
  public func input(_ val: Float) {
    currentAverage = alpha * Double(val) + (1 - alpha) * currentAverage
    numSamples += 1
  }
  
  public func output() -> Float {
    if numSamples < invalidUntilNSamples {
      return initialValue
    }
    
    return Float(currentAverage)
  }
  
  public func reset() {
    self.currentAverage = Double(initialValue)
    self.numSamples = 0
  }
  
  public func set(_ val: Float) {
    self.currentAverage = Double(val)
  }
  
}
