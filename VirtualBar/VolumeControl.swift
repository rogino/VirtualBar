//
//  VolumeControl.swift
//  VirtualBar
//
//  Created by Rio Ogino on 23/04/22.
//


// https://stackoverflow.com/questions/27290751/using-audiotoolbox-from-swift-to-access-os-x-master-volume

import AudioToolbox

public class VolumeControl {
  var defaultOutputDeviceID: AudioObjectID = AudioDeviceID(0)
  
  private static func sizeOf<T>(_ value: T) -> UInt32 {
    return UInt32(MemoryLayout.size(ofValue: value))
  }
  
  init() throws {
    var defaultOutputDeviceIDSize = Self.sizeOf(defaultOutputDeviceID)
    
    var outputDevicePropertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
    )
    
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &outputDevicePropertyAddress,
      0,
      nil,
      &defaultOutputDeviceIDSize,
      &defaultOutputDeviceID
    )
    
    if status != .zero {
      throw fatalError("Error getting default audio device ID: \(status)")
    }
  }
  
  
  // Sets volume, clipping if necessary. Returns volume in range [0, 1], or nil if an error occurred
  func setVolume(volume: Float) -> Float? {
    var volume = Float32(volume)
    if volume < 0 {
      volume = 0
    } else if volume > 1 {
      volume = 1
    }
    let volumeSize = Self.sizeOf(volume)

    var volumePropertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMaster
    )

    let status = AudioObjectSetPropertyData(
      defaultOutputDeviceID,
      &volumePropertyAddress,
      0,
      nil,
      volumeSize,
      &volume
    )
    
    if status != .zero {
      return nil
    }
    return volume
  }
  
  func incrementVolume(delta: Float) -> Float? {
    guard let current = getVolume() else {
      return nil
    }
    return setVolume(volume: current + delta)
  }
  
  func getVolume() -> Float? {
    var volume = Float32(0.0)
    var volumeSize = Self.sizeOf(volume)

    var volumePropertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMaster
    )

    let status = AudioObjectGetPropertyData(
      defaultOutputDeviceID,
      &volumePropertyAddress,
      0,
      nil,
      &volumeSize,
      &volume
    )
    
    if status != .zero {
      print("Error retrieving volume: \(status)")
      return nil
    }

    return volume
  }
}

