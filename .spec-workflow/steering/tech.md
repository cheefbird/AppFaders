# Technology Stack

## Project Type
Native macOS Desktop Application (Menu Bar Extra) utilizing a User-Space Audio Driver (HAL Plug-in) for per-application audio management.

## Core Technologies

### Primary Language(s)
- **Swift 6.0**: The primary language for the application UI, business logic, and host-side audio management.
- **C/C++**: Minimal usage reserved for the low-level Audio Server Plug-in (HAL driver) boilerplate, integrated via Swift Package Manager.
- **Runtime/Compiler**: Xcode 16+ / LLVM.
- **Language-specific tools**: Swift Package Manager (SPM) for all dependency management and build orchestration.

### Key Dependencies/Libraries
- **SwiftUI**: Modern UI framework using the `Observation` framework for reactive state management.
- **SimplyCoreAudio**: A Swift package for high-level management of CoreAudio devices, simplifying device discovery and volume control.
- **Pancake**: A community-maintained Swift framework that wraps the C-based `AudioServerPlugIn` API, enabling the development of HAL plugins in Swift.
- **CoreAudio / AudioToolbox**: Native system frameworks for low-level audio device interaction.
- **ServiceManagement**: For implementing "Launch at Login" using the modern `SMAppService` Swift API.
- **Combine / Swift Concurrency**: For handling asynchronous audio notifications and inter-process communication.

### Application Architecture
- **Host Application (Swift)**:
    - **UI Layer**: A sleek, translucent menu bar interface built with SwiftUI.
    - **Logic Layer**: Monitors running applications and their audio state.
    - **Communication Layer**: Communicates per-app volume settings to the virtual driver using custom properties on the `AudioObject`.
- **Virtual Audio Driver (HAL Plug-in)**:
    - A user-space `AudioServerPlugIn` (HAL) component.
    - **Implementation**: We will utilize the **Pancake** framework to write the driver logic in Swift.
    - **Fallback**: If deep system integration requires it, a minimal C++ shim will be used to interface directly with the `AudioServerPlugIn` C API, keeping the core logic in Swift.
    - **Role**: Intercepts system audio and applies process-specific gain adjustments before passing audio to the physical output.
- **Inter-Process Communication (IPC)**:
    - Uses `AudioObjectSetPropertyData` and `AudioObjectGetPropertyData` for low-latency communication between the Swift host and the driver.

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
- **Target Platform**: macOS 14.0+ (Sonoma and later) to leverage the latest Swift and SwiftUI features.
- **Distribution Method**: Notarized App Bundle (DMG/PKG) for direct distribution.
- **Security**: Requires `com.apple.audio.AudioServerPlugIn` sandbox entitlement and `admin` privileges for initial driver installation.

## Technical Requirements & Constraints

### Performance Requirements
- **Audio Latency**: Must maintain < 5ms processing latency to avoid perceptible delay in audio playback.
- **CPU Usage**: The host app must remain < 1% CPU usage when idle; the driver must have negligible overhead.

### Compatibility Requirements  
- **Hardware**: Native support for Apple Silicon (Universal Binary).
- **OS**: macOS 14.0+ required for modern Swift Concurrency and SwiftUI features.

## Technical Decisions & Rationale

### Decision Log
1. **Swift 6 and Swift Testing**: Adopted to ensure the project uses the most modern and safe concurrency models from the start.
2. **SimplyCoreAudio for Device Management**: Chosen to replace boilerplate C-based CoreAudio calls with idiomatic Swift code.
3. **HAL Plug-in via SPM**: While HAL drivers are traditionally C++, we wrap the driver logic in a way that allows it to be managed as a target within the Swift Package, keeping the build process unified.
4. **Modern SMAppService**: Replaces the deprecated `SMLoginItemSetEnabled` for a more robust "Launch at Login" experience.
5. **Starting Fresh**: To ensure a clean, modern architecture, the existing Xcode boilerplate in the `AppFaders` directory will be removed. The project will be initialized from scratch using a Swift 6 and Swift Package Manager (SPM) structure, avoiding legacy `.xcodeproj` clutter.

## Known Limitations
- **Driver Installation**: Requires a one-time administrative authorization to install the HAL plug-in into `/Library/Audio/Plug-Ins/HAL`.
- **Sandboxed Apps**: Intercepting audio from certain highly sandboxed System Apps may require specific TCC permissions from the user.