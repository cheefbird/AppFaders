# Requirements Document: host-audio-orchestrator

## Introduction

This spec builds the "brain" of AppFaders: the host-side logic that connects the virtual audio driver to running applications. Phase 2 establishes device management via SimplyCoreAudio, process monitoring to track audio-capable apps, and an IPC bridge using custom AudioObject properties to send volume commands from the host to the driver.

No UI in this phase—just the orchestration layer that future UI will consume.

## Alignment with Product Vision

Per `product.md`, AppFaders provides per-application volume control. This spec delivers the essential host logic:

- **Per-App Volume Sliders**: Requires knowing which apps are running and can produce audio (AppAudioMonitor)
- **Native Experience**: SimplyCoreAudio provides idiomatic Swift APIs over raw CoreAudio
- **Performance First**: IPC via AudioObject properties is the standard low-latency mechanism for HAL communication
- The orchestrator is the prerequisite for the SwiftUI mixer in Phase 3

## Technical Approach

### Why SimplyCoreAudio

SimplyCoreAudio wraps CoreAudio's verbose C APIs with Swift-native patterns:

- Device enumeration with type filtering (input/output/aggregate)
- Default device get/set operations
- Property change notifications via Combine/NotificationCenter
- Eliminates hundreds of lines of AudioObject boilerplate

The framework is mature (5+ years) and actively maintained. It targets macOS 10.12+ and Swift 4.0+, well within our macOS 26+ / Swift 6 requirements.

### Why AudioObject Properties for IPC

The HAL plug-in model supports custom properties on AudioObjects. This is the established pattern for host ↔ driver communication:

- **Low latency**: Property reads/writes go directly through coreaudiod
- **No external IPC overhead**: No XPC, no Mach ports, no sockets to manage
- **Atomic operations**: CoreAudio handles synchronization
- **Discoverable**: Standard `kAudioObjectPropertyCustomPropertyInfoList` mechanism

Phase 1 driver already stubs `kAudioObjectPropertyCustomPropertyInfoList`—we'll extend it to expose volume control properties.

### Process Monitoring via NSWorkspace

macOS provides `NSWorkspace.runningApplications` and notifications for app launch/termination. This is the standard approach for tracking running processes without elevated privileges:

- `NSWorkspaceDidLaunchApplicationNotification` for new apps
- `NSWorkspaceDidTerminateApplicationNotification` for closed apps
- Bundle ID provides stable app identification

Audio session detection (knowing which apps *can* produce audio vs which *are* producing audio) requires additional heuristics or AudioToolbox queries—this spec focuses on process awareness first.

## Requirements

### Requirement 1: SimplyCoreAudio Integration

**User Story:** As a developer, I want SimplyCoreAudio integrated as an SPM dependency, so that I can manage audio devices with idiomatic Swift code.

#### Acceptance Criteria

1. WHEN `swift build` is run THEN SimplyCoreAudio SHALL compile without errors alongside existing targets
2. WHEN the host app initializes THEN it SHALL enumerate available audio devices using SimplyCoreAudio
3. WHEN the default output device changes THEN the host SHALL receive a notification via SimplyCoreAudio's observer mechanism
4. IF SimplyCoreAudio fails to initialize THEN the host SHALL log an error and continue with degraded functionality

### Requirement 2: AppFaders Virtual Device Discovery

**User Story:** As a developer, I want the host to locate the AppFaders Virtual Device, so that it can communicate with our driver.

#### Acceptance Criteria

1. WHEN the host starts THEN it SHALL search for a device with UID matching our driver's published UID
2. WHEN the virtual device is found THEN the host SHALL store a reference (AudioDeviceID) for IPC operations
3. IF the virtual device is not installed THEN the host SHALL log a warning and indicate driver-not-found state
4. WHEN the virtual device appears or disappears (coreaudiod restart) THEN the host SHALL update its reference accordingly

### Requirement 3: Process Monitoring (AppAudioMonitor)

**User Story:** As a user, I want the app to know which applications are running, so that I can see them in the volume mixer.

#### Acceptance Criteria

