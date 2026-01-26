// DriverBridge.swift
// Low-level IPC bridge for communicating with the AppFaders virtual driver
//
// Handles serialization of volume commands and direct AudioObject property access.
// Manages the connection state to the specific AudioDeviceID of the virtual driver.

import CoreAudio
import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "DriverBridge")

// Re-defining constants here since we don't link against the driver target directly
// These must match AppFadersDriver/AudioTypes.swift
private enum AppFadersProperty {
  // 'afvc' - Set Volume Command
  static let setVolume = AudioObjectPropertySelector(0x6166_7663)
  // 'afvq' - Get Volume Query
  static let getVolume = AudioObjectPropertySelector(0x6166_7671)
}

/// handles low-level communication with the AppFaders virtual driver
final class DriverBridge: @unchecked Sendable {
  private var deviceID: AudioDeviceID?
  private let lock = NSLock()

  /// returns true if currently connected to a valid device ID
  var isConnected: Bool {
    lock.withLock { deviceID != nil }
  }

  /// connects to the specified audio device
  /// - Parameter deviceID: The AudioDeviceID of the AppFaders Virtual Device
  func connect(deviceID: AudioDeviceID) throws {
    lock.withLock {
      self.deviceID = deviceID
    }
    os_log(.info, log: log, "DriverBridge connected to deviceID: %u", deviceID)
  }

  /// clears the stored device ID
  func disconnect() {
    lock.withLock {
      deviceID = nil
    }
    os_log(.info, log: log, "DriverBridge disconnected")
  }

  /// sends a volume command to the driver for a specific application
  /// - Parameters:
  ///   - bundleID: The target application's bundle identifier
  ///   - volume: The desired volume level (0.0 - 1.0)
  /// - Throws: DriverError if validation fails or the property write fails
  func setAppVolume(bundleID: String, volume: Float) throws {
    let currentDeviceID = lock.withLock { deviceID }
    guard let deviceID = currentDeviceID else {
      throw DriverError.deviceNotFound
    }

    // Validation
    guard volume >= 0.0, volume <= 1.0 else {
      throw DriverError.invalidVolumeRange(volume)
    }

    guard let bundleIDData = bundleID.data(using: .utf8) else {
      throw DriverError.propertyWriteFailed(kAudioHardwareUnspecifiedError)
    }

    guard bundleIDData.count <= 255 else {
      throw DriverError.bundleIDTooLong(bundleIDData.count)
    }

    // Manual Serialization of VolumeCommand
    // Format: [length: UInt8] [bundleID: 255 bytes] [volume: Float32]
    // Total: 260 bytes
    var data = Data()

    // 1. Length (UInt8)
    data.append(UInt8(bundleIDData.count))

    // 2. Bundle ID (255 bytes, padded)
    data.append(bundleIDData)
    let padding = 255 - bundleIDData.count
    if padding > 0 {
      data.append(Data(repeating: 0, count: padding))
    }

    // 3. Volume (Float32)
    var vol = volume
    withUnsafeBytes(of: &vol) { buffer in
      data.append(contentsOf: buffer)
    }

    // Prepare Property Address
    var address = AudioObjectPropertyAddress(
      mSelector: AppFadersProperty.setVolume,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    // Write Property
    let status = data.withUnsafeBytes { buffer in
      AudioObjectSetPropertyData(
        deviceID,
        &address,
        0, // inQualifierDataSize
        nil, // inQualifierData
        UInt32(buffer.count),
        buffer.baseAddress!
      )
    }

    guard status == noErr else {
      os_log(
        .error,
        log: log,
        "Failed to set volume for %{public}@: %d",
        bundleID,
        status
      )
      throw DriverError.propertyWriteFailed(status)
    }
  }

  /// retrieves the current volume for a specific application from the driver
  /// - Parameter bundleID: The target application's bundle identifier
  /// - Returns: The current volume level (0.0 - 1.0)
  /// - Throws: DriverError if the property read fails
  func getAppVolume(bundleID: String) throws -> Float {
    let currentDeviceID = lock.withLock { deviceID }
    guard let deviceID = currentDeviceID else {
      throw DriverError.deviceNotFound
    }

    guard var bundleIDData = bundleID.data(using: .utf8) else {
      throw DriverError.propertyReadFailed(kAudioHardwareUnspecifiedError)
    }

    guard bundleIDData.count <= 255 else {
      throw DriverError.bundleIDTooLong(bundleIDData.count)
    }

    // Append null terminator for C-string compatibility in the driver
    bundleIDData.append(0)

    var address = AudioObjectPropertyAddress(
      mSelector: AppFadersProperty.getVolume,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    var volume: Float32 = 0.0
    var dataSize = UInt32(MemoryLayout<Float32>.size)

    // Use bundleID (null-terminated) as qualifier data
    let status = bundleIDData.withUnsafeBytes { qualifierBuffer in
      AudioObjectGetPropertyData(
        deviceID,
        &address,
        UInt32(bundleIDData.count),
        qualifierBuffer.baseAddress,
        &dataSize,
        &volume
      )
    }

    guard status == noErr else {
      os_log(
        .error,
        log: log,
        "Failed to get volume for %{public}@: %d",
        bundleID,
        status
      )
      throw DriverError.propertyReadFailed(status)
    }

    return volume
  }
}
