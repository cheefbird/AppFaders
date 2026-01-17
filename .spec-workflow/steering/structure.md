# Project Structure

## Directory Organization

The project is structured as a modern, monorepo-style Swift Package Manager (SPM) project. This ensures all components, including the low-level audio driver, are managed using native Swift tools.

```
AppFaders/                  # Project root
├── Package.swift           # SPM manifest defining all targets and dependencies
├── Sources/
│   ├── AppFaders/          # Main SwiftUI Application
│   │   ├── App.swift       # Application entry point & lifecycle
│   │   ├── UI/             # SwiftUI Views & ViewModels
│   │   │   ├── Components/ # Reusable UI elements (Sliders, Buttons)
│   │   │   └── Windows/    # Main settings and menu bar windows
│   │   └── Logic/          # Business logic & Device management
│   │       ├── AudioEngine.swift # High-level audio state management
│   │       └── AppMonitor.swift  # Running application detection logic
│   └── AppFadersDriver/    # Swift-based Audio Server Plug-in (HAL)
│       ├── DriverEntry.swift   # Plug-in entry point using Swift interfaces
│       ├── VirtualDevice.swift # Virtual audio device implementation
│       └── Support/            # Minimal C/C++ shims required by CoreAudio
├── Tests/
│   ├── AppFadersTests/     # Swift Testing suite for the application
│   └── AppFadersDriverTests/ # Unit tests for driver logic
└── Resources/              # Shared assets (Icons, Localizations)
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
1. **System Frameworks**: `Foundation`, `SwiftUI`, `CoreAudio`.
2. **First-party Swift Packages**: `SimplyCoreAudio`, `Pancake`.
3. **Internal Modules**: `AppFadersDriver`.

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

- **AppFaders (Main Target)**: Depends on `SimplyCoreAudio` for device orchestration. It observes the system state and commands the driver.
- **AppFadersDriver (Library Target)**: A specialized target that compiles into a `.driver` bundle. It utilizes Swift-based HAL frameworks (like `Pancake`) to minimize C++ boilerplate.
- **SimplyCoreAudio (External)**: Used as the primary bridge for high-level CoreAudio interactions.

## Code Size Guidelines

- **Source Files**: < 400 lines. Use extensions to separate protocol conformances.
- **Methods**: < 40 lines. Prefer small, composable functions.
- **Complexity**: Favor functional patterns (map, filter) over deep nested loops for processing application lists.