# Design Document: host-audio-orchestrator

## Overview

This design establishes the host-side orchestration layer for AppFaders: the Swift code that connects the virtual audio driver to running applications. The orchestrator discovers our virtual device via SimplyCoreAudio, monitors running processes via NSWorkspace, and sends volume commands via custom AudioObject properties.

This phase delivers:

- SimplyCoreAudio integration for device discovery and notifications
- AppAudioMonitor for tracking audio-capable applications
- IPC bridge using custom driver properties for volume commands
- Observable state ready for Phase 3 UI binding

## Steering Document Alignment

### Technical Standards (tech.md)

- **Swift 6** with strict concurrency and `@Observable` for state management
- **SimplyCoreAudio** (v4.1.1) as specified dependency for device management
- **AudioObject properties** for IPC — standard HAL pattern, low-latency
- **macOS 26+ / arm64 only** per platform requirements
- **os_log** for diagnostics with subsystem `com.fbreidenbach.appfaders`

### Project Structure (structure.md)

- Host logic in `Sources/AppFaders/` target per monorepo structure
- Driver modifications minimal — add to existing `VirtualDevice.swift` and `AudioTypes.swift`
- New files follow `PascalCase.swift` naming
- Max 400 lines per file, 40 lines per method
- Import order: System frameworks → SimplyCoreAudio → Internal modules

## Code Reuse Analysis

### Existing Components to Leverage

- **VirtualDevice.swift**: Already handles property queries via `hasProperty`, `getPropertyData`, `setPropertyData` — extend for custom IPC properties
- **ObjectID enum**: Stable IDs (plugIn=1, device=2, outputStream=3) — add custom property selectors
- **AudioTypes.swift**: Configuration structs — add `AppFadersProperty` enum and `VolumeCommand` struct
- **fourCharCode helper**: Already in VirtualDevice.swift for property selectors
- **os_log infrastructure**: Subsystem `com.fbreidenbach.appfaders.driver` — reuse pattern for host

### Integration Points

- **SimplyCoreAudio**: New dependency — provides `allOutputDevices`, device UID lookup, NotificationCenter-based change notifications
- **NSWorkspace**: System API for `runningApplications` and launch/terminate notifications
- **coreaudiod**: Property get/set calls flow through system daemon to driver

## Architecture

The host orchestrator sits between the future UI layer and the driver, managing state and communication.

```mermaid
graph TD
    subgraph Host["AppFaders Host (Swift)"]
        AO[AudioOrchestrator<br/>@Observable]
        AAM[AppAudioMonitor<br/>NSWorkspace]
        DM[DeviceManager<br/>SimplyCoreAudio]
        DB[DriverBridge<br/>AudioObject props]
    end

    subgraph Driver["AppFadersDriver (HAL)"]
        VD[VirtualDevice]
        VS[VolumeStore]
        PE[PassthroughEngine]
    end

    AAM --> AO
    DM --> AO
    DB --> AO
    AO --> UI[Phase 3 UI]
    DB -->|AudioObjectSetPropertyData| coreaudiod
    coreaudiod --> VD
    VD --> VS
    VS --> PE
```

### Modular Design Principles

- **Single File Responsibility**: Each Swift file handles one concern (monitoring, device mgmt, IPC)
- **Component Isolation**: Components communicate via protocols for testability
- **Service Layer Separation**: DeviceManager handles CoreAudio, AppAudioMonitor handles NSWorkspace
- **Utility Modularity**: Shared types in AudioTypes.swift, errors in dedicated file

## Components and Interfaces

### Component 1: AudioOrchestrator

- **Purpose**: Central coordinator and state container for the orchestration layer
- **Interfaces**:
  ```swift
  @Observable
  final class AudioOrchestrator {
      private(set) var trackedApps: [TrackedApp]
      private(set) var isDriverConnected: Bool
      private(set) var appVolumes: [String: Float]  // bundleID -> volume

      func setVolume(for bundleID: String, volume: Float) throws
      func start() async
      func stop()
  }
  ```
- **Dependencies**: AppAudioMonitor, DeviceManager, DriverBridge
- **Reuses**: None (new component)

