# AppFaders Implementation Roadmap

This document outlines the sequential phases for building the AppFaders macOS application, as defined in the steering documents.

## Phase 1: `driver-foundation` ✓

**Goal**: Establish the monorepo and the virtual audio pipeline.

- **Project Setup**: Initialize the SPM Monorepo in the clean project directory.
- **Driver Core**: Implement custom C/Swift wrapper (`AppFadersDriverBridge`) to replace incompatible Pancake framework.
- **HAL Implementation**: Build the minimal Audio Server Plug-in that registers the "AppFaders Virtual Device."
- **Verification**: Device appears in System Settings and passes audio successfully.

## Phase 2: `host-audio-orchestrator` (in progress)

**Goal**: Build the "Brain" of the application (Host Logic).

- **Device Management**: Integrate **CAAudioHardware** for device discovery using `AsyncStream` and structured concurrency.
- **Process Monitoring**: Implement `AppAudioMonitor` to track running apps via `NSWorkspace` notifications.
- **IPC Bridge**: ⚠️ Custom AudioObject properties (`'afvc'`/`'afvq'`) blocked by `coreaudiod` with `kAudioHardwareUnknownPropertyError`. **Pivot to XPC** required for host-driver communication.
- **Verification**: Integration tests confirming successful XPC message delivery and volume state synchronization.

### IPC Findings (Task 17)

Attempted approach: Custom AudioObject properties registered via `kAudioObjectPropertyCustomPropertyInfoList`.

**Result**: FAILED. `coreaudiod` filters custom property writes before they reach the driver. The request never arrives - confirmed by absence of driver logs.

**Next step**: Implement XPC service embedded in driver bundle, or evaluate Mach ports as alternative.

## Phase 3: `swiftui-volume-mixer` (Spec 3)

**Goal**: Create the native macOS user interface.

- **Menu Bar Integration**: Build the Menu Bar Extra and the SwiftUI popover.
- **Dynamic Mixer**: Develop the app list with reactive sliders linked to the Audio Orchestrator.
- **Native Aesthetic**: Implement Light/Dark/Auto modes with a lightweight, translucent design.
- **Verification**: Smooth UI interactions and real-time volume synchronization.

## Phase 4: `system-delivery` (Spec 4)

**Goal**: Handle installation, permissions, and persistence.

- **Privileged Installer**: Implement logic to detect missing driver and prompt for administrative credentials to install the bundle to `/Library/Audio/Plug-Ins/HAL`.
- **Persistence**: Integrate `SMAppService` for modern "Launch at Login" support.
- **Global Hotkeys**: Implement configurable shortcuts for rapid access.
- **Verification**: Successful "First Run" experience and persistence across reboots.
