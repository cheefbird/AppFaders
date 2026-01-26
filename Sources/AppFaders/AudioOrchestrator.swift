// AudioOrchestrator.swift
// Central coordinator for the AppFaders host application
//
// Manages state for the UI, coordinates device discovery, app monitoring,
// and IPC communication with the virtual driver.

import CAAudioHardware
import Foundation
import Observation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AudioOrchestrator")

/// Orchestrates the interaction between the UI, audio system, and running applications
@MainActor
@Observable
final class AudioOrchestrator {
  // MARK: - State

  /// Currently running applications that are tracked
  private(set) var trackedApps: [TrackedApp] = []

  /// Whether the AppFaders Virtual Driver is currently connected
  private(set) var isDriverConnected: Bool = false

  /// Current volume levels for applications (Bundle ID -> Volume 0.0-1.0)
  private(set) var appVolumes: [String: Float] = [:]

  // MARK: - Components

  private let deviceManager: DeviceManager
  private let appAudioMonitor: AppAudioMonitor
  private let driverBridge: DriverBridge

  // MARK: - Initialization

  init() {
    deviceManager = DeviceManager()
    appAudioMonitor = AppAudioMonitor()
    driverBridge = DriverBridge()
    os_log(.info, log: log, "AudioOrchestrator initialized")
  }

  // MARK: - Lifecycle

  /// Starts the orchestration process
  /// - Consumes updates from DeviceManager and AppAudioMonitor
  /// - Maintains connection to the virtual driver
  /// - Note: This method blocks until the task is cancelled.
  func start() async {
    os_log(.info, log: log, "AudioOrchestrator starting...")

    // 1. Capture streams first to avoid race conditions and actor isolation issues
    let deviceUpdates = deviceManager.deviceListUpdates
    let appEvents = appAudioMonitor.events

    // 2. Initialize monitoring (populates initial list)
    appAudioMonitor.start()

    // 3. Process initial apps (deduplicating if stream caught them already)
    for app in appAudioMonitor.runningApps {
      trackApp(app)
    }

    // 4. Initial check for driver
    await checkDriverConnection()

    // 5. Start consuming streams
    await withTaskGroup(of: Void.self) { group in
      // Device List Updates
      group.addTask { [weak self] in
        for await _ in deviceUpdates {
          await self?.checkDriverConnection()
        }
      }

      // App Lifecycle Events
      group.addTask { [weak self] in
        for await event in appEvents {
          await self?.handleAppEvent(event)
        }
      }
    }
  }

  /// Stops the orchestrator (placeholder for interface compliance)
  /// Task cancellation is the primary mechanism to stop start().
  func stop() {
    os_log(.info, log: log, "AudioOrchestrator stopping")
    driverBridge.disconnect()
    isDriverConnected = false
  }

  // MARK: - Actions

  /// Gets the current volume for an application from the driver
  /// - Parameter bundleID: The bundle identifier of the application
  /// - Returns: The volume level (0.0 - 1.0)
  /// - Throws: Error if the driver communication fails
  func getVolume(for bundleID: String) throws -> Float {
    guard driverBridge.isConnected else {
      throw DriverError.deviceNotFound
    }
    return try driverBridge.getAppVolume(bundleID: bundleID)
  }

  /// Sets the volume for a specific application
  /// - Parameters:
  ///   - bundleID: The bundle identifier of the application
  ///   - volume: The volume level (0.0 - 1.0)
  /// - Throws: Error if the driver communication fails
  func setVolume(for bundleID: String, volume: Float) throws {
    let oldVolume = appVolumes[bundleID]

    // 1. Update local state immediately for UI responsiveness
    appVolumes[bundleID] = volume

    // 2. Send command to driver
    do {
      if driverBridge.isConnected {
        try driverBridge.setAppVolume(bundleID: bundleID, volume: volume)
      } else {
        os_log(.debug, log: log, "Driver not connected, volume cached for %{public}@", bundleID)
      }
    } catch {
      // Revert on error to maintain consistency
      if let old = oldVolume {
        appVolumes[bundleID] = old
      } else {
        appVolumes.removeValue(forKey: bundleID)
      }

      os_log(
        .error,
        log: log,
        "Failed to set volume for %{public}@: %@",
        bundleID,
        error as CVarArg
      )
      throw error
    }
  }

  // MARK: - Private Helpers

  /// Checks if the virtual driver is present and updates connection state
  private func checkDriverConnection() async {
    if let device = deviceManager.appFadersDevice {
      if !driverBridge.isConnected {
        do {
          try driverBridge.connect(deviceID: device.objectID)
          isDriverConnected = true
          os_log(.info, log: log, "Connected to AppFaders Virtual Driver")

          // Restore volumes to driver
          restoreVolumes()
        } catch {
          os_log(.error, log: log, "Failed to connect to driver: %@", error as CVarArg)
          isDriverConnected = false
        }
      }
    } else {
      if driverBridge.isConnected {
        driverBridge.disconnect()
        isDriverConnected = false
        os_log(.info, log: log, "Disconnected from AppFaders Virtual Driver")
      }
    }
  }

  private func restoreVolumes() {
    for (bundleID, volume) in appVolumes {
      do {
        try driverBridge.setAppVolume(bundleID: bundleID, volume: volume)
      } catch {
        os_log(
          .error,
          log: log,
          "Failed to restore volume for %{public}@: %@",
          bundleID,
          error as CVarArg
        )
      }
    }
  }

  /// Handles app launch and termination events
  private func handleAppEvent(_ event: AppLifecycleEvent) {
    switch event {
    case let .didLaunch(app):
      trackApp(app)

      // Sync volume to driver if it exists
      if let vol = appVolumes[app.bundleID], driverBridge.isConnected {
        do {
          try driverBridge.setAppVolume(bundleID: app.bundleID, volume: vol)
        } catch {
          os_log(
            .error,
            log: log,
            "Failed to sync volume for launched app %{public}@: %@",
            app.bundleID,
            error as CVarArg
          )
        }
      }

    case let .didTerminate(bundleID):
      if let index = trackedApps.firstIndex(where: { $0.bundleID == bundleID }) {
        trackedApps.remove(at: index)
        os_log(.debug, log: log, "Tracked app terminated: %{public}@", bundleID)
        // We generally keep the volume in appVolumes to remember it for next launch
      }
    }
  }

  private func trackApp(_ app: TrackedApp) {
    if !trackedApps.contains(where: { $0.bundleID == app.bundleID }) {
      trackedApps.append(app)
      // Initialize volume if not present (default 1.0)
      if appVolumes[app.bundleID] == nil {
        appVolumes[app.bundleID] = 1.0
      }
      os_log(.debug, log: log, "Tracked app: %{public}@", app.bundleID)
    }
  }
}
