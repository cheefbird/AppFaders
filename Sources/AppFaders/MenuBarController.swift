import AppKit
import os.log
import SwiftUI

private let log = OSLog(subsystem: "com.fbreidenbach.appfaders", category: "MenuBarController")

@MainActor
final class MenuBarController: NSObject {
  private var statusItem: NSStatusItem?
  private var panel: NSPanel?
  private(set) var isPanelVisible = false

  private var clickOutsideMonitor: Any?
  private var escapeKeyMonitor: Any?

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

    positionPanelBelowStatusItem()
    panel.makeKeyAndOrderFront(nil)
    isPanelVisible = true
    addEventMonitors()
    os_log(.debug, log: log, "Panel shown")
  }

  func hidePanel() {
    guard let panel else { return }

    removeEventMonitors()
    panel.orderOut(nil)
    isPanelVisible = false
    os_log(.debug, log: log, "Panel hidden")
  }

  // MARK: - Panel Positioning

  private func positionPanelBelowStatusItem() {
    guard let panel,
          let button = statusItem?.button,
          let buttonWindow = button.window
    else { return }

    let buttonFrame = buttonWindow.frame
    let panelSize = panel.frame.size

    // Center panel horizontally below the status item button
    let panelX = buttonFrame.midX - (panelSize.width / 2)
    // Position panel just below the menu bar
    let panelY = buttonFrame.minY - panelSize.height

    // Ensure panel stays on screen
    if let screen = buttonWindow.screen {
      let screenFrame = screen.visibleFrame
      let adjustedX = max(screenFrame.minX, min(panelX, screenFrame.maxX - panelSize.width))
      panel.setFrameOrigin(NSPoint(x: adjustedX, y: panelY))
    } else {
      panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
    }
  }

  // MARK: - Event Monitors

  private func addEventMonitors() {
    // Click outside to dismiss
    clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
      [weak self] event in
      guard let self else { return }
      Task { @MainActor in
        self.handleClickOutside(event)
      }
    }

    // Escape key to dismiss
    escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self else { return event }
      if event.keyCode == 53 {  // Escape key
        Task { @MainActor in
          self.hidePanel()
        }
        return nil  // Consume the event
      }
      return event
    }
  }

  private func removeEventMonitors() {
    if let monitor = clickOutsideMonitor {
      NSEvent.removeMonitor(monitor)
      clickOutsideMonitor = nil
    }
    if let monitor = escapeKeyMonitor {
      NSEvent.removeMonitor(monitor)
      escapeKeyMonitor = nil
    }
  }

  private func handleClickOutside(_ event: NSEvent) {
    guard let panel, isPanelVisible else { return }

    // For global events, locationInWindow is screen coordinates
    let clickLocation = event.locationInWindow

    // Ignore clicks on the status item - let togglePanel handle those
    if let button = statusItem?.button,
       let buttonWindow = button.window {
      let buttonFrame = buttonWindow.frame
      if buttonFrame.contains(clickLocation) {
        return
      }
    }

    // Check if click is outside the panel
    let panelFrame = panel.frame
    if !panelFrame.contains(clickLocation) {
      hidePanel()
    }
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
