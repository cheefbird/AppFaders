# AppFaders

[![Platform](https://img.shields.io/badge/platform-macOS%2026+-blue)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](LICENSE.md)

Per-application audio volume control for macOS via a custom HAL audio driver.

> **Status**: Phases 1-3 complete. Menu bar UI working. Next up: distribution packaging.

![AppFaders Desktop UI](/docs/desktop-ui.png)  
*UI is from development - Finder volume won't be included*

---

## Overview

AppFaders is a menu bar app that lets you control volume individually for each application. It works by installing a virtual audio device (HAL plug-in) that sits between apps and your output device.

```
┌─────────────────────┐                ┌─────────────────────┐
│                     │      XPC       │                     │
│   Host App          │◄──────────────►│   Helper Service    │
│   ─────────         │                │   ──────────────    │
│   • Menu Bar UI     │                │   • VolumeStore     │
│   • App monitoring  │                │   • XPC listener    │
│                     │                │                     │
└─────────────────────┘                └──────────┬──────────┘
                                                  │
                                                  │ XPC
                                                  ▼
                                       ┌─────────────────────┐
                                       │                     │
                                       │   HAL Driver        │
                                       │   ──────────        │
                                       │   • Virtual device  │
                                       │   • Passthrough     │
                                       │                     │
                                       └─────────────────────┘
```

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 26+ (Tahoe) |
| **Architecture** | Apple Silicon (arm64) |
| **Privileges** | Admin (for driver installation) |

---

## Quick Start

### Build & Test

```bash
swift build
swift test
```

### Run the App

```bash
swift build
swift run AppFaders
```

### Install Driver & Helper

> **Note**: Requires an Apple Developer account and valid signing certificate.

```bash
# Build, sign, and install
Scripts/install-driver.sh

# Uninstall
Scripts/uninstall-driver.sh
```

---

## Project Structure

| Target | Description |
|--------|-------------|
| `AppFaders` | SwiftUI menu bar app |
| `AppFadersCore` | Shared library (TrackedApp, DriverBridge, AppAudioMonitor) |
| `AppFadersHelper` | XPC service (LaunchDaemon) for volume state |
| `AppFadersDriver` | Swift HAL driver implementation |
| `AppFadersDriverBridge` | C interface for CoreAudio HAL |
| `BundleAssembler` | SPM plugin for .driver bundle packaging |

---

## Development Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | **driver-foundation** — Virtual device registration and passthrough | ✅ |
| 2 | **host-audio-orchestrator** — App monitoring + XPC IPC | ✅ |
| 3 | **desktop-ui** — Menu bar UI (NSPanel + SwiftUI) | ✅ |
| 4 | **system-delivery** — Signed PKG installer + notarization | 🔜 |
| 5 | **settings-and-hotkeys** — Launch at login + global hotkeys | ⏳ |
