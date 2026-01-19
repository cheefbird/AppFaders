# Tasks Document: host-audio-orchestrator

## Phase 1: Package Setup

- [x] 1. Add SimplyCoreAudio dependency and test target to Package.swift
  - File: Package.swift
  - Add SimplyCoreAudio 4.1.0+ dependency from github.com/rnine/SimplyCoreAudio
  - Add dependency to AppFaders executable target
  - Create AppFadersTests test target with dependency on AppFaders
  - Purpose: Enable device management and host-side testing
  - _Leverage: design.md SimplyCoreAudio Integration Details section_
  - _Requirements: 1.1, 1.2, 1.3_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer with SPM expertise | Task: Update Package.swift to add SimplyCoreAudio dependency (from: "4.1.0") and add it to AppFaders target dependencies. Create new AppFadersTests test target that depends on AppFaders. Reference design.md for exact structure. | Restrictions: Do not modify driver targets. Keep dependency version at 4.1.0+. | _Leverage: .spec-workflow/specs/host-audio-orchestrator/design.md | Success: `swift build` compiles with SimplyCoreAudio imported, `swift test` runs AppFadersTests | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 2: Shared Types (Driver-side)

- [x] 2. Add AppFadersProperty enum to AudioTypes.swift
  - File: Sources/AppFadersDriver/AudioTypes.swift
  - Define custom property selectors: setVolume (0x61667663 = 'afvc'), getVolume (0x61667671 = 'afvq')
  - Use AudioObjectPropertySelector type
  - Purpose: Shared IPC property identifiers between host and driver
  - _Leverage: design.md AppFadersProperty section, existing fourCharCode helper in VirtualDevice.swift_
  - _Requirements: 5.1, 5.2, 6.1_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift/CoreAudio developer | Task: Add AppFadersProperty enum to AudioTypes.swift with static let setVolume and getVolume as AudioObjectPropertySelector values. Use hex values 0x61667663 and 0x61667671. These are four-char codes 'afvc' and 'afvq'. | Restrictions: Do not modify existing types. Add to existing file only. | _Leverage: Sources/AppFadersDriver/AudioTypes.swift, design.md | Success: AppFadersProperty compiles and is accessible from driver code | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 3. Create VolumeStore for per-app volume storage
  - File: Sources/AppFadersDriver/VolumeStore.swift
  - Create thread-safe singleton with NSLock
  - Implement setVolume(bundleID:volume:), getVolume(bundleID:) with default 1.0, removeVolume(bundleID:)
  - Mark as @unchecked Sendable (uses internal lock)
  - Purpose: Store per-app volume settings for real-time gain application
  - _Leverage: design.md Component 5: VolumeStore, VirtualDevice.swift lock pattern_
  - _Requirements: 5.1, 5.2, 5.3, 6.3_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift concurrency developer | Task: Create VolumeStore.swift with thread-safe singleton. Use private NSLock and Dictionary<String, Float> for storage. setVolume validates 0.0-1.0 range. getVolume returns 1.0 for unknown bundleIDs. Follow lock pattern from VirtualDevice.shared. Add os_log for volume changes. | Restrictions: Must be thread-safe. No async/await - use locks for real-time safety. | _Leverage: Sources/AppFadersDriver/VirtualDevice.swift lock pattern, design.md | Success: VolumeStore compiles, is Sendable, and handles concurrent access safely | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 4. Add custom property handlers to VirtualDevice.swift
  - File: Sources/AppFadersDriver/VirtualDevice.swift
  - Update hasDeviceProperty to include AppFadersProperty.setVolume and getVolume
  - Update getDevicePropertyDataSize for custom properties
  - Update getDevicePropertyData to read from VolumeStore (for getVolume)
  - Update setPropertyData to write to VolumeStore (for setVolume)
  - Update kAudioObjectPropertyCustomPropertyInfoList to return our custom properties
  - Purpose: Enable IPC between host and driver via AudioObject properties
  - _Leverage: design.md IPC Protocol Design section, existing property handlers_
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: CoreAudio HAL developer | Task: Extend VirtualDevice.swift to handle custom IPC properties. Add AppFadersProperty selectors to hasDeviceProperty, getDevicePropertyDataSize, getDevicePropertyData, setPropertyData. For setVolume: parse VolumeCommand (UInt8 length + 255 bytes bundleID + Float32 volume), call VolumeStore.setVolume. For getVolume: use qualifier data as bundleID, return Float32 from VolumeStore. Update kAudioObjectPropertyCustomPropertyInfoList to return AudioObjectPropertyInfo structs for our properties. | Restrictions: Match existing property handler patterns. Keep real-time safe. | _Leverage: Sources/AppFadersDriver/VirtualDevice.swift, design.md | Success: Custom properties are discoverable and functional via AudioObjectSetPropertyData/GetPropertyData | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 3: Host Models and Utilities

