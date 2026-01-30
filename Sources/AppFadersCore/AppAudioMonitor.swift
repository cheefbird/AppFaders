import AppKit
import Foundation
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AppAudioMonitor")

/// lifecycle events for tracked applications
public enum AppLifecycleEvent: Sendable {
  case didLaunch(TrackedApp)
  case didTerminate(String) // bundleID
}

/// monitors running applications using NSWorkspace
public final class AppAudioMonitor: @unchecked Sendable {
  private let workspace = NSWorkspace.shared
  private let lock = NSLock()
  private var _runningApps: [TrackedApp] = []

  /// currently running tracked applications
  public var runningApps: [TrackedApp] {
    lock.lock()
    defer { lock.unlock() }
    return _runningApps
  }

  /// async stream of app lifecycle events
  public var events: AsyncStream<AppLifecycleEvent> {
    AsyncStream { continuation in
      let task = Task { [weak self] in
        guard let self else { return }

        await withTaskGroup(of: Void.self) { group in
          // Launch notifications
          group.addTask { [weak self] in
            for await notification in NotificationCenter.default.notifications(
              named: NSWorkspace.didLaunchApplicationNotification
            ) {
              self?.handleAppLaunch(notification, continuation: continuation)
            }
          }

          // Termination notifications
          group.addTask { [weak self] in
            for await notification in NotificationCenter.default.notifications(
              named: NSWorkspace.didTerminateApplicationNotification
            ) {
              self?.handleAppTerminate(notification, continuation: continuation)
            }
          }
        }
      }

      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  public init() {
    os_log(.info, log: log, "AppAudioMonitor initialized")
  }

  /// starts monitoring and populates initial state
  public func start() {
    // initial snapshot
    let currentApps = workspace.runningApplications
      .compactMap { TrackedApp(from: $0) }

    lock.lock()
    _runningApps = currentApps
    lock.unlock()

    os_log(.info, log: log, "Started monitoring with %d initial apps", currentApps.count)
  }

  private func handleAppLaunch(
    _ notification: Notification,
    continuation: AsyncStream<AppLifecycleEvent>.Continuation
  ) {
    guard let app = notification
      .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      let trackedApp = TrackedApp(from: app)
    else { return }

    lock.lock()
    if !_runningApps.contains(where: { $0.bundleID == trackedApp.bundleID }) {
      _runningApps.append(trackedApp)
      os_log(.debug, log: log, "App launched: %{public}@", trackedApp.bundleID)
      continuation.yield(.didLaunch(trackedApp))
    } else {
      os_log(.debug, log: log, "App launched (already tracked): %{public}@", trackedApp.bundleID)
    }
    lock.unlock()
  }

  private func handleAppTerminate(
    _ notification: Notification,
    continuation: AsyncStream<AppLifecycleEvent>.Continuation
  ) {
    guard let app = notification
      .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
      let bundleID = app.bundleIdentifier
    else { return }

    lock.lock()
    if let index = _runningApps.firstIndex(where: { $0.bundleID == bundleID }) {
      _runningApps.remove(at: index)
    }
    lock.unlock()

    os_log(.debug, log: log, "App terminated: %{public}@", bundleID)
    continuation.yield(.didTerminate(bundleID))
  }
}
