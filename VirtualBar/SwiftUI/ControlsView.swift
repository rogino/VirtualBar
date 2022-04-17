//
//  ControlsView.swift
//  VirtualBar
//
//  Created by Rio Ogino on 17/04/22.
//

import SwiftUI

struct ControlsView: View {
  @State var minSize: Float = ImageMean.activeAreaHeightFractionRange.lowerBound
  @State var maxSize: Float = ImageMean.activeAreaHeightFractionRange.upperBound
  @State var threshold: Float = ImageMean.threshold
  
  var range: ClosedRange<Float> = 0.001...0.100
  var thresholdRange: ClosedRange<Float> = 0.001...0.200
  
    var body: some View {
      VStack {
        HStack {
          Text("Threshold")
          Spacer()
          Slider(value: $threshold, in: thresholdRange) {
            Text(String(format: "%.4f", threshold))
              .font(.system(.body, design: .monospaced))
          }
          .onChange(of: threshold) { _ in
            DispatchQueue.main.async {
              ImageMean.threshold = threshold
            }
          }
        }
        HStack {
          Text("Min size")
          Spacer()
          Slider(value: $minSize, in: range) {
            Text(String(format: "%.4f", minSize))
              .font(.system(.body, design: .monospaced))
          }
        }
        HStack {
          Text("Max size")
          Spacer()
          Slider(value: $maxSize, in: range) {
            Text(String(format: "%.4f", maxSize))
              .font(.system(.body, design: .monospaced))
          }
        }
      }
      .onChange(of: minSize) { _ in
        DispatchQueue.main.async {
          if maxSize < minSize {
            maxSize = minSize
          }
          ImageMean.activeAreaHeightFractionRange = minSize...maxSize
        }
      }
      .onChange(of: maxSize) { _ in
        DispatchQueue.main.async {
          if minSize > maxSize {
            minSize = maxSize
          }
          ImageMean.activeAreaHeightFractionRange = minSize...maxSize
        }
      }
    }
}


