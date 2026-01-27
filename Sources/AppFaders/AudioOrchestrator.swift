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

  /// Whether the helper service is currently connected
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
  /// - Maintains connection to the helper service
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

    // 4. Initial connection to helper
    await connectToHelper()

    // 5. Start consuming streams
    await withTaskGroup(of: Void.self) { group in
      // Device List Updates (still useful for knowing if driver is available)
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

  /// Stops the orchestrator (placeholder for interface compliance)
  /// Task cancellation is the primary mechanism to stop start().
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

    // 1. Update local state immediately for UI responsiveness
    appVolumes[bundleID] = volume

    // 2. Send command to helper
    do {
      if driverBridge.isConnected {
        try await driverBridge.setAppVolume(bundleID: bundleID, volume: volume)
      } else {
        os_log(.debug, log: log, "Helper not connected, volume cached for %{public}@", bundleID)
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

      // Restore volumes to helper
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

  /// Checks if driver is available (informational - connection is to helper)
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

      // Sync volume to helper if connected
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
