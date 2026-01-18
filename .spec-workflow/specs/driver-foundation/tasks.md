# Tasks Document: driver-foundation

## Phase 1: Project Setup

- [x] 1. Initialize SPM monorepo with Package.swift
  - File: Package.swift
  - Create Swift 6 package manifest with macOS 26+ platform target
  - Define products: AppFaders executable, AppFadersDriver dynamic library, BundleAssembler plugin
  - Add Pancake dependency (or placeholder if fork needed)
  - Configure CoreAudio/AudioToolbox linker settings for driver target
  - Purpose: Establish build system foundation
  - _Leverage: SPM documentation, Context7_
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer specializing in SPM and macOS development | Task: Create Package.swift for monorepo with app target, driver library target, and build plugin target. Use Swift 6, macOS 26+ only, arm64. Add Pancake dependency from github.com/0bmxa/Pancake. Link CoreAudio and AudioToolbox frameworks. Reference design.md for exact structure. | Restrictions: Do not create Xcode project files. Do not add unnecessary dependencies. Keep package manifest clean and minimal. | _Leverage: .spec-workflow/specs/driver-foundation/design.md, Context7 for SPM docs | Success: `swift build` compiles without errors, package structure matches design.md | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 2. Create placeholder app entry point
  - File: Sources/AppFaders/main.swift
  - Create minimal main.swift that prints version info
  - Purpose: Satisfy SPM executable target requirement
  - _Leverage: None_
  - _Requirements: 1.1_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer | Task: Create minimal main.swift for AppFaders executable target that prints "AppFaders v0.1.0 - Driver Foundation" and exits. | Restrictions: Keep it minimal - no UI, no functionality beyond print statement. | _Leverage: None | Success: `swift run AppFaders` prints version and exits cleanly | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 3. Create driver Info.plist template
  - File: Resources/Info.plist
  - Define CFBundleIdentifier, CFBundleName, CFBundleExecutable
  - Add AudioServerPlugIn dictionary with DeviceUID
  - Purpose: Required metadata for HAL plug-in bundle
  - _Leverage: Apple AudioServerPlugIn documentation_
  - _Requirements: 5.1, 5.2_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: macOS developer with HAL plug-in experience | Task: Create Info.plist for AppFadersDriver.driver bundle. Include CFBundleIdentifier=com.appfaders.driver, CFBundleExecutable=AppFadersDriver, and AudioServerPlugIn dict with DeviceUID=com.appfaders.virtualdevice. | Restrictions: Use exact keys required by coreaudiod. No extra keys. | _Leverage: design.md Bundle Structure section | Success: Info.plist contains all required AudioServerPlugIn keys | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 2: HAL Wrapper Setup

- [x] 4. Verify Pancake Swift 6 compatibility
  - File: docs/pancake-compatibility.md
  - Tested Pancake import and documented incompatibility
  - Decision: Use custom minimal HAL wrapper instead
  - Purpose: Validate dependency before building on it
  - _Leverage: Pancake repository, Context7_
  - _Requirements: 2.1, 2.2_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer debugging dependency issues | Task: Create PancakeCheck.swift that imports Pancake and attempts to use CreatePancakeDeviceConfig(), PancakeDeviceConfigAddFormat(), and CreatePancakeConfig(). Run swift build and document results. If build fails, document specific errors. | Restrictions: Do not modify Pancake source. Just test and document. | _Leverage: Context7 for Pancake docs if available, github.com/0bmxa/Pancake | Success: Document whether Pancake builds with Swift 6 - either "works" or "fails with [specific errors]" | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts documenting compatibility status, mark complete when done._

- [x] 5. Create C interface layer for HAL plug-in
  - Files: Sources/AppFadersDriverBridge/PlugInInterface.c, include/PlugInInterface.h
  - Implement COM-style factory function `AppFadersDriver_Create()`
  - Create AudioServerPlugInDriverInterface vtable with function pointers
  - Bridge to Swift implementation via @_cdecl exports
  - Purpose: Entry point that coreaudiod loads and calls
  - _Leverage: BackgroundMusic BGM_PlugInInterface.cpp, Apple AudioServerPlugIn.h_
  - _Requirements: 2.2, 3.1_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: C/Swift interop developer with CoreAudio experience | Task: Create minimal C interface layer for HAL plug-in. Implement factory function matching CFPlugInFactories UUID. Create vtable implementing AudioServerPlugInDriverInterface. Use @_cdecl to expose Swift functions. Reference BackgroundMusic's BGM_PlugInInterface.cpp for patterns. | Restrictions: Keep C layer minimal - just bridge to Swift. Use Apple's AudioServerPlugIn.h types exactly. | _Leverage: docs/pancake-compatibility.md, BackgroundMusic source | Success: C interface compiles and exports correct symbols for coreaudiod loading | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 3: HAL Driver Implementation

