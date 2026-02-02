import AppFadersCore
import AppKit
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menuBarController: MenuBarController?
  private let orchestrator = AudioOrchestrator()
  private let deviceManager = DeviceManager()
  private var appState: AppState?
  private var orchestratorTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    os_log(.info, log: log, "AppFaders launching")

    NSApp.setActivationPolicy(.accessory)

    // Create AppState with dependencies
    let state = AppState(orchestrator: orchestrator, deviceManager: deviceManager)
    appState = state

    // Create menu bar controller with state
    menuBarController = MenuBarController(appState: state)

    // Start orchestrator
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
