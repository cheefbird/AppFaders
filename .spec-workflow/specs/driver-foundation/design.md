# Design Document: driver-foundation

## Overview

This design establishes the foundational architecture for AppFaders: an SPM-based monorepo containing a HAL AudioServerPlugIn that creates a virtual audio device. The driver intercepts system audio and passes it through to the default physical output.

This phase delivers:

- SPM monorepo structure with app and driver targets
- HAL plug-in that registers "AppFaders Virtual Device"
- Basic audio passthrough (no per-app control yet)

## Steering Document Alignment

### Technical Standards (tech.md)

- **Swift 6** with strict concurrency for all new code
- **SPM-first** build system (with build plugin for bundle assembly)
- **Custom HAL wrapper** - minimal Swift/C implementation (Pancake not SPM-compatible)
- **macOS 26+ / arm64 only** per updated requirements

### Project Structure (structure.md)

- Monorepo with separate targets: `AppFaders` (app) and `AppFadersDriver` (driver)
- Driver code isolated in `Sources/AppFadersDriver/`
- Swift files follow `PascalCase.swift` naming
- Max 400 lines per file, 40 lines per method

## Code Reuse Analysis

### Existing Components to Leverage

- **Custom HAL wrapper** (internal): Minimal Swift/C implementation wrapping AudioServerPlugIn C API - see `docs/pancake-compatibility.md` for decision rationale
- **BackgroundMusic** (reference): Open-source HAL driver for patterns and implementation guidance
- **CoreAudio/AudioToolbox** (system): Native frameworks for audio device interaction and format handling

### Integration Points

- **coreaudiod**: System audio daemon that loads our HAL plug-in from `/Library/Audio/Plug-Ins/HAL/`
- **System Settings**: Where our virtual device appears after registration

## Architecture

The driver operates as a HAL AudioServerPlugIn loaded by `coreaudiod`. It creates a virtual output device that captures audio and forwards it to the real output.

```sh
┌─────────────────────────────────────────────────────────────────────┐
│                           coreaudiod                                │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              AppFadersDriver.driver (HAL Plug-in)             │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌───────────────────────┐  │  │
│  │  │ PlugIn      │  │ VirtualDevice│  │ PassthroughEngine    │  │  │
│  │  │ (entry pt)  │──│ (AudioObject)│──│ (routes to output)   │  │  │
│  │  └─────────────┘  └─────────────┘  └───────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │  Physical Output      │
                    │  (speakers/headphones)│
                    └───────────────────────┘
```

### Modular Design Principles

- **Single File Responsibility**: Each Swift file handles one HAL object type
- **Component Isolation**: PlugIn, Device, Stream, and Passthrough are separate modules
- **Protocol-Driven**: Internal interfaces use Swift protocols for testability

## Components and Interfaces

### Component 1: DriverEntry (PlugIn Interface)

- **Purpose**: Entry point that `coreaudiod` calls to initialize the plug-in
- **Interfaces**:
  - `AudioServerPlugInDriverInterface` vtable (C function pointers in PlugInInterface.c)
  - Swift exports via @_cdecl: `AppFadersDriver_Initialize()`, `AppFadersDriver_CreateDevice()`, `AppFadersDriver_DestroyDevice()`
- **Dependencies**: AppFadersDriverBridge target, CoreAudio types
- **Files**: `Sources/AppFadersDriver/DriverEntry.swift`, `Sources/AppFadersDriverBridge/PlugInInterface.c`

### Component 2: VirtualDevice

- **Purpose**: Represents the "AppFaders Virtual Device" AudioObject with property handlers
- **Interfaces**:
  - Property handlers via @_cdecl: `HasProperty()`, `IsPropertySettable()`, `GetPropertyDataSize()`, `GetPropertyData()`
  - `ObjectID` enum for stable audio object identifiers (plugIn=1, device=2, outputStream=3)
- **Dependencies**: DriverEntry, CoreAudio types
- **File**: `Sources/AppFadersDriver/VirtualDevice.swift`

### Component 3: VirtualStream

- **Purpose**: Handles audio stream configuration (sample rate, format, channels)
- **Interfaces**:
  - `configure(format: AudioStreamBasicDescription)`
  - `startIO()` / `stopIO()`
- **Dependencies**: VirtualDevice, CoreAudio types
- **File**: `Sources/AppFadersDriver/VirtualStream.swift`

### Component 4: PassthroughEngine

- **Purpose**: Routes captured audio to the default physical output device
- **Interfaces**:
  - `start(inputDevice: AudioDeviceID)`
  - `stop()`
  - `processBuffer(_ buffer: AudioBuffer)` (real-time safe)
- **Dependencies**: CoreAudio, AudioToolbox
- **File**: `Sources/AppFadersDriver/PassthroughEngine.swift`

### Component 5: Build Plugin (BundleAssembler)

- **Purpose**: SPM build tool plugin that assembles the `.driver` bundle with correct structure and Info.plist
- **Interfaces**: SPM `BuildToolPlugin` protocol
- **Dependencies**: Foundation, PackagePlugin
- **File**: `Plugins/BundleAssembler/BundleAssembler.swift`

