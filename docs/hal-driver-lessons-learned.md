# macOS HAL Audio Driver: Lessons Learned

Getting this to work, even as a POC was a pain, so I figured I should share what I found along the way. Written and researched by Opus, edited and verified by me. Best of luck!

A practical guide to implementing a HAL (Hardware Abstraction Layer) AudioServerPlugIn on macOS, based on building AppFaders. This document covers non-obvious requirements and gotchas discovered during development.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Critical Gotchas](#critical-gotchas)
3. [Build System Requirements](#build-system-requirements)
4. [Property System](#property-system)
5. [C/Swift Interop](#cswift-interop)
6. [Debugging Techniques](#debugging-techniques)
7. [Required Properties](#required-properties)
8. [Code Signing](#code-signing)
9. [Troubleshooting](#troubleshooting)
10. [Common Build Errors](#common-build-errors)
11. [Testing](#testing)
12. [References](#references)

---

## Architecture Overview

HAL drivers run in a separate helper process (`com.apple.audio.Core-Audio-Driver-Service.helper`), not in coreaudiod directly. This is the "remote plugin" architecture Apple uses for isolation.

```sh
coreaudiod
    │
    ▼ communicates via XPC
Core-Audio-Driver-Service.helper
    │
    ▼ loads your .driver bundle
Your HAL Plugin (CFPlugIn)
```

### Key Implications

- Your driver code executes in the helper process, not coreaudiod
- Property queries come through XPC, which adds error cases (the "who?" error)
- You can crash the helper without taking down coreaudiod (mostly)
- Logs appear under the helper process, not coreaudiod

> **Note:** This is the modern AudioServerPlugIn architecture (macOS 10.11+). Older drivers used a different in-process model. If you're reading pre-2015 sample code, the architecture may differ.

---

## Critical Gotchas

### 1. Binary Type: MH_BUNDLE vs MH_DYLIB

**This was the hardest issue to diagnose.** The driver would load, show up in coreaudiod logs, but none of our code would run.

**The Problem:** SPM builds dynamic libraries as `MH_DYLIB` (Mach-O shared library), but CFPlugIn requires `MH_BUNDLE` (Mach-O bundle).

**Symptom:** Driver appears to load in logs, but no os_log output from your code, and the device doesn't work.

**Diagnosis:**

```bash
# Check what other working drivers look like
file /Library/Audio/Plug-Ins/HAL/ZoomAudioDevice.driver/Contents/MacOS/ZoomAudioDevice
# Output: Mach-O 64-bit bundle arm64

# Check what you built
file .build/arm64-apple-macosx/debug/libAppFadersDriver.dylib
# Output: Mach-O 64-bit dynamically linked shared library arm64  <-- WRONG!
```

**Fix in Package.swift:**

```swift
.target(
  name: "AppFadersDriver",
  dependencies: ["AppFadersDriverBridge"],
  linkerSettings: [
    .linkedFramework("CoreAudio"),
    .linkedFramework("AudioToolbox"),
    // Build as MH_BUNDLE instead of MH_DYLIB for CFPlugIn compatibility
    .unsafeFlags(["-Xlinker", "-bundle"])
  ]
)
```

After the fix:

```bash
file .build/arm64-apple-macosx/debug/libAppFadersDriver.dylib
# Output: Mach-O 64-bit bundle arm64  <-- Correct!
```

### 2. Property Scope Handling

**The Problem:** `kAudioDevicePropertyStreams` must respect the `mScope` field. If you always return streams regardless of scope, the system gets confused.

**Symptom:** Device activates but doesn't appear in System Settings. You see "who?" errors in logs.

**Wrong:**

```swift
case kAudioDevicePropertyStreams:
  // Always returns stream - WRONG!
  var streamID = ObjectID.outputStream
  return (Data(bytes: &streamID, count: ...), ...)
```

**Correct:**

```swift
case kAudioDevicePropertyStreams:
  // Only return stream for output scope (we have no input streams)
  if address.mScope == kAudioObjectPropertyScopeOutput ||
     address.mScope == kAudioObjectPropertyScopeGlobal {
    var streamID = ObjectID.outputStream
    return (Data(bytes: &streamID, count: ...), ...)
  }
  return (Data(), 0)  // No input streams
```

### 3. Missing Required Properties

**The Problem:** The system queries properties you might not expect. Missing handlers cause "unknown property" errors that prevent device visibility.

**Critical properties often missed:**

- `kAudioDevicePropertyIsHidden` - Must return 0 (not hidden) or device won't show
- `kAudioDevicePropertyPreferredChannelsForStereo` - Must return `[1, 2]` for stereo
- `kAudioDevicePropertyZeroTimeStampPeriod` - Needed for IO timing
- `kAudioDevicePropertyClockDomain` - Clock synchronization

**Symptom:** `HALS_UCRemotePlugIn::ObjectGetPropertyData: failed: Error: 2003332927 ('who?')`

The error code `2003332927` is `kAudioHardwareUnknownPropertyError` (FourCC: 'who?').

### 4. CFString Property Return Format

> ⚠️ **This is one of the most common HAL driver bugs.** Getting CFString handling wrong produces subtle failures—the property appears to work but returns garbage to the system.

**The Problem:** CoreAudio expects CFString properties as raw pointers, not serialized bytes.

**Wrong:**

```swift
case kAudioObjectPropertyName:
  let nameData = (name as String).data(using: .utf8)!
  return (nameData, ...)  // WRONG - serialized bytes
```

**Correct:**

```swift
private func cfStringPropertyData(_ string: CFString) -> (Data, UInt32) {
  var ptr = Unmanaged.passUnretained(string).toOpaque()
  return (Data(bytes: &ptr, count: MemoryLayout<UnsafeRawPointer>.size),
          UInt32(MemoryLayout<UnsafeRawPointer>.size))
}

case kAudioObjectPropertyName:
  return cfStringPropertyData(name)  // Correct - raw pointer
```

---

## Build System Requirements

### SPM Structure for HAL Drivers

The driver needs two targets: a C interface layer and Swift implementation.

```swift
// Package.swift structure
targets: [
  // C interface layer for HAL AudioServerPlugIn
  .target(
    name: "AppFadersDriverBridge",
    publicHeadersPath: "include",
    cSettings: [.headerSearchPath("include")],
    linkerSettings: [
      .linkedFramework("CoreAudio"),
      .linkedFramework("CoreFoundation")
    ]
  ),
  // Swift implementation
  .target(
    name: "AppFadersDriver",
    dependencies: ["AppFadersDriverBridge"],
    linkerSettings: [
      .linkedFramework("CoreAudio"),
      .linkedFramework("AudioToolbox"),
      .unsafeFlags(["-Xlinker", "-bundle"])  // CRITICAL!
    ]
  )
]
```

### Bundle Assembly

HAL drivers must be `.driver` bundles with this structure:

```sh
AppFadersDriver.driver/
  Contents/
    Info.plist
    MacOS/
      AppFadersDriver  (the MH_BUNDLE binary)
```

We use an SPM build plugin to assemble this structure. See `Plugins/BundleAssembler/`.

### Info.plist Requirements

The minimal CFPlugIn keys required:

```xml
<key>CFPlugInFactories</key>
<dict>
  <!-- Your unique factory UUID -->
  <key>8CDE7F8F-4676-47A8-8DCD-2D68746C3291</key>
  <!-- Must match your C factory function name exactly -->
  <string>AppFadersDriver_Create</string>
</dict>
<key>CFPlugInTypes</key>
<dict>
  <!-- kAudioServerPlugInTypeUUID - DO NOT CHANGE THIS -->
  <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
  <array>
    <!-- Your factory UUID from above -->
    <string>8CDE7F8F-4676-47A8-8DCD-2D68746C3291</string>
  </array>
</dict>
```

> **Note:** A complete Info.plist also needs standard bundle keys (`CFBundleIdentifier`, `CFBundleExecutable`, `CFBundlePackageType` = `"BNDL"`, etc.) and optionally an `AudioServerPlugIn` dict with `DeviceUID`. See the actual `Resources/Info.plist` in this project for a complete example.

---

## Property System

### Object Hierarchy

```sh
Plugin (ObjectID 1)
  └── Device (ObjectID 2)
        └── Stream (ObjectID 3)
```

Each property query includes:

- `objectID` - which object (plugin, device, or stream)
- `selector` - which property (FourCC code)
- `scope` - output/input/global
- `element` - usually 0 (`kAudioObjectPropertyElementMain`; macOS 11+ deprecated `kAudioObjectPropertyElementMaster` which was the same value)

### Property Implementation Pattern

Every AudioObject needs these four methods:

1. `HasProperty` - Does this object support this property?
2. `IsPropertySettable` - Can this property be changed?
3. `GetPropertyDataSize` - How many bytes will the value be?
4. `GetPropertyData` - Return the actual value

```swift
func hasProperty(address: AudioObjectPropertyAddress) -> Bool {
  switch address.mSelector {
  case kAudioObjectPropertyClass,
       kAudioObjectPropertyName,
       kAudioDevicePropertyStreams,
       // ... list ALL supported properties
       kAudioDevicePropertyIsHidden:
    return true
  default:
    return false
  }
}
```

### Missing Constants in Swift

Some HAL constants aren't bridged to Swift. Define them manually:

```swift
private let kAudioPlugInPropertyResourceBundle =
  AudioObjectPropertySelector(fourCharCode("rsrc"))
private let kAudioDevicePropertyZeroTimeStampPeriod =
  AudioObjectPropertySelector(fourCharCode("ring"))

private func fourCharCode(_ string: String) -> UInt32 {
  var result: UInt32 = 0
  for char in string.utf8.prefix(4) {
    result = (result << 8) | UInt32(char)
  }
  return result
}
```

---

## C/Swift Interop

### COM-Style Interface

CoreAudio uses COM-style interfaces. Your C layer must provide:

- `QueryInterface` - Return interface pointers
- `AddRef` / `Release` - Reference counting
- All the AudioServerPlugInDriverInterface methods

```c
static AudioServerPlugInDriverInterface gDriverInterface = {
  ._reserved = NULL,
  .QueryInterface = PlugIn_QueryInterface,
  .AddRef = PlugIn_AddRef,
  .Release = PlugIn_Release,
  .Initialize = PlugIn_Initialize,
  // ... all other methods
};
```

### Bridging to Swift

Use `@_cdecl` to export Swift functions with C linkage:

```swift
// In Swift
@_cdecl("AppFadersDriver_Initialize")
public func driverInitialize(host: AudioServerPlugInHostRef) -> OSStatus {
  DriverEntry.shared.initialize(host: host)
}

// In C header
extern OSStatus AppFadersDriver_Initialize(AudioServerPlugInHostRef inHost);
```

### Thread Safety

Driver code can be called from any thread. Use locks for mutable state:

```swift
final class VirtualDevice: @unchecked Sendable {
  private let lock = NSLock()
  private var sampleRate: Float64 = 48000.0

  func getSampleRate() -> Float64 {
    lock.lock()
    defer { lock.unlock() }
    return sampleRate
  }
}
```

---

## Debugging Techniques

### Enable Debug Logging

```bash
# Enable verbose HAL logging
sudo log config --subsystem com.apple.audio.HAL --mode level:debug

# Or for your driver specifically
sudo log config --subsystem com.fbreidenbach.appfaders.driver --mode level:debug
```

### Watch Logs

```bash
# Real-time logs from the driver helper
log stream --predicate 'subsystem == "com.fbreidenbach.appfaders.driver"' --level debug

# Or watch everything audio-related
log stream --predicate 'subsystem CONTAINS "audio"' --level debug
```

### Restart coreaudiod

After installing a new driver version:

```bash
sudo killall coreaudiod
# Wait 2-3 seconds for it to restart automatically
```

> `killall` sends SIGTERM (graceful shutdown). You can also use `killall -9` (SIGKILL) for immediate termination. Either way, launchd automatically restarts the daemon.

### Verify Device Registration

```bash
# Check if device appears
system_profiler SPAudioDataType | grep -A5 "AppFaders"
```

### Decode Error Codes

Common error codes:

- `2003332927` = `'who?'` = `kAudioHardwareUnknownPropertyError`
- `560947818` = `'!obj'` = `kAudioHardwareBadObjectError`
- `1970171760` = `'unop'` = `kAudioHardwareUnsupportedOperationError`

Convert codes:

```swift
func fourCharCodeToString(_ code: UInt32) -> String {
  let chars: [Character] = [
    Character(UnicodeScalar((code >> 24) & 0xFF)!),
    Character(UnicodeScalar((code >> 16) & 0xFF)!),
    Character(UnicodeScalar((code >> 8) & 0xFF)!),
    Character(UnicodeScalar(code & 0xFF)!)
  ]
  return String(chars)
}
```

---

## Required Properties

### Plugin Properties

| Property | Return Value |
|----------|--------------|
| `kAudioObjectPropertyClass` | `kAudioPlugInClassID` |
| `kAudioObjectPropertyBaseClass` | `kAudioObjectClassID` |
| `kAudioObjectPropertyOwner` | `kAudioObjectSystemObject` |
| `kAudioObjectPropertyManufacturer` | Your manufacturer CFString |
| `kAudioPlugInPropertyDeviceList` | Array of device IDs |
| `kAudioPlugInPropertyResourceBundle` | Empty string or bundle path |

### Device Properties

| Property | Return Value | Notes |
|----------|--------------|-------|
| `kAudioObjectPropertyClass` | `kAudioDeviceClassID` | |
| `kAudioObjectPropertyName` | Device name CFString | What users see |
| `kAudioDevicePropertyDeviceUID` | Unique identifier | Stable across reboots |
| `kAudioDevicePropertyTransportType` | `kAudioDeviceTransportTypeVirtual` | For virtual devices |
| `kAudioDevicePropertyStreams` | Array of stream IDs | **Respect scope!** |
| `kAudioDevicePropertyIsHidden` | 0 | **Must be 0 to appear** |
| `kAudioDevicePropertyPreferredChannelsForStereo` | `[1, 2]` | Left/right channels |
| `kAudioDevicePropertyCanBeDefaultDevice` | 1 | To appear in Sound prefs |
| `kAudioDevicePropertyNominalSampleRate` | Current rate (Float64) | |
| `kAudioDevicePropertyAvailableNominalSampleRates` | Array of AudioValueRange | |
| `kAudioDevicePropertyZeroTimeStampPeriod` | Sample rate as UInt32 | For IO timing |
| `kAudioDevicePropertyClockDomain` | 0 | Default clock domain |

### Stream Properties

| Property | Return Value | Notes |
|----------|--------------|-------|
| `kAudioObjectPropertyClass` | `kAudioStreamClassID` | |
| `kAudioStreamPropertyDirection` | 0 for output, 1 for input | Per `AudioHardwareBase.h` |
| `kAudioStreamPropertyPhysicalFormat` | AudioStreamBasicDescription | Current format |
| `kAudioStreamPropertyAvailablePhysicalFormats` | Array of AudioStreamRangedDescription | |
| `kAudioStreamPropertyIsActive` | 1 when IO running, 0 otherwise | |

---

## Code Signing

Drivers installed in `/Library/Audio/Plug-Ins/HAL/` must be code signed:

```bash
# Sign with Developer ID (for distribution)
codesign --force --sign "Developer ID Application: Your Name" \
  --timestamp \
  AppFadersDriver.driver

# Or for development, ad-hoc signing works
codesign --force --sign - AppFadersDriver.driver
```

Verify:

```bash
codesign -dv --verbose=4 AppFadersDriver.driver
```

### Production Requirements

For distributing outside the App Store:

1. **Developer ID certificate** - Ad-hoc signing only works for local development
2. **Notarization** - Required for apps distributed outside the App Store on macOS 10.15+. Submit your driver to Apple's notary service via `xcrun notarytool`
3. **Hardened Runtime** - May be required depending on your distribution method

> **Note:** Newer macOS versions have stricter security. An unsigned driver may work during development but fail silently on users' machines with tightened Gatekeeper settings.

---

## Troubleshooting

When your driver loads but the device doesn't appear, work through this checklist:

```
Driver loads but device doesn't show up?
│
├─ Check logs for 'who?' errors (kAudioHardwareUnknownPropertyError)
│  └─ YES → Missing required property. See Required Properties tables above.
│
├─ Check kAudioDevicePropertyIsHidden returns 0
│  └─ Returns non-zero or not implemented → Device is hidden from users
│
├─ Check kAudioDevicePropertyStreams respects mScope
│  └─ Returns streams for wrong scope → System gets confused about device capabilities
│
├─ Check binary type with `file YourDriver.driver/Contents/MacOS/YourDriver`
│  └─ Says "dynamically linked shared library" → Need MH_BUNDLE, add `-Xlinker -bundle`
│
├─ Check Info.plist factory function name
│  └─ Doesn't match your @_cdecl function name exactly → CFPlugIn can't find entry point
│
└─ Check logs for any initialization errors
   └─ Look for os_log output from your Initialize function
```

### Quick Diagnosis Commands

```bash
# Is the driver binary the right type?
file /Library/Audio/Plug-Ins/HAL/YourDriver.driver/Contents/MacOS/YourDriver

# Does the device appear to the system?
system_profiler SPAudioDataType | grep -A5 "YourDeviceName"

# Watch for errors in real-time
log stream --predicate 'subsystem CONTAINS "audio"' --level debug

# Check coreaudiod's view of plugins
sudo launchctl list | grep coreaudio
```

---

## Common Build Errors

### SPM Linker Issues

**Error:** "Undefined symbols" or linking failures with CoreAudio types.

**Fix:** Ensure your target has the right linker settings:

```swift
linkerSettings: [
  .linkedFramework("CoreAudio"),
  .linkedFramework("CoreFoundation"),
  .unsafeFlags(["-Xlinker", "-bundle"])  // CRITICAL for HAL drivers
]
```

### Missing HAL Constants in Swift

**Error:** "Cannot find 'kAudioPlugInPropertyResourceBundle' in scope"

**Fix:** Some HAL constants aren't bridged to Swift. Define them manually using FourCC:

```swift
private let kAudioPlugInPropertyResourceBundle =
  AudioObjectPropertySelector(0x72737263) // 'rsrc'
```

### Factory Function Not Found

**Error:** Driver loads but none of your code runs. No os_log output.

**Causes:**

1. Factory function name in Info.plist doesn't match your `@_cdecl` function name
2. Binary is MH_DYLIB instead of MH_BUNDLE
3. Factory function isn't validating the UUID correctly

**Diagnosis:** Add os_log at the very start of your factory function. If you don't see it, the function isn't being called at all.

### Code Signing Errors During Install

**Error:** "code signature invalid" or similar when copying to `/Library/Audio/Plug-Ins/HAL/`

**Fix:** Sign the entire `.driver` bundle after building:

```bash
codesign --force --sign - YourDriver.driver  # ad-hoc for development
```

---

## Testing

### What You Can Unit Test

HAL drivers are tricky to test because CFPlugIn loading can't be easily mocked. However, you can unit test:

- **Property data formatting** - Test that your `getPropertyData` methods return correctly formatted data
- **Audio buffer helpers** - Ring buffer implementations, format conversions
- **State management** - Lock correctness, state transitions

Example from AppFaders:

```swift
func testStreamFormatHasCorrectSize() {
  let format = VirtualStream.shared.currentFormat()
  XCTAssertEqual(format.mBytesPerFrame, 8)  // 2ch * 4 bytes
  XCTAssertEqual(format.mChannelsPerFrame, 2)
}
```

### Manual Integration Testing

After building and signing:

1. **Install** - Copy to `/Library/Audio/Plug-Ins/HAL/`
2. **Restart coreaudiod** - `sudo killall coreaudiod`
3. **Verify registration** - `system_profiler SPAudioDataType | grep -A5 "YourDevice"`
4. **Check logs** - `log stream --predicate 'subsystem == "your.subsystem"' --level debug`
5. **Test audio flow** - Route audio to the device and verify behavior

### Automated Integration Testing

For CI, you can script the verification:

```bash
#!/bin/bash
Scripts/install-driver.sh
sleep 3
system_profiler SPAudioDataType | grep -q "AppFaders Virtual Output" || exit 1
echo "Driver registered successfully"
```

---

## References

### Apple Documentation

- [Audio Server Plug-Ins](https://developer.apple.com/documentation/coreaudio/audio_server_plug-in) - Official (sparse) docs
- `AudioServerPlugIn.h` - The authoritative reference (in CoreAudio framework)

### Open Source Examples

- [libASPL](https://github.com/gavv/libaspl) - **Recommended.** Production-ready C++17 library for HAL drivers. Excellent documentation and actively maintained. Even if you don't use C++, the architecture and patterns are worth studying.
- [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) - Complete reference implementation. Uses older Objective-C++ approach but covers all the bases.

### Community Resources

- [Creating an Audio Server Driver Plug-In](https://developer.apple.com/library/archive/samplecode/AudioDriverExamples/) - Apple sample (archived but useful)

---

## Summary Checklist

Before your driver will work:

- [ ] Binary is MH_BUNDLE type (use `-Xlinker -bundle` in SPM)
- [ ] Info.plist has correct `CFPlugInFactories` and `CFPlugInTypes`
- [ ] Factory function name matches Info.plist exactly
- [ ] Factory function validates `kAudioServerPlugInTypeUUID`
- [ ] All required properties implemented for plugin, device, and stream
- [ ] `kAudioDevicePropertyIsHidden` returns 0
- [ ] `kAudioDevicePropertyStreams` respects scope
- [ ] CFString properties returned as raw pointers, not serialized bytes
- [ ] Driver is code signed
- [ ] Installed to `/Library/Audio/Plug-Ins/HAL/`
- [ ] coreaudiod restarted after installation
