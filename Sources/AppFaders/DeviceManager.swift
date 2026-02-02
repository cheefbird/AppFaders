@preconcurrency import CAAudioHardware
import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "DeviceManager")

/// manages audio device discovery and status monitoring
final class DeviceManager: Sendable {
  /// returns all available output devices
  var allOutputDevices: [AudioDevice] {
    do {
      return try AudioDevice.devices.filter { try $0.supportsOutput }
    } catch {
      os_log(.error, log: log, "Failed to get all output devices: %@", error as CVarArg)
      return []
    }
  }

  /// returns the AppFaders Virtual Device if currently available
  var appFadersDevice: AudioDevice? {
    do {
      guard let deviceID = try AudioSystem.instance
        .deviceID(forUID: "com.fbreidenbach.appfaders.virtualdevice")
      else {
        return nil
      }
      let audioObject = try AudioObject.make(deviceID)
      guard let device = audioObject as? AudioDevice else {
        os_log(.error, log: log, "Found object for UID is not an AudioDevice")
        return nil
      }
      return device
    } catch {
      os_log(.error, log: log, "Failed to find AppFaders device: %@", error as CVarArg)
      return nil
    }
  }

  /// an async stream of notifications for device list changes
  var deviceListUpdates: AsyncStream<Void> {
    AsyncStream { continuation in
      do {
        try AudioSystem.instance.whenSelectorChanges(.devices) { _ in
          continuation.yield()
        }
      } catch {
        os_log(.error, log: log, "Failed to subscribe to device list changes: %@", error as CVarArg)
        continuation.finish()
      }

      continuation.onTermination = { @Sendable _ in
        // To stop observing, CAAudioHardware expects passing nil to the block
        try? AudioSystem.instance.whenSelectorChanges(.devices, perform: nil)
      }
    }
  }

  /// returns the default system output device
  var defaultOutputDevice: AudioDevice? {
    try? AudioDevice.defaultOutputDevice
  }

  // MARK: - System Volume Control

  /// gets the current system output volume (0.0-1.0)
  func getSystemVolume() -> Float {
    guard let device = defaultOutputDevice else {
      os_log(.error, log: log, "No default output device for getSystemVolume")
      return 1.0
    }
    do {
      return try device.volumeScalar(inScope: .output)
    } catch {
      os_log(.error, log: log, "Failed to get system volume: %@", error as CVarArg)
      return 1.0
    }
  }

  /// sets the system output volume (0.0-1.0)
  func setSystemVolume(_ volume: Float) {
    guard let device = defaultOutputDevice else {
      os_log(.error, log: log, "No default output device for setSystemVolume")
      return
    }
    let clamped = max(0.0, min(1.0, volume))
    do {
      try device.setVolumeScalar(clamped, inScope: .output)
    } catch {
      os_log(.error, log: log, "Failed to set system volume: %@", error as CVarArg)
    }
  }

  /// gets the current system mute state
  func getSystemMute() -> Bool {
    guard let device = defaultOutputDevice else {
      os_log(.error, log: log, "No default output device for getSystemMute")
      return false
    }
    do {
      return try device.mute(inScope: .output)
    } catch {
      os_log(.error, log: log, "Failed to get system mute: %@", error as CVarArg)
      return false
    }
  }

  /// sets the system mute state
  func setSystemMute(_ muted: Bool) {
    guard let device = defaultOutputDevice else {
      os_log(.error, log: log, "No default output device for setSystemMute")
      return
    }
    do {
      try device.setMute(muted, inScope: .output)
    } catch {
      os_log(.error, log: log, "Failed to set system mute: %@", error as CVarArg)
    }
  }

  init() {
    os_log(.info, log: log, "DeviceManager initialized")
  }
}
