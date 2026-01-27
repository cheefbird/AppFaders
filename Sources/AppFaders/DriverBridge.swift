// DriverBridge.swift
// XPC client for communicating with the AppFaders helper service
//
// Handles async volume commands via XPC. Replaces the defunct AudioObject property approach.

import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "DriverBridge")
private let machServiceName = "com.fbreidenbach.appfaders.helper"

/// handles communication with the AppFaders helper service via XPC
final class DriverBridge: @unchecked Sendable {
  private let lock = NSLock()
  private var connection: NSXPCConnection?

  /// returns true if currently connected to the helper service
  var isConnected: Bool {
    lock.withLock { connection != nil }
  }

  // MARK: - Connection Management

  /// establishes XPC connection to the helper service
  func connect() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      lock.lock()

      if connection != nil {
        lock.unlock()
        continuation.resume()
        return
      }

      os_log(.info, log: log, "Connecting to helper: %{public}@", machServiceName)

      let conn = NSXPCConnection(machServiceName: machServiceName)
      conn.remoteObjectInterface = NSXPCInterface(with: AppFadersHostProtocol.self)

      conn.invalidationHandler = { [weak self] in
        os_log(.info, log: log, "XPC connection invalidated")
        self?.handleDisconnect()
      }

      conn.interruptionHandler = { [weak self] in
        os_log(.info, log: log, "XPC connection interrupted")
        self?.handleDisconnect()
      }

      conn.resume()
      connection = conn
      lock.unlock()

      os_log(.info, log: log, "XPC connection established")
      continuation.resume()
    }
  }

  /// disconnects from the helper service
  func disconnect() {
    lock.lock()
    defer { lock.unlock() }

    connection?.invalidate()
    connection = nil
    os_log(.info, log: log, "Disconnected from helper")
  }

  private func handleDisconnect() {
    lock.lock()
    defer { lock.unlock() }
    connection = nil
  }

  // MARK: - Volume Commands

  /// sends a volume command to the helper for a specific application
  /// - Parameters:
  ///   - bundleID: The target application's bundle identifier
  ///   - volume: The desired volume level (0.0 - 1.0)
  /// - Throws: DriverError if validation fails or XPC call fails
  func setAppVolume(bundleID: String, volume: Float) async throws {
    // Validation
    guard volume >= 0.0, volume <= 1.0 else {
      throw DriverError.invalidVolumeRange(volume)
    }

    guard bundleID.utf8.count <= 255 else {
      throw DriverError.bundleIDTooLong(bundleID.utf8.count)
    }

    let proxy = try getProxy()

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      proxy.setVolume(bundleID: bundleID, volume: volume) { error in
        if let error = error {
          continuation.resume(throwing: DriverError.remoteError(error.localizedDescription))
        } else {
          continuation.resume()
        }
      }
    }
  }

  /// retrieves the current volume for a specific application from the helper
  /// - Parameter bundleID: The target application's bundle identifier
  /// - Returns: The current volume level (0.0 - 1.0)
  /// - Throws: DriverError if validation fails or XPC call fails
  func getAppVolume(bundleID: String) async throws -> Float {
    guard bundleID.utf8.count <= 255 else {
      throw DriverError.bundleIDTooLong(bundleID.utf8.count)
    }

    let proxy = try getProxy()

    return try await withCheckedThrowingContinuation { continuation in
      proxy.getVolume(bundleID: bundleID) { volume, error in
        if let error = error {
          continuation.resume(throwing: DriverError.remoteError(error.localizedDescription))
        } else {
          continuation.resume(returning: volume)
        }
      }
    }
  }

  // MARK: - Private Helpers

  private func getProxy() throws -> AppFadersHostProtocol {
    lock.lock()
    let conn = connection
    lock.unlock()

    guard let conn = conn else {
      throw DriverError.helperNotRunning
    }

    guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
      os_log(.error, log: log, "XPC proxy error: %{public}@", error.localizedDescription)
    }) as? AppFadersHostProtocol else {
      throw DriverError.connectionFailed("Failed to get remote object proxy")
    }

    return proxy
  }
}
