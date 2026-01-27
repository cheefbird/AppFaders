import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders.driver", category: "HelperBridge")
private let machServiceName = "com.fbreidenbach.appfaders.helper"

/// Protocol for driver connections (read-only) - must match helper's definition
@objc protocol AppFadersDriverProtocol {
  func getVolume(bundleID: String, reply: @escaping (Float, NSError?) -> Void)
  func getAllVolumes(reply: @escaping ([String: Float], NSError?) -> Void)
}

/// XPC client for driver-side communication with helper service
/// Uses local cache for real-time audio safety - getVolume never blocks
final class HelperBridge: @unchecked Sendable {
  static let shared = HelperBridge()

  private let lock = NSLock()
  private var connection: NSXPCConnection?
  private var volumeCache: [String: Float] = [:]
  private var isConnected = false

  private init() {
    os_log(.info, log: log, "HelperBridge initialized")
  }

  // MARK: - Connection Management

  /// Establish connection to helper service
  func connect() {
    lock.lock()
    defer { lock.unlock() }

    guard connection == nil else {
      os_log(.debug, log: log, "Already connected")
      return
    }

    os_log(.info, log: log, "Connecting to helper: %{public}@", machServiceName)

    let conn = NSXPCConnection(machServiceName: machServiceName)
    conn.remoteObjectInterface = NSXPCInterface(with: AppFadersDriverProtocol.self)

    conn.invalidationHandler = { [weak self] in
      os_log(.info, log: log, "XPC connection invalidated")
      self?.handleDisconnect()
    }

    conn.interruptionHandler = { [weak self] in
      os_log(.info, log: log, "XPC connection interrupted, will reconnect")
      self?.handleDisconnect()
      self?.scheduleReconnect()
    }

    conn.resume()
    connection = conn
    isConnected = true

    os_log(.info, log: log, "XPC connection established")

    // Defer initial cache refresh - XPC calls during driver init can block
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.refreshCacheAsync()
    }
  }

  /// Disconnect from helper service
  func disconnect() {
    lock.lock()
    defer { lock.unlock() }

    connection?.invalidate()
    connection = nil
    isConnected = false
    os_log(.info, log: log, "Disconnected from helper")
  }

  private func handleDisconnect() {
    lock.lock()
    defer { lock.unlock() }
    connection = nil
    isConnected = false
  }

  private func scheduleReconnect() {
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.connect()
    }
  }

  // MARK: - Volume Access

  /// Get volume for bundle ID - synchronous, returns from cache (never blocks)
  /// - Parameter bundleID: application bundle identifier
  /// - Returns: volume level (defaults to 1.0 if not in cache)
  func getVolume(for bundleID: String) -> Float {
    lock.lock()
    let volume = volumeCache[bundleID] ?? 1.0
    lock.unlock()
    return volume
  }

  /// Refresh volume cache from helper (async)
  func refreshCache() {
    refreshCacheAsync()
  }

  private func refreshCacheAsync() {
    lock.lock()
    let conn = connection
    lock.unlock()

    guard let conn else {
      os_log(.debug, log: log, "Cannot refresh cache - not connected")
      return
    }

    guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
      os_log(
        .error,
        log: log,
        "XPC error during cache refresh: %{public}@",
        error.localizedDescription
      )
    }) as? AppFadersDriverProtocol else {
      os_log(.error, log: log, "Failed to get remote object proxy")
      return
    }

    proxy.getAllVolumes { [weak self] volumes, error in
      if let error {
        os_log(.error, log: log, "getAllVolumes failed: %{public}@", error.localizedDescription)
        return
      }

      self?.lock.lock()
      self?.volumeCache = volumes
      self?.lock.unlock()

      os_log(.debug, log: log, "Cache refreshed: %d entries", volumes.count)
    }
  }
}