1. WHEN the host starts THEN it SHALL enumerate currently running applications
2. WHEN a new application launches THEN AppAudioMonitor SHALL add it to the tracked list within 1 second
3. WHEN an application terminates THEN AppAudioMonitor SHALL remove it from the tracked list within 1 second
4. WHEN an application is tracked THEN its bundle ID, localized name, and icon SHALL be available
5. IF an application has no bundle ID (command-line tool) THEN it SHALL be excluded from tracking

### Requirement 4: Audio Capability Filtering

**User Story:** As a user, I want to see only apps that can produce audio, so that the mixer isn't cluttered with irrelevant processes.

#### Acceptance Criteria

1. WHEN enumerating applications THEN AppAudioMonitor SHALL filter to apps with potential audio capability
2. WHEN filtering THEN apps with known audio entitlements or AudioToolbox usage SHALL be prioritized
3. IF an app's audio capability cannot be determined THEN it SHALL be included by default (false negatives are worse than false positives)
4. WHEN the user opens System Settings or other known non-audio apps THEN these MAY be filtered out via a configurable exclusion list

### Requirement 5: IPC Bridge - Custom Properties

**User Story:** As a developer, I want to send volume commands to the driver via custom AudioObject properties, so that volume changes take effect in real-time.

#### Acceptance Criteria

1. WHEN the host sets a per-app volume THEN it SHALL write the value to a custom property on the virtual device
2. WHEN a custom property is written THEN the driver SHALL receive the data within 10ms
3. WHEN the driver receives a volume command THEN it SHALL apply the gain adjustment to the corresponding audio stream
4. IF the property write fails THEN the host SHALL log the error and retry once
5. WHEN the host reads the current volume THEN the driver SHALL return the last-set value

### Requirement 6: Volume Command Protocol

**User Story:** As a developer, I want a well-defined protocol for volume commands, so that host and driver agree on data format.

#### Acceptance Criteria

1. WHEN defining the volume command THEN it SHALL include: app bundle ID (String), volume level (Float32, 0.0-1.0)
2. WHEN serializing commands THEN the format SHALL be compact and fixed-size where possible
3. WHEN the driver receives an unknown bundle ID THEN it SHALL create a new volume entry for it
4. WHEN an app terminates THEN the host SHALL optionally send a cleanup command to release driver resources

### Requirement 7: Host Application Structure

**User Story:** As a developer, I want the AppFaders executable target to initialize the orchestrator, so that it's ready for UI integration in Phase 3.

#### Acceptance Criteria

1. WHEN the AppFaders app launches THEN it SHALL initialize SimplyCoreAudio, AppAudioMonitor, and IPC bridge
2. WHEN initialization completes THEN the app SHALL expose an observable state object for future UI binding
3. WHEN any component fails to initialize THEN the app SHALL continue with available functionality and surface errors
4. WHEN running without UI THEN the orchestrator SHALL function as a background service (no window, just initialization)

## Non-Functional Requirements

### Code Architecture and Modularity

- **Single Responsibility**: AppAudioMonitor handles process tracking only; IPC bridge handles driver communication only
- **Modular Design**: Each component is a separate Swift file/type with clear public API
- **Clear Interfaces**: Components communicate via protocols, enabling testing with mocks
- **SPM Target Isolation**: Host logic lives in `AppFaders` target; driver code untouched except for custom property additions

### Performance

- **Process Monitoring**: CPU usage < 0.5% when idle (no polling, notification-driven only)
- **IPC Latency**: Property writes complete within 10ms under normal load
- **Memory**: Minimal footprint—store only necessary app metadata (bundle ID, name, icon reference)

### Security

- No additional entitlements required beyond existing app sandbox
- Bundle ID-based app identification (no process injection or private APIs)
- Volume commands validated before sending (range check 0.0-1.0)

### Reliability

- Graceful handling of coreaudiod restarts (re-discover virtual device)
- No crashes if virtual device is absent (degraded mode)
- Notification observers properly removed on deinitialization

### Testability

- Unit tests for AppAudioMonitor with mock NSWorkspace
- Unit tests for IPC bridge with mock AudioObject calls
- Integration test proving volume command reaches driver (requires installed driver)
