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

  init() {
    os_log(.info, log: log, "DeviceManager initialized")
  }
}
