# Requirements Document: driver-foundation

## Introduction

This spec establishes the foundational layer for AppFaders: a Swift Package Manager monorepo and a minimal HAL (Hardware Abstraction Layer) audio plug-in that registers a virtual audio device with macOS. This phase focuses purely on infrastructure—getting the project structure right and proving the virtual device can be loaded by `coreaudiod`.

No UI, no per-app volume control, no IPC—just a passthrough virtual audio device that appears in System Settings and successfully routes audio.

## Alignment with Product Vision

Per `product.md`, AppFaders requires a virtual audio device to intercept and modify per-application audio streams. This spec delivers the essential plumbing:

- **Native Experience**: Using SPM and Swift 6 ensures modern, maintainable code from day one
- **Performance First**: A minimal passthrough driver establishes the foundation for future optimization
- The virtual device is the prerequisite for all future audio manipulation features

## Technical Approach

### Why HAL AudioServerPlugIn (not AudioDriverKit)

Apple's AudioDriverKit framework does **not** support virtual audio devices. Per Apple's guidance, AudioDriverKit is only for hardware-backed drivers. For virtual audio devices (like ours), the HAL AudioServerPlugIn model remains the required approach.

This means:
- We must use the traditional `/Library/Audio/Plug-Ins/HAL/` installation path
- Driver installation requires `coreaudiod` restart (no hot-reload)
- We'll use the Pancake framework to wrap the C-based HAL API in Swift

### macOS 26+ and Apple Silicon Only

Targeting only macOS 26 and arm64 enables:
- **Single architecture build** — no Universal Binary complexity
- **Latest Swift 6 concurrency** — no runtime availability checks needed
- **Latest SwiftUI** — no `@available` guards throughout the codebase
- **Simplified testing** — one architecture to validate
- **Modern dependencies** — can require latest versions without backwards compat concerns

## Requirements

### Requirement 1: SPM Monorepo Initialization

**User Story:** As a developer, I want a properly structured Swift Package Manager monorepo, so that all targets (app and driver) can be built and tested with standard Swift tooling.

#### Acceptance Criteria

1. WHEN `swift build` is run in the project root THEN the build system SHALL compile all targets without errors
2. WHEN `swift test` is run THEN the test runner SHALL execute tests for all testable targets
3. IF the project is opened in Xcode THEN Xcode SHALL recognize the SPM structure and provide full IDE support
4. WHEN a new dependency is added to `Package.swift` THEN SPM SHALL resolve and fetch it automatically

### Requirement 2: HAL Driver Framework Integration

**User Story:** As a developer, I want a Swift-friendly HAL framework integrated, so that I can write plug-in logic in Swift instead of raw C/C++.

#### Acceptance Criteria

1. WHEN `Package.swift` is resolved THEN the HAL framework dependency SHALL be fetched
2. IF Pancake is used AND it doesn't build with Swift 6 THEN we SHALL either fork/patch it or implement a minimal Swift wrapper directly
3. WHEN the driver target imports the HAL framework THEN the AudioServerPlugIn APIs SHALL be accessible from Swift code

### Requirement 3: Virtual Audio Device Registration

**User Story:** As a user, I want a virtual audio device called "AppFaders Virtual Device" to appear in my system, so that I can select it as an audio output.

#### Acceptance Criteria

1. WHEN the HAL plug-in bundle is installed to `/Library/Audio/Plug-Ins/HAL/` AND `coreaudiod` is restarted THEN the virtual device SHALL appear in System Settings → Sound → Output
2. WHEN the virtual device is selected as output THEN audio from any application SHALL play through it without audible artifacts
3. IF the driver encounters an initialization error THEN it SHALL log diagnostic information to the system console
4. WHEN the driver bundle is removed from the HAL directory AND `coreaudiod` is restarted THEN the virtual device SHALL no longer appear

### Requirement 4: Audio Passthrough

**User Story:** As a user, I want audio routed through the virtual device to be forwarded to my default physical output, so that I can hear sound while using the virtual device.

#### Acceptance Criteria

1. WHEN audio is played to the virtual device THEN the driver SHALL forward it to the default physical output device
2. WHEN passthrough occurs THEN the audio latency SHALL be reasonable (no noticeable delay in normal use)
3. IF the default physical output changes THEN the driver SHALL continue routing to the new default device
4. WHEN multiple applications play audio simultaneously THEN the driver SHALL mix them correctly before passthrough

### Requirement 5: Driver Bundle Structure

**User Story:** As a developer, I want the driver to compile into a valid `.driver` bundle, so that macOS recognizes it as a HAL plug-in.

#### Acceptance Criteria

1. WHEN `swift build` completes THEN a `AppFadersDriver.driver` bundle SHALL be produced
2. WHEN the bundle's `Info.plist` is inspected THEN it SHALL contain the required `AudioServerPlugIn` keys
3. IF the bundle structure is invalid THEN `coreaudiod` SHALL reject it with a logged error (testable during development)

## Non-Functional Requirements

### Code Architecture and Modularity

- **Single Responsibility**: The driver target contains only HAL plug-in code; no UI or host logic
- **Modular Design**: Driver components (device, stream, controls) are separate Swift files
- **Clear Interfaces**: Public driver API (if any) is defined via Swift protocols
- **SPM Target Isolation**: `AppFaders` (app) and `AppFadersDriver` are separate targets with explicit dependencies

### Performance

- Audio passthrough should work without noticeable delay or artifacts
- Specific latency and CPU targets deferred to later optimization phases

### Security

- No unnecessary entitlements beyond `com.apple.audio.AudioServerPlugIn`
- Installation requires explicit admin authorization (expected for `/Library/` writes)
- Code-signing and notarization deferred to Phase 4 (system-delivery)

### Reliability

- Driver must handle `coreaudiod` restarts gracefully
- No crashes or hangs during audio format changes
- Graceful degradation if physical output device is unavailable

### Compatibility

- macOS 26+ only
- Apple Silicon only (arm64)
- Swift 6 with strict concurrency checking enabled
