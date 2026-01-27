import CAAudioHardware
import Foundation
import Observation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AudioOrchestrator")

/// Orchestrates the interaction between the UI, audio system, and running applications
@MainActor
@Observable
final class AudioOrchestrator {
  private(set) var trackedApps: [TrackedApp] = []
  private(set) var isDriverConnected: Bool = false
  private(set) var appVolumes: [String: Float] = [:] // bundleID -> volume

  private let deviceManager: DeviceManager
  private let appAudioMonitor: AppAudioMonitor
  private let driverBridge: DriverBridge

  init() {
    deviceManager = DeviceManager()
    appAudioMonitor = AppAudioMonitor()
    driverBridge = DriverBridge()
    os_log(.info, log: log, "AudioOrchestrator initialized")
  }

  // MARK: - Lifecycle

  /// Starts the orchestration process
  /// - Consumes updates from DeviceManager and AppAudioMonitor
  /// - Maintains connection to the helper service
  /// - Note: This method blocks until the task is cancelled.
  func start() async {
    os_log(.info, log: log, "AudioOrchestrator starting...")

    let deviceUpdates = deviceManager.deviceListUpdates
    let appEvents = appAudioMonitor.events

    appAudioMonitor.start()

    for app in appAudioMonitor.runningApps {
      trackApp(app)
    }

    await connectToHelper()

    await withTaskGroup(of: Void.self) { group in
      group.addTask { [weak self] in
        for await _ in deviceUpdates {
          await self?.checkDriverAvailability()
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

  /// Stops the orchestrator. Cancellation of start() is the primary stop mechanism.
  func stop() {
    os_log(.info, log: log, "AudioOrchestrator stopping")
    driverBridge.disconnect()
    isDriverConnected = false
  }

  // MARK: - Actions

  /// Gets the current volume for an application from the helper
  /// - Parameter bundleID: The bundle identifier of the application
  /// - Returns: The volume level (0.0 - 1.0)
  /// - Throws: Error if the helper communication fails
  func getVolume(for bundleID: String) async throws -> Float {
    guard driverBridge.isConnected else {
      throw DriverError.helperNotRunning
    }
    return try await driverBridge.getAppVolume(bundleID: bundleID)
  }

  /// Sets the volume for a specific application
  /// - Parameters:
  ///   - bundleID: The bundle identifier of the application
  ///   - volume: The volume level (0.0 - 1.0)
  func setVolume(for bundleID: String, volume: Float) async {
    let oldVolume = appVolumes[bundleID]
    appVolumes[bundleID] = volume

    do {
      if driverBridge.isConnected {
        try await driverBridge.setAppVolume(bundleID: bundleID, volume: volume)
      } else {
        os_log(.debug, log: log, "Helper not connected, volume cached for %{public}@", bundleID)
      }
    } catch {
      if let old = oldVolume {
        appVolumes[bundleID] = old
      } else {
        appVolumes.removeValue(forKey: bundleID)
      }

      os_log(
        .error,
        log: log,
        "Failed to set volume for %{public}@: %{public}@",
        bundleID,
        error.localizedDescription
      )
    }
  }

  // MARK: - Private Helpers

  /// Connects to the helper service
  private func connectToHelper() async {
    do {
      try await driverBridge.connect()
      isDriverConnected = true
      os_log(.info, log: log, "Connected to AppFaders Helper Service")
      await restoreVolumes()
    } catch {
      os_log(
        .error,
        log: log,
        "Failed to connect to helper: %{public}@",
        error.localizedDescription
      )
      isDriverConnected = false
    }
  }

  /// Logs driver availability status
  private func checkDriverAvailability() {
    let driverAvailable = deviceManager.appFadersDevice != nil
    os_log(
      .debug,
      log: log,
      "Driver availability check: %{public}@",
      driverAvailable ? "available" : "not found"
    )
  }

  private func restoreVolumes() async {
    for (bundleID, volume) in appVolumes {
      do {
        try await driverBridge.setAppVolume(bundleID: bundleID, volume: volume)
      } catch {
        os_log(
          .error,
          log: log,
          "Failed to restore volume for %{public}@: %{public}@",
          bundleID,
          error.localizedDescription
        )
      }
    }
  }

  /// Handles app launch and termination events
  private func handleAppEvent(_ event: AppLifecycleEvent) async {
    switch event {
    case let .didLaunch(app):
      trackApp(app)

      if let vol = appVolumes[app.bundleID], driverBridge.isConnected {
        do {
          try await driverBridge.setAppVolume(bundleID: app.bundleID, volume: vol)
        } catch {
          os_log(
            .error,
            log: log,
            "Failed to sync volume for launched app %{public}@: %{public}@",
            app.bundleID,
            error.localizedDescription
          )
        }
      }

    case let .didTerminate(bundleID):
      if let index = trackedApps.firstIndex(where: { $0.bundleID == bundleID }) {
        trackedApps.remove(at: index)
        os_log(.debug, log: log, "Tracked app terminated: %{public}@", bundleID)
      }
    }
  }

  private func trackApp(_ app: TrackedApp) {
    if !trackedApps.contains(where: { $0.bundleID == app.bundleID }) {
      trackedApps.append(app)
      if appVolumes[app.bundleID] == nil {
        appVolumes[app.bundleID] = 1.0
      }
      os_log(.debug, log: log, "Tracked app: %{public}@", app.bundleID)
    }
  }
}
