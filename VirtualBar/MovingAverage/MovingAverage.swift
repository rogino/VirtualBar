//
//  MovingAverage.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

public protocol MovingAverage {
  associatedtype T
  func input(_: T)
  func output() -> T
}