- [x] 5. Create TrackedApp model
  - File: Sources/AppFaders/TrackedApp.swift
  - Define struct with bundleID, localizedName, icon (NSImage?), launchDate
  - Conform to Identifiable (id = bundleID), Sendable, Hashable
  - Add convenience init from NSRunningApplication
  - Purpose: Represent tracked applications for UI binding
  - _Leverage: design.md Data Models TrackedApp section_
  - _Requirements: 3.1, 3.2, 3.4_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift/AppKit developer | Task: Create TrackedApp.swift with struct matching design.md. Use AppKit NSRunningApplication and NSImage. Add init?(from: NSRunningApplication) that extracts bundleIdentifier, localizedName, icon, launchDate. Return nil if bundleIdentifier is nil. Mark NSImage as @unchecked Sendable via extension. | Restrictions: Exclude apps without bundleID per Requirement 3.5. | _Leverage: design.md Data Models, AppKit docs | Success: TrackedApp compiles, can be created from NSRunningApplication | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 6. Create DriverError enum
  - File: Sources/AppFaders/DriverError.swift
  - Define error cases: deviceNotFound, propertyReadFailed(OSStatus), propertyWriteFailed(OSStatus), invalidVolumeRange(Float), bundleIDTooLong(Int)
  - Conform to Error, LocalizedError with errorDescription
  - Purpose: Type-safe error handling for driver communication
  - _Leverage: design.md Error Types section_
  - _Requirements: 5.4, 6.4_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer | Task: Create DriverError.swift with enum cases matching design.md Error Types. Implement LocalizedError with descriptive errorDescription for each case. Include OSStatus code in messages for debugging. | Restrictions: Keep error descriptions user-friendly but informative. | _Leverage: design.md Error Handling section | Success: DriverError compiles and provides meaningful error messages | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 4: Host Components

