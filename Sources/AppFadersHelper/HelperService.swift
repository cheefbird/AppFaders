import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.helper", category: "HelperService")

/// Error domain for helper service errors
private let errorDomain = "com.fbreidenbach.appfaders.helper"

/// XPC service implementation for both host and driver protocols
final class HelperService: NSObject, AppFadersHostProtocol, AppFadersDriverProtocol,
@unchecked Sendable {
  static let shared = HelperService()

  override private init() {
    super.init()
    os_log(.info, log: log, "HelperService initialized")
  }

  // MARK: - Validation

  private func validateBundleID(_ bundleID: String) -> NSError? {
    guard bundleID.count <= 255 else {
      os_log(.error, log: log, "Bundle ID too long: %d chars", bundleID.count)
      return NSError(
        domain: errorDomain,
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Bundle ID exceeds 255 characters"]
      )
    }
    guard !bundleID.isEmpty else {
      os_log(.error, log: log, "Bundle ID is empty")
      return NSError(
        domain: errorDomain,
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Bundle ID cannot be empty"]
      )
    }
    return nil
  }

  private func validateVolume(_ volume: Float) -> NSError? {
    guard volume >= 0.0, volume <= 1.0 else {
      os_log(.error, log: log, "Volume out of range: %.2f", volume)
      return NSError(
        domain: errorDomain,
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Volume must be between 0.0 and 1.0"]
      )
    }
    return nil
  }

  // MARK: - AppFadersHostProtocol

  func setVolume(bundleID: String, volume: Float, reply: @escaping (NSError?) -> Void) {
    if let error = validateBundleID(bundleID) {
      reply(error)
      return
    }
    if let error = validateVolume(volume) {
      reply(error)
      return
    }

    VolumeStore.shared.setVolume(for: bundleID, volume: volume)
    os_log(.info, log: log, "setVolume: %{public}@ = %.2f", bundleID, volume)
    reply(nil)
  }

  func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void) {
    if let error = validateBundleID(bundleID) {
      reply(0, error)
      return
    }

    let volume = VolumeStore.shared.getVolume(for: bundleID)
    os_log(.debug, log: log, "getVolume: %{public}@ = %.2f", bundleID, volume)
    reply(volume, nil)
  }

  func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void) {
    let volumes = VolumeStore.shared.getAllVolumes()
    os_log(.debug, log: log, "getAllVolumes: %d entries", volumes.count)
    reply(volumes, nil)
  }
}
