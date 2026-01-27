import CoreAudio
import Foundation
import os.log

// MARK: - HAL Type Aliases

// opaque pointers for unbridged types - C layer handles actual struct access
public typealias AudioServerPlugInHostRef = OpaquePointer
public typealias AudioServerPlugInClientInfoRef = UnsafeRawPointer

// MARK: - Logging

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.driver", category: "DriverEntry")

// MARK: - Driver Entry Singleton

/// thread-safe singleton for plug-in lifecycle
final class DriverEntry: @unchecked Sendable {
  static let shared = DriverEntry()

  /// for property change notifications
  private var host: AudioServerPlugInHostRef?

  private(set) var plugInObjectID: AudioObjectID = ObjectID.plugIn
  private(set) var deviceObjectID: AudioObjectID = ObjectID.device

  private let lock = NSLock()

  private init() {
    os_log(.info, log: log, "DriverEntry singleton created")
  }

  // MARK: - Lifecycle

  /// called by coreaudiod after loading the driver bundle
  func initialize(host: AudioServerPlugInHostRef) -> OSStatus {
    lock.lock()
    defer { lock.unlock() }

    os_log(.info, log: log, "initialize called")

    // guard against double-init (shouldn't happen but be safe)
    guard self.host == nil else {
      os_log(.error, log: log, "initialize called but already initialized")
      return noErr
    }

    self.host = host

    // Connect to helper XPC service for volume data
    HelperBridge.shared.connect()

    // VirtualDevice is a singleton, accessed via VirtualDevice.shared
    os_log(.debug, log: log, "initialize complete - device ID: %u", deviceObjectID)
    return noErr
  }

  /// not supported - device created at init time
  func createDevice(
    description: CFDictionary?,
    clientInfo: AudioServerPlugInClientInfoRef?
  ) -> (OSStatus, AudioObjectID) {
    os_log(.info, log: log, "createDevice called - not supported")
    return (kAudioHardwareUnsupportedOperationError, kAudioObjectUnknown)
  }

  /// not supported - no dynamic device destruction
  func destroyDevice(deviceID: AudioObjectID) -> OSStatus {
    os_log(.info, log: log, "destroyDevice called for %u - not supported", deviceID)
    return kAudioHardwareUnsupportedOperationError
  }

  // MARK: - Host Communication

  func getHost() -> AudioServerPlugInHostRef? {
    lock.lock()
    defer { lock.unlock() }
    return host
  }

  /// call when device/stream properties change
  func notifyPropertiesChanged(
    objectID: AudioObjectID,
    addresses: [AudioObjectPropertyAddress]
  ) {
    guard getHost() != nil else {
      os_log(.error, log: log, "notifyPropertiesChanged: no host reference")
      return
    }

    // TODO(task9): implement host.PropertiesChanged call
    os_log(
      .debug,
      log: log,
      "notifyPropertiesChanged: %u properties on object %u",
      addresses.count,
      objectID
    )
  }
}

// MARK: - C Interface Exports

// called from PlugInInterface.c Initialize()
@_cdecl("AppFadersDriver_Initialize")
public func driverInitialize(host: AudioServerPlugInHostRef) -> OSStatus {
  DriverEntry.shared.initialize(host: host)
}

// called from PlugInInterface.c CreateDevice()
@_cdecl("AppFadersDriver_CreateDevice")
public func driverCreateDevice(
  description: CFDictionary?,
  clientInfo: AudioServerPlugInClientInfoRef?,
  outDeviceID: UnsafeMutablePointer<AudioObjectID>?
) -> OSStatus {
  let (status, deviceID) = DriverEntry.shared.createDevice(
    description: description,
    clientInfo: clientInfo
  )
  outDeviceID?.pointee = deviceID
  return status
}

// called from PlugInInterface.c DestroyDevice()
@_cdecl("AppFadersDriver_DestroyDevice")
public func driverDestroyDevice(deviceID: AudioObjectID) -> OSStatus {
  DriverEntry.shared.destroyDevice(deviceID: deviceID)
}