- [ ] 7. Create DeviceManager wrapper for SimplyCoreAudio
  - File: Sources/AppFaders/DeviceManager.swift
  - Import SimplyCoreAudio, create instance
  - Implement allOutputDevices, appFadersDevice (find by UID)
  - Implement startObserving/stopObserving with NotificationCenter for .deviceListChanged
  - Add onDeviceListChanged callback
  - Purpose: Encapsulate device discovery and notifications
  - _Leverage: design.md Component 3: DeviceManager, SimplyCoreAudio Integration Details_
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: macOS audio developer | Task: Create DeviceManager.swift per design.md. Use SimplyCoreAudio() instance. Find appFadersDevice by filtering allOutputDevices where uid == "com.fbreidenbach.appfaders.virtualdevice". Subscribe to NotificationCenter .deviceListChanged in startObserving, store observer token, remove in stopObserving. Call onDeviceListChanged callback when notification fires. | Restrictions: Use SimplyCoreAudio APIs only, no raw CoreAudio. Handle nil device gracefully. | _Leverage: design.md, SimplyCoreAudio README | Success: DeviceManager finds virtual device when installed, receives device change notifications | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 8. Create AppAudioMonitor for process tracking
  - File: Sources/AppFaders/AppAudioMonitor.swift
  - Use NSWorkspace.shared.runningApplications for initial list
  - Subscribe to NSWorkspace.didLaunchApplicationNotification, didTerminateApplicationNotification
  - Filter to apps with bundleIdentifier (exclude command-line tools)
  - Implement delegate protocol for launch/terminate events
  - Purpose: Track running applications that may produce audio
  - _Leverage: design.md Component 2: AppAudioMonitor_
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: macOS/AppKit developer | Task: Create AppAudioMonitor.swift per design.md. On start(), snapshot NSWorkspace.shared.runningApplications filtered to non-nil bundleIdentifier, create TrackedApp for each. Subscribe to NSWorkspace notifications for launch/terminate. On launch: create TrackedApp, call delegate.monitor(_:didLaunch:). On terminate: extract bundleID from notification, call delegate.monitor(_:didTerminate:). Store observer tokens, remove in stop(). | Restrictions: Filter out apps without bundleIdentifier. Use main queue for notifications. | _Leverage: design.md, AppKit NSWorkspace docs | Success: AppAudioMonitor tracks app launches/terminates with < 1 second latency | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 9. Create DriverBridge for IPC communication
  - File: Sources/AppFaders/DriverBridge.swift
  - Import CoreAudio for AudioObject functions
  - Implement connect(deviceID:) storing AudioDeviceID
  - Implement setAppVolume using AudioObjectSetPropertyData with VolumeCommand format
  - Implement getAppVolume using AudioObjectGetPropertyData with bundleID as qualifier
  - Validate volume range, throw DriverError on failures
  - Purpose: Low-level IPC with driver via custom properties
  - _Leverage: design.md Component 4: DriverBridge, IPC Protocol Design_
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 6.1, 6.2_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: CoreAudio/IPC developer | Task: Create DriverBridge.swift per design.md. Store connected AudioDeviceID. For setAppVolume: validate 0.0-1.0 range, serialize VolumeCommand (UInt8 length + bundleID bytes padded to 255 + Float32 volume), call AudioObjectSetPropertyData with AppFadersProperty.setVolume selector. For getAppVolume: encode bundleID as qualifier, call AudioObjectGetPropertyData with getVolume selector, return Float32. Check OSStatus, throw DriverError on failure. | Restrictions: Bundle ID max 255 chars. Validate all inputs. Use os_log for errors. | _Leverage: design.md, CoreAudio AudioObject.h | Success: DriverBridge can send volume commands to installed driver | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 10. Create AudioOrchestrator as central coordinator
  - File: Sources/AppFaders/AudioOrchestrator.swift
  - Mark as @Observable for SwiftUI binding
  - Compose DeviceManager, AppAudioMonitor, DriverBridge
  - Expose trackedApps, isDriverConnected, appVolumes state
  - Implement start() that initializes all components
  - Implement setVolume(for:volume:) that updates state and calls DriverBridge
  - Conform to AppAudioMonitorDelegate to update trackedApps
  - Purpose: Central state container for orchestration layer
  - _Leverage: design.md Component 1: AudioOrchestrator_
  - _Requirements: 7.1, 7.2, 7.3_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer with Observation framework expertise | Task: Create AudioOrchestrator.swift per design.md. Use @Observable macro. Create DeviceManager, AppAudioMonitor (set self as delegate), DriverBridge as private properties. In start(): call deviceManager.startObserving(), appAudioMonitor.start(), attempt driverBridge.connect() if device found. setVolume: update appVolumes dict, call driverBridge.setAppVolume, handle errors. Implement AppAudioMonitorDelegate to add/remove from trackedApps. | Restrictions: Handle errors gracefully - don't crash if driver missing. | _Leverage: design.md, Swift Observation framework | Success: AudioOrchestrator compiles, manages state, coordinates components | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 11. Update main.swift to initialize orchestrator
  - File: Sources/AppFaders/main.swift
  - Create AudioOrchestrator instance
  - Call start() to initialize components
  - Print status (driver connected, tracked apps count)
  - Keep process alive with RunLoop or dispatchMain()
  - Purpose: Entry point that runs orchestrator as background service
  - _Leverage: design.md, existing main.swift_
  - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer | Task: Update main.swift to create AudioOrchestrator, call start(), print "AppFaders Host v0.2.0", print driver connection status and tracked app count. Use dispatchMain() to keep process running for notifications. Add signal handler for SIGINT to clean shutdown. | Restrictions: No UI - just console output for Phase 2. Keep it minimal. | _Leverage: Sources/AppFaders/main.swift, design.md | Success: `swift run AppFaders` starts orchestrator, prints status, receives app notifications | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 5: Testing

