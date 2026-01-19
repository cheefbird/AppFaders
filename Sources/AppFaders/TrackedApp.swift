import AppKit
import Foundation

/// Represents an application tracked by the AppFaders host orchestrator.
struct TrackedApp: Identifiable, Sendable, Hashable {
  /// The unique identifier for the app, which is its bundle ID.
  var id: String { bundleID }

  /// The bundle identifier of the application.
  let bundleID: String

  /// The localized name of the application.
  let localizedName: String

  /// The icon of the application.
  let icon: NSImage?

  /// The date when the application was launched.
  let launchDate: Date

  /// Initializes a `TrackedApp` from an `NSRunningApplication`.
  /// - Parameter runningApp: The `NSRunningApplication` to extract data from.
  /// - Returns: A `TrackedApp` instance if the `bundleIdentifier` is available, otherwise `nil`.
  init?(from runningApp: NSRunningApplication) {
    guard let bundleID = runningApp.bundleIdentifier else {
      return nil
    }

    self.bundleID = bundleID
    localizedName = runningApp.localizedName ?? bundleID
    icon = runningApp.icon
    launchDate = runningApp.launchDate ?? .distantPast
  }

  // MARK: - Equatable & Hashable

  static func == (lhs: TrackedApp, rhs: TrackedApp) -> Bool {
    lhs.bundleID == rhs.bundleID && lhs.launchDate == rhs.launchDate
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(bundleID)
    hasher.combine(launchDate)
  }
}
