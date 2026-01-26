// VolumeStore.swift
// Thread-safe storage for per-application volume settings
//
// Central source of truth for volume levels, accessed by host and driver via XPC.

import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.helper", category: "VolumeStore")

/// Thread-safe storage for application-specific volumes
final class VolumeStore: @unchecked Sendable {
  static let shared = VolumeStore()

  private let lock = NSLock()
  private var volumes: [String: Float] = [:]

  private init() {
    os_log(.info, log: log, "VolumeStore initialized")
  }

  /// Set volume for a specific application
  /// - Parameters:
  ///   - bundleID: application bundle identifier
  ///   - volume: volume level (0.0 to 1.0)
  func setVolume(for bundleID: String, volume: Float) {
    let clampedVolume = max(0.0, min(1.0, volume))

    lock.lock()
    volumes[bundleID] = clampedVolume
    lock.unlock()

    os_log(.info, log: log, "Volume set for %{public}@: %.2f", bundleID, clampedVolume)
  }

  /// Get volume for a specific application
  /// - Parameter bundleID: application bundle identifier
  /// - Returns: volume level (defaults to 1.0 if unknown)
  func getVolume(for bundleID: String) -> Float {
    lock.lock()
    let volume = volumes[bundleID] ?? 1.0
    lock.unlock()
    return volume
  }

  /// Get all stored volumes
  /// - Returns: dictionary of bundleID to volume
  func getAllVolumes() -> [String: Float] {
    lock.lock()
    let copy = volumes
    lock.unlock()
    return copy
  }

  /// Remove volume setting for an application
  /// - Parameter bundleID: application bundle identifier
  func removeVolume(for bundleID: String) {
    lock.lock()
    volumes.removeValue(forKey: bundleID)
    lock.unlock()

    os_log(.info, log: log, "Volume removed for %{public}@", bundleID)
  }
}
