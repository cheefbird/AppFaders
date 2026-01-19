# Project Structure

## Directory Organization

The project is structured as a modern, monorepo-style Swift Package Manager (SPM) project. This ensures all components, including the low-level audio driver, are managed using native Swift tools.

```sh
AppFaders/                              # Project root
├── Package.swift                       # SPM manifest (targets, dependencies, -bundle flag)
├── CLAUDE.md                           # Project conventions for AI assistance
├── Sources/
│   ├── AppFaders/                      # Main SwiftUI Application (Phase 2+)
│   │   └── main.swift                  # Placeholder entry point
│   ├── AppFadersDriver/                # Swift HAL implementation (Phase 1 ✓)
│   │   ├── AppFadersDriver.swift       # Module entry, version constant
│   │   ├── AudioTypes.swift            # Configuration structs (Sendable)
│   │   ├── DriverEntry.swift           # Plugin lifecycle, @_cdecl exports
│   │   ├── PassthroughEngine.swift     # Audio routing + AudioRingBuffer
│   │   ├── VirtualDevice.swift         # Device property handlers
│   │   └── VirtualStream.swift         # Stream config + IO state
│   └── AppFadersDriverBridge/          # C interface layer for HAL
│       ├── PlugInInterface.c           # COM-style vtable, factory function
│       └── include/
│           └── PlugInInterface.h       # C function prototypes
├── Tests/
│   └── AppFadersDriverTests/           # Swift Testing suite
│       ├── AppFadersDriverTests.swift  # Placeholder
│       └── AudioTypesTests.swift       # Config, format, ring buffer tests
├── Plugins/
│   └── BundleAssembler/                # SPM BuildToolPlugin
│       └── BundleAssembler.swift       # Assembles .driver bundle structure
├── Resources/
│   └── Info.plist                      # CFPlugIn configuration for driver
├── Scripts/
│   ├── install-driver.sh               # Build, sign, install, restart coreaudiod
│   └── uninstall-driver.sh             # Remove driver from system
└── docs/
    ├── hal-driver-lessons-learned.md   # HAL driver gotchas and patterns
    └── pancake-compatibility.md        # Why we use custom C wrapper
```

## Naming Conventions

### Files

- **Swift Files**: `PascalCase.swift` (e.g., `VolumeController.swift`).
- **Target Folders**: `PascalCase` (e.g., `AppFadersDriver`).
- **Tests**: `PascalCaseTests.swift`.

### Code

- **Types (Structs, Classes, Enums)**: `PascalCase`.
- **Properties & Functions**: `camelCase`.
- **Macros/Property Wrappers**: `@CamelCase` or `@camelCase` depending on framework usage.

## Import Patterns

### Import Order

1. **System Frameworks**: `Foundation`, `SwiftUI`, `CoreAudio`, `AudioToolbox`, `os.log`.
2. **First-party Swift Packages**: `SimplyCoreAudio`.
3. **Internal Modules**: `AppFadersDriver`, `AppFadersDriverBridge`.

## Code Structure Patterns

### SwiftUI Component Pattern

```swift
@Observable
class ComponentViewModel { ... }

struct ComponentView: View {
    @State private var viewModel = ComponentViewModel()
    var body: some View { ... }
}
```

### Module Organization

- **Public API**: Clearly marked with `public` or `package` access modifiers.
- **Implementation**: `internal` or `private` by default to enforce strict module boundaries.

## Code Organization Principles

1. **Swift-First**: Every component must be implemented in Swift unless strictly prohibited by system constraints.
2. **Strict Concurrency**: Leverage Swift 6 `Sendable` and `Actor` types to manage audio device state safely across threads.
3. **Dependency Injection**: Use protocols and injection to ensure the UI can be tested with mock audio devices.
4. **Package-Driven**: All shared code between the App and the Driver must be factored into local SPM libraries.

## Module Boundaries

- **AppFaders (Executable Target)**: Main application. Will depend on `SimplyCoreAudio` for device orchestration.
- **AppFadersDriver (Dynamic Library Target)**: Swift implementation of HAL driver logic. Depends on `AppFadersDriverBridge`. Exports functions via `@_cdecl` for C interop. Built with `-Xlinker -bundle` to produce `MH_BUNDLE` binary.
- **AppFadersDriverBridge (Library Target)**: C interface layer implementing `AudioServerPlugInDriverInterface` vtable. Factory function `AppFadersDriver_Create` serves as CFPlugIn entry point.
- **BundleAssembler (Plugin Target)**: SPM `BuildToolPlugin` that assembles the `.driver` bundle structure from build artifacts.
- **SimplyCoreAudio (External)**: Will be used as primary bridge for high-level CoreAudio interactions in Phase 2.

## Code Size Guidelines

- **Source Files**: < 400 lines. Use extensions to separate protocol conformances.
- **Methods**: < 40 lines. Prefer small, composable functions.
- **Complexity**: Favor functional patterns (map, filter) over deep nested loops for processing application lists.
