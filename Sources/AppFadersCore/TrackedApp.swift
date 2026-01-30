import AppKit
import Foundation

/// Application tracked by the host orchestrator
public struct TrackedApp: Identifiable, Sendable, Hashable {
  public var id: String {
    bundleID
  }

  public let bundleID: String
  public let localizedName: String
  public let icon: NSImage?
  public let launchDate: Date

  public init?(from runningApp: NSRunningApplication) {
    guard let bundleID = runningApp.bundleIdentifier else {
      return nil
    }

    self.bundleID = bundleID
    localizedName = runningApp.localizedName ?? bundleID
    icon = runningApp.icon
    launchDate = runningApp.launchDate ?? .distantPast
  }

  public init(bundleID: String, localizedName: String, icon: NSImage?, launchDate: Date) {
    self.bundleID = bundleID
    self.localizedName = localizedName
    self.icon = icon
    self.launchDate = launchDate
  }

  public static func == (lhs: TrackedApp, rhs: TrackedApp) -> Bool {
    lhs.bundleID == rhs.bundleID && lhs.launchDate == rhs.launchDate
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(bundleID)
    hasher.combine(launchDate)
  }
}
