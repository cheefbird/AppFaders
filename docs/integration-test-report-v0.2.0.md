# Integration Test Report: IPC Volume Control (v0.2.0)

**Date:** January 25, 2026
**Tester:** Gemini CLI Agent
**Scope:** Verification of host-to-driver IPC for volume control (Task 17)

## Environment

- **OS:** macOS 15.2 (Darwin 24.2.0)
- **Project Version:** Phase 2 (Host Audio Orchestrator)
- **Driver Version:** 0.2.0 (Prototype)

## Test Procedure

### 1. Driver Installation

- **Command:** `Scripts/install-driver.sh`
- **Result:** [PASS] Driver built and registered successfully. Virtual Device visible in `system_profiler`.

### 2. Host Application Launch

- **Command:** `swift run AppFaders`
- **Result:** [PASS] Host app started and correctly resolved `AudioDeviceID` for the virtual device.

### 3. Volume Command Round-Trip

- **Action:** Programmatically set volume for `com.apple.Safari` to `0.5` using `AudioObjectSetPropertyData` with custom selector `'afvc'`.
- **Result:** [FAIL]
  - Status: `kAudioHardwareUnknownPropertyError` (2003332927)
  - Logs: `coreaudiod` did NOT forward the request to the driver's handlers.

## Findings & Critical Issues

1. **Custom Property Blockage:** Even with corrected `AudioServerPlugInCustomPropertyInfo` struct alignment (including `mName` and `mCategory`), `coreaudiod` continues to reject custom property writes with `kAudioHardwareUnknownPropertyError`.
2. **System Instability:** Attempting to register custom properties via the `kAudioObjectPropertyCustomPropertyInfoList` selector resulted in significant system-wide performance degradation and `coreaudiod` instability.
3. **Sandbox/Security Limits:** The failure likely stems from modern macOS security policies that restrict HAL drivers (running via `com.apple.audio.Core-Audio-Driver-Service.helper`) from exposing custom IPC interfaces through the standard `AudioObject` property system to external processes.

## Conclusion & Path Forward

The "AudioObject Properties" IPC mechanism is **not viable** for custom app-volume control in modern macOS HAL drivers. To salvage the project, we must pivot:

1. **Mandatory XPC:** Implement an XPC listener inside the HAL driver and have the Host App connect directly via XPC. This bypasses `coreaudiod` property filtering.
2. **Mach Ports:** Alternatively, use Mach message passing if XPC setup within the HAL bundle proves too restrictive.
3. **Abandon Custom Properties:** All code related to `'afvc'` and `'afvq'` should be removed from the driver's property handlers to maintain system stability.

## Status

**Overall Result:** FAILED (IPC Connectivity - Architectural Pivot Required)
