# AppFaders

Per-application audio volume control for macOS via a custom HAL audio driver.

> **Status**: Early development — Phases 1-2 complete. XPC IPC working. Next up: SwiftUI menu bar UI.

## Overview

AppFaders is a menu bar app that lets you control volume individually for each application. It works by installing a virtual audio device (HAL plug-in) that sits between apps and your output device.

```mermaid
flowchart LR
    subgraph Host["Host App (SwiftUI)"]
        H1[Menu Bar UI]
        H2[App monitoring]
    end

    subgraph Helper["Helper Service"]
        S1[VolumeStore]
        S2[XPC listener]
    end

    subgraph Driver["HAL Driver"]
        D1[Virtual device]
        D2[Passthrough]
    end

    Host <-->|XPC| Helper
    Helper -->|XPC| Driver
```

## Requirements

- macOS 26+
- Apple Silicon (arm64)
- Admin privileges (for driver installation)

## Building

```bash
swift build
swift test
```

## Installing

```bash
# Build, sign, and install driver + helper service
Scripts/install-driver.sh

# Remove driver + helper
Scripts/uninstall-driver.sh
```

## Project Structure

| Target | Description |
|--------|-------------|
| `AppFaders` | SwiftUI menu bar app |
| `AppFadersHelper` | XPC service (LaunchDaemon) for volume state |
| `AppFadersDriver` | Swift HAL driver implementation |
| `AppFadersDriverBridge` | C interface for CoreAudio HAL |
| `BundleAssembler` | SPM plugin for .driver bundle packaging |

## Development Phases

1. ~~**driver-foundation**~~ — Virtual device registration and passthrough ✓
2. ~~**host-audio-orchestrator**~~ — App monitoring + XPC IPC ✓
3. **swiftui-volume-mixer** — Menu bar UI
4. **distribution-packaging** — Signed PKG installer + notarization
5. **settings-and-hotkeys** — Launch at login + global hotkeys

## License

[Apache 2.0](LICENSE)
