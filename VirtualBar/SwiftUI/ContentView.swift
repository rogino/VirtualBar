//
//  ContentView.swift
//  VirtualBar
//
//  Created by Rio Ogino on 10/04/22.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      MetalView()
//        .aspectRatio(16/9, contentMode: .fit)
      ControlsView()
        .padding()
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
