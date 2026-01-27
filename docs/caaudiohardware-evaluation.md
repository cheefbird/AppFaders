# CAAudioHardware Evaluation

**Date:** January 20, 2026
**Subject:** Evaluation of `sbooth/CAAudioHardware` as a replacement for `SimplyCoreAudio`.

## Summary

`CAAudioHardware` is a robust, actively maintained Swift wrapper for the Core Audio HAL. It provides all the necessary primitives to replace `SimplyCoreAudio` in the `host-audio-orchestrator` spec, including device enumeration, notifications, and custom property I/O.

## Feature Mapping

| Requirement | SimplyCoreAudio | CAAudioHardware Implementation |
| :--- | :--- | :--- |
| **Enumerate Devices** | `simplyCA.allOutputDevices` | `AudioDevice.devices` (returns all, requires filtering) |
| **Find by UID** | `device.uid == "..."` | `AudioSystem.instance.deviceID(forUID:)` |
| **Notifications** | `NotificationCenter.default` | `AudioSystem.instance.whenSelectorChanges(.devices)` |
| **Custom Properties** | (Manual `AudioObjectGetPropertyData`) | `device.getProperty(PropertyAddress(...))` |
| **Concurrency** | Non-Sendable (Legacy) | `@unchecked Sendable` classes, callback-based events |

## Migration Strategy

### 1. Device Discovery

**SimplyCoreAudio:**

```swift
simplyCA.allOutputDevices.first { $0.uid == "..." }
```

**CAAudioHardware:**

```swift
if let id = try AudioSystem.instance.deviceID(forUID: "...") {
    let device = AudioDevice(id)
}
```

### 2. Notifications (AsyncStream Adapter)

`CAAudioHardware` uses closure callbacks. We can adapt this to `AsyncStream` easily:

```swift
var deviceListUpdates: AsyncStream<Void> {
    AsyncStream { continuation in
        let observer = try? AudioSystem.instance.whenSelectorChanges(.devices, on: .main) { _ in
            continuation.yield()
        }
        // Cleanup requires removing the listener
        continuation.onTermination = { _ in
            // AudioSystem.instance.whenSelectorChanges(.devices, perform: nil) // removes listener
        }
    }
}
```

### 3. Custom Properties (Volume Control)

`CAAudioHardware` shines here by providing type-safe property wrappers.

```swift
let selector = AudioObjectSelector<AudioDevice>(0x61667663) // 'afvc'
let address = PropertyAddress(PropertySelector(selector.rawValue), scope: .global)
try device.setProperty(address, to: volumeData)
```

## Recommendation

**Adopt CAAudioHardware.** It offers a cleaner, lower-level abstraction that fits our "driver-first" mental model better than `SimplyCoreAudio`, while still hiding the C pointer complexity. It is actively maintained and supports the exact feature set we need.
