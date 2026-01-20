// DeviceManager.swift
// Wrapper around SimplyCoreAudio for device discovery and notifications
//
// handles enumeration of audio devices and identifies the AppFaders virtual device.
// provides notifications when the system's device list changes.

import Foundation
import os.log
@preconcurrency import SimplyCoreAudio

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "DeviceManager")

/// manages audio device discovery and status monitoring
/// note: marked as @unchecked Sendable as it wraps the SimplyCoreAudio hardware interface
final class DeviceManager: @unchecked Sendable {
  private let simplyCA = SimplyCoreAudio()
  private let notificationObservers = ThreadSafeArray<NSObjectProtocol>()
  private let lock = NSLock()

  private var _onDeviceListChanged: (@Sendable () -> Void)?
  /// callback triggered when the system audio device list changes
  var onDeviceListChanged: (@Sendable () -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _onDeviceListChanged
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _onDeviceListChanged = newValue
    }
  }

  /// returns all available output devices
  var allOutputDevices: [AudioDevice] {
    simplyCA.allOutputDevices
  }

  /// returns the AppFaders Virtual Device if currently available
  var appFadersDevice: AudioDevice? {
    simplyCA.allOutputDevices.first { $0.uid == "com.fbreidenbach.appfaders.virtualdevice" }
  }

  init() {
    os_log(.info, log: log, "DeviceManager initialized")
  }

  /// starts observing system-wide audio device list changes
  func startObserving() {
    guard notificationObservers.isEmpty else { return }

    let observer = NotificationCenter.default.addObserver(
      forName: .deviceListChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      os_log(.debug, log: log, "Device list changed notification received")
      self?.onDeviceListChanged?()
    }

    notificationObservers.append(observer)
    os_log(.info, log: log, "Started observing device list changes")
  }

  /// stops observing device list changes
  func stopObserving() {
    let observers = notificationObservers.removeAll()
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    os_log(.info, log: log, "Stopped observing device list changes")
  }

  deinit {
    stopObserving()
  }
}

// MARK: - Helper Types

/// basic thread-safe array for managing observer tokens
private final class ThreadSafeArray<T>: @unchecked Sendable {
  private var elements: [T] = []
  private let lock = NSLock()

  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return elements.isEmpty
  }

  func append(_ element: T) {
    lock.lock()
    defer { lock.unlock() }
    elements.append(element)
  }

  func removeAll() -> [T] {
    lock.lock()
    defer { lock.unlock() }
    let copy = elements
    elements.removeAll()
    return copy
  }
}
