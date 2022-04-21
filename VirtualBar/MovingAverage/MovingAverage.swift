//
//  MovingAverage.swift
//  VirtualBar
//
//  Created by Rio Ogino on 21/04/22.
//

public protocol MovingAverage {
  func input(_: Float)
  func output() -> Float
}
