import AppKit
import Foundation

/// Application tracked by the host orchestrator
struct TrackedApp: Identifiable, Sendable, Hashable {
  var id: String { bundleID }

  let bundleID: String
  let localizedName: String
  let icon: NSImage?
  let launchDate: Date

  init?(from runningApp: NSRunningApplication) {
    guard let bundleID = runningApp.bundleIdentifier else {
      return nil
    }

    self.bundleID = bundleID
    localizedName = runningApp.localizedName ?? bundleID
    icon = runningApp.icon
    launchDate = runningApp.launchDate ?? .distantPast
  }

  init(bundleID: String, localizedName: String, icon: NSImage?, launchDate: Date) {
    self.bundleID = bundleID
    self.localizedName = localizedName
    self.icon = icon
    self.launchDate = launchDate
  }

  static func == (lhs: TrackedApp, rhs: TrackedApp) -> Bool {
    lhs.bundleID == rhs.bundleID && lhs.launchDate == rhs.launchDate
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleID)
    hasher.combine(launchDate)
  }
}
