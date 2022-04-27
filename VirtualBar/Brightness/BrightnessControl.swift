//
//  BrightnessControl.swift
//  VirtualBar
//
//  Created by Rio Ogino on 27/04/22.
//

import Foundation

enum BrightnessError: Error {
  case initializationError(code: Int32)
  case readError
  case setError
}

extension BrightnessError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case let .initializationError(code):
      return "Error initializating brightness controller; failed to get display ID and/or service (\(code))"
    case .readError:
      return "Error getting display brightness"
    case .setError:
      return "Error setting display brightness"
    }
  }
}

class BrightnessControl {
  var displayId: CGDirectDisplayID = 0;
  var displayService: io_service_t = 0;
  init() throws {
    let err = getInternalDisplayIdAndService(&displayId, &displayService);
    if err != 0 {
      throw BrightnessError.initializationError(code: err)
    }
  }
  
  // can't call it getBrightness as the C function is called that
  func get() throws -> Float {
    var brightness: Float = -1;
    if (!getBrightness(displayId, displayService, &brightness)) {
      throw BrightnessError.readError
    }
    return brightness
  }
  
  func set(brightness: Float) throws -> Float {
    let brightness: Float = max(0, min(1, brightness))
    if (!setBrightness(displayId, displayService, brightness)) {
      throw BrightnessError.setError
    }
    
    return brightness
    
  }
}
