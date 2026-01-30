import AppFadersCore
import AppKit
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menuBarController: MenuBarController?
  private let orchestrator = AudioOrchestrator()
  private var orchestratorTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    os_log(.info, log: log, "AppFaders launching")

    // Menu bar only - no dock icon
    NSApp.setActivationPolicy(.accessory)

    // Create menu bar controller (panel toggle placeholder for now)
    menuBarController = MenuBarController()

    // Start orchestrator in background task
    orchestratorTask = Task {
      await orchestrator.start()
    }

    os_log(.info, log: log, "AppFaders initialization complete")
  }

  func applicationWillTerminate(_ notification: Notification) {
    os_log(.info, log: log, "AppFaders terminating")
    orchestratorTask?.cancel()
    orchestrator.stop()
  }
}