- [x] 6. Implement DriverEntry (HAL plug-in entry point)
  - File: Sources/AppFadersDriver/DriverEntry.swift
  - Create Swift singleton that manages plug-in lifecycle
  - Implement Initialize(), CreateDevice(), DestroyDevice() callbacks via @_cdecl
  - Coordinate with C interface layer from Task 5
  - Purpose: Entry point that coreaudiod calls
  - _Leverage: BackgroundMusic BGM_PlugIn, design.md Component 1_
  - _Requirements: 3.1, 3.2, 3.3_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: macOS audio driver developer | Task: Create DriverEntry.swift implementing the HAL plug-in entry point. Create singleton managing plugin state. Expose Initialize(), CreateDevice(), Teardown() via @_cdecl for C interface to call. Use os_log for diagnostics. | Restrictions: Keep real-time safe - no allocations in audio callbacks. | _Leverage: design.md, BackgroundMusic BGM_PlugIn.cpp | Success: Driver compiles and exports correct symbols for coreaudiod | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 7. Implement VirtualDevice
  - File: Sources/AppFadersDriver/VirtualDevice.swift
  - Create AudioObject representing "AppFaders Virtual Device"
  - Implement property getters/setters (name, UID, manufacturer, etc.)
  - Configure device as output type
  - Purpose: The virtual audio device users see in System Settings
  - _Leverage: BackgroundMusic BGM_Device, design.md Component 2_
  - _Requirements: 3.1, 3.2_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: CoreAudio developer | Task: Create VirtualDevice.swift implementing the AudioObject for "AppFaders Virtual Device". Set name="AppFaders Virtual Device", uid="com.fbreidenbach.appfaders.virtualdevice", manufacturer="AppFaders". Implement HasProperty, IsPropertySettable, GetPropertyDataSize, GetPropertyData, SetPropertyData for required properties. | Restrictions: Follow AudioObject property patterns exactly. | _Leverage: design.md, BackgroundMusic BGM_Device.cpp, CoreAudio headers | Success: Device properties are correctly reported when queried | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 8. Implement VirtualStream
  - File: Sources/AppFadersDriver/VirtualStream.swift
  - Create stream configuration (sample rate, format, channels)
  - Support common formats: 44.1kHz, 48kHz, 96kHz stereo
  - Implement startIO/stopIO callbacks
  - Purpose: Handle audio stream configuration
  - _Leverage: BackgroundMusic BGM_Stream, design.md Component 3_
  - _Requirements: 4.1_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Audio systems developer | Task: Create VirtualStream.swift implementing audio stream for VirtualDevice. Support 44100, 48000, 96000 Hz sample rates, stereo (2 channel), 32-bit float PCM. Implement stream property handlers and startIO/stopIO that coordinate with PassthroughEngine. | Restrictions: Support standard formats only for Phase 1. | _Leverage: design.md, BackgroundMusic BGM_Stream.cpp, CoreAudio AudioStreamBasicDescription | Success: Stream reports correct formats and handles IO lifecycle | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 9. Implement PassthroughEngine
  - File: Sources/AppFadersDriver/PassthroughEngine.swift
  - Route captured audio to default physical output
  - Use CoreAudio APIs for output device discovery
  - Implement real-time safe audio buffer processing
  - Purpose: Actually play the audio through speakers
  - _Leverage: CoreAudio/AudioToolbox, design.md Component 4_
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Real-time audio systems developer | Task: Create PassthroughEngine.swift that routes audio from VirtualDevice to the default output device. Use AudioObjectGetPropertyData to find default output. Set up IOProc for real-time audio routing. Handle device changes gracefully. | Restrictions: MUST be real-time safe - no locks, no allocations in audio callback. Use lock-free patterns. | _Leverage: design.md, BackgroundMusic BGMPlayThrough patterns, CoreAudio | Success: Audio played to virtual device is heard through physical output | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 10. Create shared audio types
  - File: Sources/AppFadersDriver/AudioTypes.swift
  - Define AudioDeviceConfiguration struct
  - Define StreamFormat struct
  - Add CoreAudio type extensions if needed
  - Purpose: Shared types across driver components
  - _Leverage: design.md Data Models_
  - _Requirements: All_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift developer | Task: Create AudioTypes.swift with AudioDeviceConfiguration and StreamFormat structs exactly as defined in design.md Data Models section. Make them Sendable for Swift 6 concurrency. Add any useful CoreAudio type aliases or extensions. | Restrictions: Match design.md exactly. Keep minimal. | _Leverage: design.md Data Models section | Success: Types compile and are usable by other driver components | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 4: Build System