## Data Models

### AudioDeviceConfiguration

```swift
struct AudioDeviceConfiguration: Sendable {
    let name: String           // "AppFaders Virtual Device"
    let uid: String            // "com.fbreidenbach.appfaders.virtualdevice"
    let manufacturer: String   // "AppFaders"
    let sampleRates: [Double]  // [44100, 48000, 96000]
    let channelCount: UInt32   // 2 (stereo)
}
```

### StreamFormat

```swift
struct StreamFormat: Sendable {
    let sampleRate: Double
    let channelCount: UInt32
    let bitsPerChannel: UInt32
    let formatID: AudioFormatID  // kAudioFormatLinearPCM
}
```

## Bundle Structure

The driver must be packaged as a valid HAL plug-in bundle:

```sh
AppFadersDriver.driver/
├── Contents/
│   ├── Info.plist          # AudioServerPlugIn keys
│   ├── MacOS/
│   │   └── AppFadersDriver # Compiled binary
│   └── Resources/
│       └── (empty for now)
```

### Required Info.plist Keys

```xml
<key>CFBundleIdentifier</key>
<string>com.appfaders.driver</string>
<key>AudioServerPlugIn</key>
<dict>
    <key>DeviceUID</key>
    <string>com.appfaders.virtualdevice</string>
</dict>
```

## Build System Design

### Package.swift Structure

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "AppFaders",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AppFaders", targets: ["AppFaders"]),
        .library(name: "AppFadersDriver", type: .dynamic, targets: ["AppFadersDriver"]),
        .plugin(name: "BundleAssembler", targets: ["BundleAssembler"])
    ],
    dependencies: [
        // No external dependencies - using custom HAL wrapper
    ],
    targets: [
        .executableTarget(name: "AppFaders", dependencies: []),
        // C interface layer - SPM requires separate target for C code
        .target(
            name: "AppFadersDriverBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // Swift driver implementation
        .target(
            name: "AppFadersDriver",
            dependencies: ["AppFadersDriverBridge"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .plugin(
            name: "BundleAssembler",
            capability: .buildTool()
        ),
        .testTarget(name: "AppFadersDriverTests", dependencies: ["AppFadersDriver"])
    ]
)
```

### Build & Install Flow

1. `swift build` compiles the driver library
2. Build plugin assembles `.driver` bundle structure
3. Manual/scripted copy to `/Library/Audio/Plug-Ins/HAL/`
4. `sudo killall coreaudiod` to reload

## Error Handling

### Error Scenarios

1. **C/Swift interop issues in HAL wrapper**
   - **Handling**: Ensure @_cdecl exports match C header declarations exactly
   - **User Impact**: None (build-time issue)

2. **Driver fails to load in coreaudiod**
   - **Handling**: Log detailed diagnostics via `os_log` to Console.app
   - **User Impact**: Virtual device doesn't appear; user checks Console

3. **Default output device unavailable**
   - **Handling**: PassthroughEngine gracefully stops; resumes when device returns
   - **User Impact**: Silence until output device reconnects

4. **Audio format mismatch**
   - **Handling**: VirtualStream reports supported formats; rejects unsupported
   - **User Impact**: App may need to resample (handled by CoreAudio)

## Testing Strategy

### Unit Testing

- **VirtualDevice**: Test property getters/setters with mock AudioObjects
- **StreamFormat**: Test format validation and conversion
- **AudioDeviceConfiguration**: Test serialization and validation

### Integration Testing

- **Driver Loading**: Script that installs driver, restarts coreaudiod, verifies device appears
- **Audio Passthrough**: Play test tone through virtual device, verify output on physical device

### Manual Testing

- Install driver, select as output in System Settings
- Play audio from various apps (Music, Safari, etc.)
- Verify audio passes through without artifacts or noticeable latency
- Test hot-plugging headphones while audio plays

## File Summary

```sh
AppFaders/
├── Package.swift
├── Sources/
│   ├── AppFaders/
│   │   └── main.swift              # Placeholder app entry
│   ├── AppFadersDriverBridge/      # Separate C target (SPM requires this)
│   │   ├── include/
│   │   │   └── PlugInInterface.h   # C header for coreaudiod
│   │   └── PlugInInterface.c       # C entry point, COM vtable
│   └── AppFadersDriver/
│       ├── DriverEntry.swift       # HAL plug-in Swift implementation
│       ├── VirtualDevice.swift     # AudioObject device implementation
│       ├── VirtualStream.swift     # Stream configuration
│       ├── PassthroughEngine.swift # Audio routing to physical output
│       └── AudioTypes.swift        # Shared types and extensions
├── Plugins/
│   └── BundleAssembler/
│       └── BundleAssembler.swift   # Build plugin for .driver bundle
├── Tests/
│   └── AppFadersDriverTests/
│       └── VirtualDeviceTests.swift
└── Resources/
    └── Info.plist                  # Template for driver bundle
```
