# Product Overview

## Product Purpose

A native macOS application that provides granular control over audio volume on a per-application basis, allowing users to balance sound levels across different software (e.g., turning down browser volume during a Zoom call without affecting the call's audio).

## Target Users

- **Office Workers**: Keeping notification sounds low while listening to focus music or in meetings.
- **Casual Users**: Managing multiple audio sources without changing system-wide volume.

## Key Features

1. **Per-App Volume Sliders**: Individual volume control for open applications that could produce audio.
2. **Global Mute/Unmute**: Quick toggle for all applications or specific ones.
3. **Menu Bar Integration**: Quick access to volume controls via a sleek macOS menu bar icon.
4. **Global Hotkeys**: Configurable keyboard shortcuts to quickly open the controller or adjust specific volumes.

## Project Objectives

- **Quality**: A seamless, stable, and native-feeling utility for macOS.
- **Performance**: Extremely lightweight footprint with minimal impact on system resources.
- **Ease-of-Use**: Intuitive design with zero learning curve.

## Success Metrics

- **Performance**: Minimal CPU and memory overhead during active audio management.
- **Responsiveness**: Near-instant UI updates and volume changes.
- **Stability**: Robust integration with the macOS audio engine.

## Product Principles

1. **Native Experience**: Look and feel like a first-party macOS utility.
2. **Performance First**: Minimal impact on system resources and audio latency.
3. **Intuitive Design**: Zero-learning curve for basic volume management. Design should be lightweight and include dark, light, and auto (system) modes.

## Monitoring & Visibility

- **Dashboard Type**: macOS Menu Bar Extra and a main settings window.
- **Real-time Updates**: Reflecting application volume changes and detecting new audio sources using macOS AudioToolbox/CoreAudio notifications.
- **Key Metrics Displayed**: Current volume levels and active/open applications.

## Future Vision

### Potential Enhancements

- **Profiles**: Saved volume presets for different workflows (e.g., "Work", "Gaming").
- **Audio Routing**: Ability to select output devices per application.
- **Audio Equalization**: Per-app EQ settings for fine-tuned audio control.