### Component 2: AppAudioMonitor

- **Purpose**: Track running applications that may produce audio via NSWorkspace
- **Interfaces**:
  ```swift
  protocol AppAudioMonitorDelegate: AnyObject {
      func monitor(_ monitor: AppAudioMonitor, didLaunch app: TrackedApp)
      func monitor(_ monitor: AppAudioMonitor, didTerminate bundleID: String)
  }

  final class AppAudioMonitor {
      weak var delegate: AppAudioMonitorDelegate?
      var runningApps: [TrackedApp] { get }

      func start()
      func stop()
  }
  ```
- **Dependencies**: NSWorkspace, AppKit (for NSRunningApplication, NSImage)
- **Reuses**: None (new component)

### Component 3: DeviceManager

- **Purpose**: Wrapper around SimplyCoreAudio for device discovery and notifications
- **Interfaces**:
  ```swift
  final class DeviceManager {
      var allOutputDevices: [AudioDevice] { get }
      var appFadersDevice: AudioDevice? { get }

      func startObserving()
      func stopObserving()

      var onDeviceListChanged: (() -> Void)?
  }
  ```
- **Dependencies**: SimplyCoreAudio (v4.1.1)
- **Reuses**: None (new component)

### Component 4: DriverBridge

- **Purpose**: Communicate with the virtual driver via custom AudioObject properties
- **Interfaces**:
  ```swift
  final class DriverBridge {
      var isConnected: Bool { get }

      func connect(deviceID: AudioDeviceID) throws
      func disconnect()

      func setAppVolume(bundleID: String, volume: Float) throws
      func getAppVolume(bundleID: String) throws -> Float
  }
  ```
- **Dependencies**: CoreAudio (AudioObjectSetPropertyData, AudioObjectGetPropertyData)
- **Reuses**: AppFadersProperty selectors from AudioTypes.swift

### Component 5: VolumeStore (Driver-side)

- **Purpose**: Store per-app volume settings in the driver for real-time gain application
- **Interfaces**:
  ```swift
  final class VolumeStore: @unchecked Sendable {
      static let shared = VolumeStore()

      func setVolume(for bundleID: String, volume: Float)  // clamps to 0.0-1.0
      func getVolume(for bundleID: String) -> Float  // default 1.0
      func removeVolume(for bundleID: String)
  }
  ```
- **Dependencies**: Foundation (NSLock for thread safety)
- **Reuses**: Lock pattern from VirtualDevice.shared
- **Note**: VolumeStore clamps out-of-range values as a defensive measure; primary validation occurs in DriverBridge on the host side

## Data Models

### TrackedApp

```swift
struct TrackedApp: Identifiable, Sendable, Hashable {
    let id: String           // bundle ID (also serves as Identifiable id)
    let bundleID: String
    let localizedName: String
    let icon: NSImage?       // app icon for future UI
    let launchDate: Date
}
```

### VolumeCommand

```swift
// Wire format for IPC property data
struct VolumeCommand {
    static let maxBundleIDLength = 255

    var bundleIDLength: UInt8      // actual length of bundle ID
    var bundleIDBytes: (UInt8, ...)  // fixed 255 bytes, null-padded
    var volume: Float32            // 0.0 to 1.0

    // Total size: 1 + 255 + 4 = 260 bytes
}
```

### AppFadersProperty (Custom Selectors)

```swift
// Add to AudioTypes.swift
enum AppFadersProperty {
    // Four-char codes: 'afXX' (0x6166XXXX)
    static let setVolume = AudioObjectPropertySelector(0x61667663)   // 'afvc'
    static let getVolume = AudioObjectPropertySelector(0x61667671)   // 'afvq'
}
```

## Error Handling

### Error Scenarios

1. **Virtual device not found**
   - **Handling**: DeviceManager returns nil for appFadersDevice; DriverBridge.connect() throws DriverError.deviceNotFound
   - **User Impact**: App shows "Driver not installed" state; functionality degraded

2. **Property write fails (OSStatus != noErr)**
   - **Handling**: DriverBridge logs error, throws DriverError.propertyWriteFailed(status)
   - **User Impact**: Volume change doesn't take effect; error surfaced to orchestrator

