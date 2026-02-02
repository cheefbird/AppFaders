import Foundation

/// errors related to driver communication and management
public enum DriverError: Error, LocalizedError, Equatable, Sendable {
  case deviceNotFound
  case propertyReadFailed(OSStatus)
  case propertyWriteFailed(OSStatus)
  case invalidVolumeRange(Float)
  case bundleIDTooLong(Int)

  // MARK: - XPC Errors

  case helperNotRunning
  case connectionFailed(String)
  case connectionInterrupted
  case remoteError(String)

  public var errorDescription: String? {
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
    case .helperNotRunning:
      "AppFaders helper service is not running."
    case let .connectionFailed(reason):
      "Failed to connect to helper service: \(reason)"
    case .connectionInterrupted:
      "Connection to helper service was interrupted."
    case let .remoteError(message):
      "Helper service error: \(message)"
    }
  }
}
