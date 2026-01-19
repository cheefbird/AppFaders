# AppFaders

Per-application audio volume control for macOS via a custom HAL audio driver.

> **Status**: Early development — Phase 1 (driver foundation) complete, Phase 2 (host audio orchestrator) in progress.

## Overview

AppFaders is a menu bar app that lets you control volume individually for each application. It works by installing a virtual audio device (HAL plug-in) that sits between apps and your output device.

```sh
┌─────────────────────┐                    ┌────────────────────┐
│  Host App (SwiftUI) │◄──────────────────►│  HAL Driver        │
│  - Menu Bar UI      │   AudioObject IPC  │  - Virtual device  │
│  - App monitoring   │                    │  - Passthrough     │
└─────────────────────┘                    └────────────────────┘
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

## Installing the Driver

```bash
# Build, sign, and install to /Library/Audio/Plug-Ins/HAL
Scripts/install-driver.sh

# Remove the driver
Scripts/uninstall-driver.sh
```

## Project Structure

| Target | Description |
|--------|-------------|
| `AppFaders` | SwiftUI menu bar app |
| `AppFadersDriver` | Swift HAL driver implementation |
| `AppFadersDriverBridge` | C interface for CoreAudio HAL |
| `BundleAssembler` | SPM plugin for .driver bundle packaging |

## Development Phases

1. ~~**driver-foundation**~~ — Virtual device registration and passthrough ✓
2. **host-audio-orchestrator** — App monitoring + IPC *(in progress)*
3. **swiftui-volume-mixer** — Menu bar UI
4. **system-delivery** — Installer + launch at login

## License

[Apache 2.0](LICENSE)
