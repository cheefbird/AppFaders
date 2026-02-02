# Future Integration Test Recommendations

## Current State

As of Phase 3 (desktop-ui) completion, the following components have unit test coverage:

| Component | Coverage | Notes |
|-----------|----------|-------|
| `AppVolumeState` | ✓ | Struct, no dependencies |
| `TrackedApp` | ✓ | Struct, equality/hashing |
| `AppAudioMonitor` | ✓ | Initial enumeration, stream mechanics, concurrency |
| `DriverBridge` | ✓ | Validation (volume range, bundle ID length, connection state) |
| `AppState` class | ✗ | Requires real AudioOrchestrator + DeviceManager |
| UI Views | ✗ | SwiftUI previews serve as visual tests |

## Testing Gap: AppState Class

The `AppState` class contains business logic that should be tested but currently isn't due to hard dependencies on:

1. **AudioOrchestrator** - requires XPC connection to helper service
2. **DeviceManager** - requires real audio hardware (CAAudioHardware)

### Untested Methods

```swift
// Per-app volume control
func setVolume(for bundleID: String, volume: Float) async
func toggleMute(for bundleID: String) async

// Master volume control
func setMasterVolume(_ volume: Float)
func toggleMasterMute()

// State sync
func syncFromOrchestrator()
func refreshMasterVolume()
```

### Testable Logic Within These Methods

1. **Volume clamping** - `max(0.0, min(1.0, volume))` ensures 0-1 range
2. **Auto-unmute on volume change** - setting volume > 0 while muted should unmute
3. **Mute toggle state machine** - stores previousVolume, restores on unmute
4. **Sync preserves mute state** - existing muted apps stay muted after sync

## Recommended Approach: Protocol-Based Dependencies

### Step 1: Define Protocols

```swift
// AudioOrchestratorProtocol.swift
@MainActor
protocol AudioOrchestratorProtocol {
    var trackedApps: [TrackedApp] { get }
    var appVolumes: [String: Float] { get }
    var isDriverConnected: Bool { get }
    func setVolume(for bundleID: String, volume: Float) async
}

// DeviceManagerProtocol.swift
protocol DeviceManagerProtocol {
    func getSystemVolume() -> Float
    func setSystemVolume(_ volume: Float)
    func getSystemMute() -> Bool
    func setSystemMute(_ muted: Bool)
}
```

### Step 2: Create Mock Implementations

```swift
// MockAudioOrchestrator.swift (in Tests/)
@MainActor
final class MockAudioOrchestrator: AudioOrchestratorProtocol {
    var trackedApps: [TrackedApp] = []
    var appVolumes: [String: Float] = [:]
    var isDriverConnected: Bool = true

    var setVolumeCalls: [(bundleID: String, volume: Float)] = []

    func setVolume(for bundleID: String, volume: Float) async {
        setVolumeCalls.append((bundleID, volume))
        appVolumes[bundleID] = volume
    }
}

// MockDeviceManager.swift (in Tests/)
final class MockDeviceManager: DeviceManagerProtocol {
    var systemVolume: Float = 1.0
    var systemMuted: Bool = false

    func getSystemVolume() -> Float { systemVolume }
    func setSystemVolume(_ volume: Float) { systemVolume = volume }
    func getSystemMute() -> Bool { systemMuted }
    func setSystemMute(_ muted: Bool) { systemMuted = muted }
}
```

### Step 3: Update AppState Init

```swift
// Allow protocol-based injection
init(orchestrator: any AudioOrchestratorProtocol, deviceManager: any DeviceManagerProtocol) {
    self.orchestrator = orchestrator
    self.deviceManager = deviceManager
    // ...
}
```

## Priority Test Cases

### High Priority

1. **Volume clamping**
   - `setVolume(volume: -0.5)` → clamped to 0.0
   - `setVolume(volume: 1.5)` → clamped to 1.0
   - `setMasterVolume(-0.5)` → clamped to 0.0

2. **Mute toggle state machine**
   - Mute stores previousVolume, sets volume to 0
   - Unmute restores previousVolume
   - Mute → change previousVolume externally → unmute restores correct value

3. **Auto-unmute on volume change**
   - App is muted, `setVolume(volume: 0.5)` → unmutes and sets volume
   - Master is muted, `setMasterVolume(0.5)` → unmutes and sets volume

### Medium Priority

1. **syncFromOrchestrator preserves mute state**
   - Muted app stays muted after sync
   - Volume shows 0 for muted apps even if orchestrator has different value

2. **Connection error state**
   - `isDriverConnected = false` → `connectionError` is set
   - `isDriverConnected = true` → `connectionError` is nil

### Lower Priority

1. **refreshMasterVolume reads from device manager**
2. **setVolume for non-existent bundleID is no-op**
3. **toggleMute for non-existent bundleID is no-op**

## Integration Test Considerations

For full end-to-end testing with real XPC and audio hardware:

1. **Requires helper service running** - use `Scripts/install-driver.sh` first
2. **Requires audio device** - may need to mock or use virtual device
3. **Consider CI environment** - GitHub Actions runners may not have audio hardware

### Suggested Integration Test Setup

```swift
@Suite("AppState Integration", .disabled("Requires helper service"))
struct AppStateIntegrationTests {
    @Test func realVolumeChangeReflectsInHelper() async {
        // Only run when helper is available
        // ...
    }
}
```

## Implementation Timeline

| Phase | Scope | Effort |
|-------|-------|--------|
| Phase 4 (system-delivery) | Consider adding protocols during installer work | Low |
| Post-MVP | Full protocol extraction + mock tests | Medium |
| CI Enhancement | Integration tests with helper service | High |

## References

- BackgroundMusic uses similar architecture with HAL driver + helper
- Apple's XPC testing documentation recommends mock services for unit tests
- Swift Testing framework supports `.disabled()` trait for conditional tests