3. **coreaudiod restart during operation**
   - **Handling**: SimplyCoreAudio posts `.deviceListChanged` notification; DeviceManager re-discovers devices; DriverBridge reconnects
   - **User Impact**: Brief disconnection, automatic recovery

4. **Invalid volume value**
   - **Handling**: DriverBridge validates 0.0-1.0 range before sending; throws DriverError.invalidVolumeRange
   - **User Impact**: None (validation prevents bad data)

### Error Types

```swift
enum DriverError: Error, LocalizedError {
    case deviceNotFound
    case propertyReadFailed(OSStatus)
    case propertyWriteFailed(OSStatus)
    case invalidVolumeRange(Float)
    case bundleIDTooLong(Int)

    var errorDescription: String? { ... }
}
```

## Testing Strategy

### Unit Testing

- **AppAudioMonitor**: Inject mock NotificationCenter; verify app tracking on launch/terminate notifications
- **DriverBridge**: Mock AudioObjectSetPropertyData/GetPropertyData; verify VolumeCommand serialization
- **VolumeStore**: Test concurrent setVolume/getVolume; verify default 1.0 for unknown bundleIDs
- **AudioOrchestrator**: Mock all dependencies; verify state transitions and error propagation

### Integration Testing

- **Device discovery**: With installed driver, verify SimplyCoreAudio finds device by UID `com.fbreidenbach.appfaders.virtualdevice`
- **Property round-trip**: Host sets volume, reads back from driver, verifies match
- **Notification flow**: Simulate device removal/addition, verify DeviceManager callbacks

### End-to-End Testing

- Install driver via Scripts/install-driver.sh
- Launch host app, verify driver connection
- Launch various apps (Safari, Music), verify AppAudioMonitor detects them
- Set volume for an app, verify driver logs receipt (via Console.app)

## SimplyCoreAudio Integration Details

### Package.swift Changes

```swift
dependencies: [
    .package(url: "https://github.com/rnine/SimplyCoreAudio.git", from: "4.1.0")
],
targets: [
    .executableTarget(
        name: "AppFaders",
        dependencies: [
            .product(name: "SimplyCoreAudio", package: "SimplyCoreAudio")
        ]
    ),
    // ... existing targets unchanged
]
```

### Device Discovery Pattern

```swift
import SimplyCoreAudio

final class DeviceManager {
    private let simplyCA = SimplyCoreAudio()
    private var notificationObservers: [NSObjectProtocol] = []

    var appFadersDevice: AudioDevice? {
        simplyCA.allOutputDevices.first { device in
            device.uid == "com.fbreidenbach.appfaders.virtualdevice"
        }
    }

    func startObserving() {
        let observer = NotificationCenter.default.addObserver(
            forName: .deviceListChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onDeviceListChanged?()
        }
        notificationObservers.append(observer)
    }
}
```

## File Summary

```
AppFaders/
├── Package.swift                      # Add SimplyCoreAudio 4.1.0+ dependency
├── Sources/
│   ├── AppFaders/
│   │   ├── main.swift                 # Update: initialize orchestrator
│   │   ├── AudioOrchestrator.swift    # NEW: central state coordinator
│   │   ├── AppAudioMonitor.swift      # NEW: NSWorkspace app tracking
│   │   ├── DeviceManager.swift        # NEW: SimplyCoreAudio wrapper
│   │   ├── DriverBridge.swift         # NEW: IPC via AudioObject properties
│   │   ├── DriverError.swift          # NEW: error types
│   │   └── TrackedApp.swift           # NEW: app model
│   └── AppFadersDriver/
│       ├── AudioTypes.swift           # UPDATE: add AppFadersProperty enum
│       ├── VirtualDevice.swift        # UPDATE: custom property handlers
│       └── VolumeStore.swift          # NEW: per-app volume storage
└── Tests/
    ├── AppFadersTests/                # NEW: test target
    │   ├── AppAudioMonitorTests.swift
    │   ├── DriverBridgeTests.swift
    │   └── VolumeStoreTests.swift
    └── AppFadersDriverTests/          # Existing
```
