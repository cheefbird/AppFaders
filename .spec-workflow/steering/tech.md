# Technology Stack

## Project Type

Native macOS Desktop Application (Menu Bar Extra) utilizing a User-Space Audio Driver (HAL Plug-in) for per-application audio management.

## Core Technologies

### Primary Language(s)

- **Swift 6.2**: The primary language for the application UI, business logic, and host-side audio management.
- **C/C++**: Minimal usage reserved for the low-level Audio Server Plug-in (HAL driver) boilerplate, integrated via Swift Package Manager.
- **Runtime/Compiler**: Xcode 16+ / LLVM.
- **Language-specific tools**: Swift Package Manager (SPM) for all dependency management and build orchestration.

### Key Dependencies/Libraries

- **SwiftUI**: Modern UI framework using the `Observation` framework for reactive state management.
- **SimplyCoreAudio**: A Swift package for high-level management of CoreAudio devices, simplifying device discovery and volume control.
- **Custom C/Swift HAL Wrapper**: Minimal C interface (`AppFadersDriverBridge`) with Swift implementation (`AppFadersDriver`). Pancake was evaluated but found incompatible with Swift 6 strict concurrency — see `docs/pancake-compatibility.md`.
- **CoreAudio / AudioToolbox**: Native system frameworks for low-level audio device interaction.
- **ServiceManagement**: For implementing "Launch at Login" using the modern `SMAppService` Swift API. *(Phase 3+)*
- **Swift Concurrency / Synchronization**: Lock-free atomics for real-time audio buffer management.

### Application Architecture

- **Host Application (Swift)**:
  - **UI Layer**: A sleek, translucent menu bar interface built with SwiftUI.
  - **Logic Layer**: Monitors running applications and their audio state.
  - **Communication Layer**: Communicates per-app volume settings to the virtual driver using custom properties on the `AudioObject`.
- **Virtual Audio Driver (HAL Plug-in)**:
  - A user-space `AudioServerPlugIn` (HAL) component built as two SPM targets:
    - **AppFadersDriverBridge** (C): COM-style vtable implementing `AudioServerPlugInDriverInterface`, factory function for CFPlugIn loading.
    - **AppFadersDriver** (Swift): Core logic with `@_cdecl` exports called by the C layer. Includes `DriverEntry`, `VirtualDevice`, `VirtualStream`, `PassthroughEngine`.
  - **Build requirement**: Must produce `MH_BUNDLE` binary (not `MH_DYLIB`) via `-Xlinker -bundle` flag.
  - **Audio flow**: Lock-free ring buffer (`AudioRingBuffer`) routes captured audio to default physical output.
  - **Role**: Intercepts system audio and applies process-specific gain adjustments before passing audio to the physical output.
- **Inter-Process Communication (IPC)**:
  - Will use `AudioObjectSetPropertyData` and `AudioObjectGetPropertyData` for low-latency communication between the Swift host and the driver.

### Data Storage

- **Primary storage**: `UserDefaults` (via `@AppStorage`) for persisting user preferences like hotkeys, default volumes, and login settings.
- **State management**: Swift's `@Observable` macro for real-time UI synchronization with the audio engine state.

### External Integrations

- **macOS Audio Server (coreaudiod)**: The application acts as a controller for the system's audio subsystem.

## Development Environment

### Build & Development Tools

- **Build System**: Xcode Build System with integrated Swift Package Manager.
- **Package Management**: 100% Swift Package Manager (SPM). No external package managers (Homebrew/CocoaPods) required for the core build.
- **Development workflow**: Local testing using `Audio Hijack` or `BlackHole` for loopback verification during development.

### Code Quality Tools

- **Static Analysis**: SwiftLint (via SPM plugin).
- **Formatting**: SwiftFormat (via SPM plugin).
- **Testing Framework**: Swift Testing (new in Swift 6) for modern, macro-based unit tests.

## Deployment & Distribution

- **Target Platform**: macOS 26+ (arm64 only, no backward compatibility, no Universal Binary).
- **Distribution Method**: Notarized App Bundle (DMG/PKG) for direct distribution.
- **Security**: Requires `com.apple.audio.AudioServerPlugIn` sandbox entitlement and `admin` privileges for initial driver installation.

## Technical Requirements & Constraints

### Performance Requirements

- **Audio Latency**: Must maintain < 5ms processing latency to avoid perceptible delay in audio playback.
- **CPU Usage**: The host app must remain < 1% CPU usage when idle; the driver must have negligible overhead.

### Compatibility Requirements

- **Hardware**: Apple Silicon only (arm64, no Universal Binary).
- **OS**: macOS 26+ required for latest Swift 6 and SwiftUI features.

## Technical Decisions & Rationale

### Decision Log

1. **Swift 6 and Swift Testing**: Adopted to ensure the project uses the most modern and safe concurrency models from the start.
2. **SimplyCoreAudio for Device Management**: Chosen to replace boilerplate C-based CoreAudio calls with idiomatic Swift code. *(Phase 2)*
3. **Custom HAL Wrapper over Pancake**: Pancake was evaluated in Phase 1 but found incompatible with Swift 6 strict concurrency. Built minimal C interface (`AppFadersDriverBridge`) with Swift implementation instead. Decision documented in `docs/pancake-compatibility.md`.
4. **Two-Target Driver Architecture**: Separating C vtable (`AppFadersDriverBridge`) from Swift logic (`AppFadersDriver`) enables clean @_cdecl bridging and maintains SPM compatibility.
5. **MH_BUNDLE Binary Type**: CFPlugIn requires bundle format, not dylib. Discovered this was the root cause of driver not executing despite loading. Fixed via `-Xlinker -bundle` in Package.swift.
6. **Lock-Free Ring Buffer**: Real-time audio callback requires no allocations or locks. Implemented `AudioRingBuffer` using Swift's `Synchronization.Atomic` for thread-safe operation.
7. **SPM Build Plugin for Bundle Assembly**: Created `BundleAssembler` plugin to construct `.driver` bundle structure from SPM build artifacts.
8. **Modern SMAppService**: Replaces the deprecated `SMLoginItemSetEnabled` for a more robust "Launch at Login" experience.

## Known Limitations

- **Driver Installation**: Requires a one-time administrative authorization to install the HAL plug-in into `/Library/Audio/Plug-Ins/HAL`.
- **Sandboxed Apps**: Intercepting audio from certain highly sandboxed System Apps may require specific TCC permissions from the user.
