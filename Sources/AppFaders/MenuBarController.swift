import AppKit
import os.log

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "MenuBarController")

@MainActor
final class MenuBarController: NSObject {
  private var statusItem: NSStatusItem?

  override init() {
    super.init()
    setupStatusItem()
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    guard let button = statusItem?.button else {
      os_log(.error, log: log, "Failed to get status item button")
      return
    }

    // SF Symbol for menu bar icon
    if let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "AppFaders") {
      image.isTemplate = true
      button.image = image
    }

    os_log(.info, log: log, "Menu bar controller initialized")
  }
}
