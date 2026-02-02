import AppFadersCore
import AppKit
import Foundation
import Observation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AppState")

// MARK: - AppVolumeState

/// Represents the volume state for a single application
/// Note: @unchecked Sendable because NSImage isn't Sendable, but this struct
/// is only used within @MainActor context (AppState)
struct AppVolumeState: Identifiable, @unchecked Sendable {
  let id: String // bundleID
  let name: String
  let icon: NSImage?
  var volume: Float // 0.0-1.0
  var isMuted: Bool
  var previousVolume: Float // for restore on unmute

  var displayPercentage: String {
    isMuted ? "Muted" : "\(Int(volume * 100))%"
  }

  init(from trackedApp: TrackedApp, volume: Float, isMuted: Bool = false) {
    id = trackedApp.bundleID
    name = trackedApp.localizedName
    icon = trackedApp.icon
    self.volume = volume
    self.isMuted = isMuted
    previousVolume = volume
  }
}

// MARK: - AppState

/// Central state container driving SwiftUI updates
@MainActor
@Observable
final class AppState {
  private(set) var apps: [AppVolumeState] = []
  var masterVolume: Float = 1.0
  var masterMuted: Bool = false
  var isPanelVisible: Bool = false
  var connectionError: String?

  private let orchestrator: AudioOrchestrator
  private let deviceManager: DeviceManager

  init(orchestrator: AudioOrchestrator, deviceManager: DeviceManager) {
    self.orchestrator = orchestrator
    self.deviceManager = deviceManager

    // Initialize master volume from system
    masterVolume = deviceManager.getSystemVolume()
    masterMuted = deviceManager.getSystemMute()

    os_log(.info, log: log, "AppState initialized")
  }

  // MARK: - Per-App Volume Control

  /// Sets the volume for a specific application
  func setVolume(for bundleID: String, volume: Float) async {
    guard let index = apps.firstIndex(where: { $0.id == bundleID }) else { return }

    let clamped = max(0.0, min(1.0, volume))
    apps[index].volume = clamped

    // If setting volume while muted, unmute
    if apps[index].isMuted, clamped > 0 {
      apps[index].isMuted = false
    }

    await orchestrator.setVolume(for: bundleID, volume: clamped)
  }

  /// Toggles mute state for a specific application
  func toggleMute(for bundleID: String) async {
    guard let index = apps.firstIndex(where: { $0.id == bundleID }) else { return }

    if apps[index].isMuted {
      // Unmute: restore previous volume
      apps[index].isMuted = false
      apps[index].volume = apps[index].previousVolume
      await orchestrator.setVolume(for: bundleID, volume: apps[index].previousVolume)
    } else {
      // Mute: store current volume, set to 0
      apps[index].previousVolume = apps[index].volume
      apps[index].isMuted = true
      apps[index].volume = 0
      await orchestrator.setVolume(for: bundleID, volume: 0)
    }
  }

  // MARK: - Master Volume Control

  /// Sets the master (system) volume
  func setMasterVolume(_ volume: Float) {
    let clamped = max(0.0, min(1.0, volume))
    masterVolume = clamped

    // If setting volume while muted, unmute
    if masterMuted, clamped > 0 {
      masterMuted = false
      deviceManager.setSystemMute(false)
    }

    deviceManager.setSystemVolume(clamped)
  }

  /// Toggles master (system) mute
  func toggleMasterMute() {
    masterMuted.toggle()
    deviceManager.setSystemMute(masterMuted)
  }

  // MARK: - Sync from Orchestrator

  /// Syncs app list from AudioOrchestrator's tracked apps and volumes
  func syncFromOrchestrator() {
    let trackedApps = orchestrator.trackedApps
    let volumes = orchestrator.appVolumes

    // Build new app states, preserving mute state for existing apps
    var newApps: [AppVolumeState] = []
    for trackedApp in trackedApps {
      let volume = volumes[trackedApp.bundleID] ?? 1.0

      // Check if we have existing state for this app (preserve mute)
      if let existing = apps.first(where: { $0.id == trackedApp.bundleID }) {
        var updated = AppVolumeState(from: trackedApp, volume: volume, isMuted: existing.isMuted)
        updated.previousVolume = existing.previousVolume
        // If muted, keep showing 0 volume
        if existing.isMuted {
          updated.volume = 0
        }
        newApps.append(updated)
      } else {
        newApps.append(AppVolumeState(from: trackedApp, volume: volume))
      }
    }

    apps = newApps

    // Update connection error status
    connectionError = orchestrator.isDriverConnected ? nil : "Helper service not connected"
  }

  /// Refreshes master volume from system (call when panel opens)
  func refreshMasterVolume() {
    masterVolume = deviceManager.getSystemVolume()
    masterMuted = deviceManager.getSystemMute()
  }

  // MARK: - App Lifecycle

  /// Terminates the application
  func quit() {
    os_log(.info, log: log, "Quit requested via AppState")
    NSApp.terminate(nil)
  }
}
