# AppFaders Implementation Roadmap

This document outlines the sequential phases for building the AppFaders macOS application, as defined in the steering documents.

## Phase 1: `driver-foundation` ✓

**Goal**: Establish the monorepo and the virtual audio pipeline.

- **Project Setup**: Initialize the SPM Monorepo in the clean project directory.
- **Driver Core**: Implement custom C/Swift wrapper (`AppFadersDriverBridge`) to replace incompatible Pancake framework.
- **HAL Implementation**: Build the minimal Audio Server Plug-in that registers the "AppFaders Virtual Device."
- **Verification**: Device appears in System Settings and passes audio successfully.

## Phase 2: `host-audio-orchestrator` ✓

**Goal**: Build the "Brain" of the application (Host Logic).

- **Device Management**: Integrated **CAAudioHardware** for device discovery using `AsyncStream` and structured concurrency.
- **Process Monitoring**: Implemented `AppAudioMonitor` to track running apps via `NSWorkspace` notifications.
- **XPC IPC**: Helper service (`AppFadersHelper`) runs as LaunchDaemon, exposing Mach service for host app and driver. Dual protocols enforce read-write (host) vs read-only (driver) access.
- **Driver Caching**: `HelperBridge` maintains local volume cache for real-time safe audio callbacks.
- **Verification**: Manual integration test confirmed XPC round-trip and volume state sync. See `Docs/xpc-integration-test.md`.

## Phase 3: `swiftui-volume-mixer`

**Goal**: Create the native macOS user interface.

- **Menu Bar Integration**: Build the Menu Bar Extra and the SwiftUI popover.
- **Dynamic Mixer**: Develop the app list with reactive sliders linked to the Audio Orchestrator via XPC.
- **Native Aesthetic**: Implement Light/Dark/Auto modes with a lightweight, translucent design.
- **Verification**: Smooth UI interactions and real-time volume synchronization.

## Phase 4: `distribution-packaging`

**Goal**: Package for end-user distribution.

- **Signed PKG Installer**: Build installer using `pkgbuild`/`productbuild` that installs driver to `/Library/Audio/Plug-Ins/HAL` and helper to `/Library/LaunchDaemons/`.
- **Notarization**: Script notarization workflow via `notarytool` for Gatekeeper approval.
- **Uninstaller**: Optional script/tool to cleanly remove driver, helper, and LaunchDaemon.
- **Verification**: Fresh macOS install can download PKG, install without Gatekeeper warnings, and run app successfully.

## Phase 5: `settings-and-hotkeys`

**Goal**: Polish features for power users.

- **Launch at Login**: Integrate `SMAppService` for modern login item support.
- **Global Hotkeys**: Configurable keyboard shortcuts for rapid volume access.
- **Settings UI**: Preferences panel for hotkey configuration and other options.
- **Verification**: Settings persist across app restarts, hotkeys work system-wide.
