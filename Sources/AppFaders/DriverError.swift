// DriverError.swift
// Error types for the AppFaders host orchestrator
//
// defines errors that can occur during audio device management and IPC bridge operations.

import Foundation

/// errors related to driver communication and management
enum DriverError: Error, LocalizedError {
  /// the virtual audio device could not be found
  case deviceNotFound
  /// failed to read a property from the audio object
  case propertyReadFailed(OSStatus)
  /// failed to write a property to the audio object
  case propertyWriteFailed(OSStatus)
  /// the provided volume is outside the valid range (0.0 - 1.0)
  case invalidVolumeRange(Float)
  /// the bundle identifier exceeds the maximum allowed length
  case bundleIDTooLong(Int)

  var errorDescription: String? {
    switch self {
    case .deviceNotFound:
      "AppFaders Virtual Device not found. Please ensure the driver is installed."
    case let .propertyReadFailed(status):
      "Failed to read driver property (OSStatus: \(status))."
    case let .propertyWriteFailed(status):
      "Failed to write driver property (OSStatus: \(status))."
    case let .invalidVolumeRange(volume):
      "Invalid volume level: \(volume). Must be between 0.0 and 1.0."
    case let .bundleIDTooLong(length):
      "Bundle identifier is too long (\(length) bytes). Max is 255."
    }
  }
}