- [x] 11. Create BundleAssembler build plugin
  - File: Plugins/BundleAssembler/BundleAssembler.swift
  - Implement SPM BuildToolPlugin
  - Assemble .driver bundle structure (Contents/MacOS, Contents/Info.plist)
  - Copy compiled binary and Info.plist to correct locations
  - Purpose: Automate driver bundle creation
  - _Leverage: SPM plugin docs, Context7, design.md Component 5_
  - _Requirements: 5.1, 5.2, 5.3_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Build systems engineer with SPM expertise | Task: Create BundleAssembler.swift implementing SPM BuildToolPlugin. Use prebuildCommand to create AppFadersDriver.driver/ bundle structure in plugin work directory. Copy Info.plist to Contents/, create Contents/MacOS/ directory. The actual binary linking happens separately. | Restrictions: Follow SPM plugin patterns exactly. Use FileManager for file operations. | _Leverage: Context7 SPM plugin docs, design.md | Success: Running swift build produces correct bundle structure in build output | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [x] 12. Create install script
  - File: Scripts/install-driver.sh
  - Copy .driver bundle to /Library/Audio/Plug-Ins/HAL/
  - Restart coreaudiod
  - Verify device appears
  - Purpose: Streamline development iteration
  - _Leverage: None_
  - _Requirements: 3.1_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: DevOps/shell scripting | Task: Create install-driver.sh that: 1) Builds with swift build, 2) Copies AppFadersDriver.driver to /Library/Audio/Plug-Ins/HAL/ (requires sudo), 3) Runs sudo killall coreaudiod, 4) Waits 2 seconds, 5) Checks if "AppFaders Virtual Device" appears in system_profiler SPAudioDataType. | Restrictions: Must handle errors gracefully. Require explicit sudo. | _Leverage: None | Success: Script installs driver and verifies it loads | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

## Phase 5: Testing & Verification

- [ ] 13. Create driver unit tests
  - File: Tests/AppFadersDriverTests/AudioTypesTests.swift
  - Test AudioDeviceConfiguration: creation, defaults, supportedFormats
  - Test StreamFormat: creation, defaults, bytesPerFrame, toASBD(), init(from:), Equatable
  - Test AudioRingBuffer: write/read operations, wrap-around, underflow/overflow behavior
  - Purpose: Verify driver logic without coreaudiod
  - _Leverage: Swift Testing framework_
  - _Requirements: All_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: Swift test engineer | Task: Create AudioTypesTests.swift using Swift Testing framework (@Test, #expect). Test AudioDeviceConfiguration defaults and supportedFormats. Test StreamFormat bytesPerFrame, toASBD round-trip, Equatable. Test AudioRingBuffer write/read, wrap-around at capacity, and edge cases. | Restrictions: Use Swift Testing, not XCTest. Keep tests fast and isolated. Focus on testable logic, not CoreAudio mocking. | _Leverage: Swift Testing docs via Context7 | Success: `swift test` passes all tests | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion with artifacts, mark complete when done._

- [ ] 14. Manual integration test
  - File: Documentation only (no code file)
  - Install driver using install script
  - Verify device appears in System Settings → Sound → Output
  - Select device and play audio from Music.app or Safari
  - Verify audio passes through to speakers
  - Document results
  - Purpose: End-to-end verification
  - _Leverage: Task 12 install script_
  - _Requirements: 3.1, 3.2, 4.1, 4.2_
  - _Prompt: Implement the task for spec driver-foundation, first run spec-workflow-guide to get the workflow guide then implement the task: Role: QA engineer | Task: Run manual integration test: 1) Run Scripts/install-driver.sh, 2) Open System Settings → Sound → Output, 3) Verify "AppFaders Virtual Device" appears, 4) Select it as output, 5) Play audio in Music.app or Safari, 6) Verify audio is heard through speakers. Document pass/fail and any issues. | Restrictions: This is manual testing - document actual results. | _Leverage: install-driver.sh | Success: Audio plays through virtual device without issues | Instructions: Mark task in-progress in tasks.md before starting, use log-implementation tool after completion documenting test results, mark complete when done._