- [ ] 12. Create VolumeStore unit tests
  - File: Tests/AppFadersDriverTests/VolumeStoreTests.swift
  - Test setVolume/getVolume round-trip
  - Test default value (1.0) for unknown bundleID
  - Test removeVolume
  - Test concurrent access (dispatch multiple operations)
  - Purpose: Verify thread-safe volume storage
  - _Leverage: Swift Testing framework, design.md Testing Strategy_
  - _Requirements: 5.1, 5.2_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift test engineer | Task: Create VolumeStoreTests.swift using Swift Testing (@Test, #expect). Test: setVolume then getVolume returns same value, getVolume for unknown returns 1.0, removeVolume then getVolume returns 1.0, concurrent access from multiple DispatchQueue.global().async blocks doesn't crash. | Restrictions: Use Swift Testing not XCTest. Keep tests fast. | _Leverage: Swift Testing docs | Success: `swift test --filter VolumeStore` passes | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 13. Create AppAudioMonitor unit tests
  - File: Tests/AppFadersTests/AppAudioMonitorTests.swift
  - Test initial app enumeration
  - Test filtering (apps without bundleID excluded)
  - Purpose: Verify app tracking logic
  - _Leverage: Swift Testing framework, design.md Testing Strategy_
  - _Requirements: 3.1, 3.2, 3.5_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift test engineer | Task: Create AppAudioMonitorTests.swift using Swift Testing. Test that start() populates runningApps with current apps. Test that apps without bundleIdentifier are excluded. Use a mock delegate to verify callbacks. Note: Can't easily mock NSWorkspace notifications in unit tests, so focus on filtering logic. | Restrictions: Keep tests isolated and fast. Don't test NSWorkspace internals. | _Leverage: Swift Testing docs, design.md | Success: `swift test --filter AppAudioMonitor` passes | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 14. Create DriverBridge unit tests
  - File: Tests/AppFadersTests/DriverBridgeTests.swift
  - Test volume validation (reject out of range)
  - Test bundleID length validation
  - Test VolumeCommand serialization format
  - Purpose: Verify IPC serialization and validation
  - _Leverage: Swift Testing framework, design.md Testing Strategy_
  - _Requirements: 5.4, 6.1, 6.2_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift test engineer | Task: Create DriverBridgeTests.swift using Swift Testing. Test: setAppVolume throws invalidVolumeRange for volume < 0 or > 1, setAppVolume throws bundleIDTooLong for bundleID > 255 chars. Can't test actual CoreAudio calls in unit test, but can test validation logic. Consider extracting validation to testable methods. | Restrictions: Don't require installed driver for unit tests. Test validation only. | _Leverage: Swift Testing docs, design.md | Success: `swift test --filter DriverBridge` passes | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 15. Integration test: volume command round-trip
  - File: Documentation only (manual test procedure)
  - Install driver using Scripts/install-driver.sh
  - Run host app
  - Verify device connection logged
  - Set volume for a bundleID via test code or debug command
  - Read volume back, verify match
  - Check driver logs in Console.app for volume receipt
  - Purpose: End-to-end verification of IPC
  - _Leverage: Scripts/install-driver.sh, Console.app_
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 7.1_
  - _Prompt: Implement the task for spec host-audio-orchestrator, first run spec-workflow-guide to get the workflow guide then implement the task: Role: QA engineer | Task: Document and run manual integration test: 1) Run Scripts/install-driver.sh to install driver, 2) Run swift run AppFaders and verify "Driver connected" logged, 3) Modify main.swift temporarily to call orchestrator.setVolume(for: "com.apple.Safari", volume: 0.5), 4) Check Console.app for driver log showing volume received, 5) Verify getAppVolume returns 0.5. Document pass/fail results. | Restrictions: Manual testing - document actual results. | _Leverage: Scripts/install-driver.sh, Console.app | Success: Volume command successfully sent from host and received by driver | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion documenting test results, mark complete when done._
