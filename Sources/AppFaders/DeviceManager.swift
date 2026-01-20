// DeviceManager.swift
// Wrapper around SimplyCoreAudio for device discovery and notifications
//
// handles enumeration of audio devices and identifies the AppFaders virtual device.
// provides notifications when the system's device list changes via AsyncStream.

import Foundation
import os.log
@preconcurrency import SimplyCoreAudio

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "DeviceManager")

/// manages audio device discovery and status monitoring
/// note: marked as @unchecked Sendable as it wraps the SimplyCoreAudio hardware interface
final class DeviceManager: @unchecked Sendable {
  private let simplyCA = SimplyCoreAudio()

  /// returns all available output devices
  var allOutputDevices: [AudioDevice] {
    simplyCA.allOutputDevices
  }

  /// returns the AppFaders Virtual Device if currently available
  var appFadersDevice: AudioDevice? {
    simplyCA.allOutputDevices.first { $0.uid == "com.fbreidenbach.appfaders.virtualdevice" }
  }

  /// an async stream of notifications for device list changes
  var deviceListUpdates: AsyncStream<Void> {
    AsyncStream { continuation in
      let task = Task { [weak self] in
        guard self != nil else { return }
        for await _ in NotificationCenter.default.notifications(named: .deviceListChanged) {
          continuation.yield()
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  init() {
    os_log(.info, log: log, "DeviceManager initialized")
  }
}
