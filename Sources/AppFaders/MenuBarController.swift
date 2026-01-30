import AppKit
import os.log
import SwiftUI

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "MenuBarController")

@MainActor
final class MenuBarController: NSObject {
  private var statusItem: NSStatusItem?
  private var panel: NSPanel?
  private(set) var isPanelVisible = false

  override init() {
    super.init()
    setupStatusItem()
    setupPanel()
  }

  // MARK: - Panel Management

  func togglePanel() {
    if isPanelVisible {
      hidePanel()
    } else {
      showPanel()
    }
  }

  func showPanel() {
    guard let panel else { return }
    panel.makeKeyAndOrderFront(nil)
    isPanelVisible = true
    os_log(.debug, log: log, "Panel shown")
  }

  func hidePanel() {
    guard let panel else { return }
    panel.orderOut(nil)
    isPanelVisible = false
    os_log(.debug, log: log, "Panel hidden")
  }

  // MARK: - Panel Setup

  private func setupPanel() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
      styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden

    let hostingView = NSHostingView(rootView: PlaceholderPanelView())
    panel.contentView = hostingView

    self.panel = panel
    os_log(.info, log: log, "Panel created")
  }

  // MARK: - Status Item Setup

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    guard let button = statusItem?.button else {
      os_log(.error, log: log, "Failed to get status item button")
      return
    }

    // SF Symbol for menu bar icon
    if let image = NSImage(
      systemSymbolName: "slider.vertical.3",
      accessibilityDescription: "AppFaders"
    ) {
      image.isTemplate = true
      button.image = image
    } else {
      os_log(.error, log: log, "Failed to load SF Symbol 'slider.vertical.3'")
    }

    // Handle both left and right clicks
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    os_log(.info, log: log, "Menu bar controller initialized")
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp {
      showContextMenu(for: sender)
    } else {
      togglePanel()
    }
  }

  private func showContextMenu(for button: NSStatusBarButton) {
    let menu = NSMenu()

    let openItem = NSMenuItem(
      title: "Open",
      action: #selector(openMenuItemClicked),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(quitMenuItemClicked),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem?.menu = menu
    button.performClick(nil)
    statusItem?.menu = nil
  }

  @objc private func openMenuItemClicked() {
    showPanel()
  }

  @objc private func quitMenuItemClicked() {
    NSApp.terminate(nil)
  }
}
