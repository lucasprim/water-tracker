# Swift Style Guide — Water Tracker

## General

- Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Prefer clarity over brevity, but avoid unnecessary verbosity
- Use Swift's modern features: `async/await`, `Sendable`, `@Observable`, structured concurrency

## Naming

- **Types**: `UpperCamelCase` — `WaterEntry`, `BottleSize`, `HydrationGoal`
- **Functions/variables**: `lowerCamelCase` — `logWaterIntake()`, `dailyGoalML`
- **Constants**: `lowerCamelCase` (prefer `let` over `var`)
- **Booleans**: use `is`, `has`, `should` prefixes — `isGoalReached`, `hasRemindersEnabled`
- Avoid abbreviations unless universally understood (`ml` for milliliters is fine)

## SwiftUI

- One view per file
- Extract subviews into separate `View` structs when a body exceeds ~50 lines
- Use `@State` for local UI state, `@Bindable` for SwiftData models
- Prefer `@Observable` (Observation framework) over `ObservableObject`/`@Published`
- Group view modifiers logically: layout → appearance → behavior

```swift
// Good
Text("500 ml logged")
    .font(.headline)
    .foregroundStyle(.primary)
    .padding()
    .onTapGesture { logEntry() }
```

## SwiftData

- Define models with `@Model` macro
- Use `@Attribute(.unique)` for identifiers
- Keep models focused — one responsibility per model
- Perform all model mutations on the `@MainActor` or within a `ModelContext`

```swift
@Model
final class WaterEntry {
    var amountML: Int
    var timestamp: Date
    var source: EntrySource

    init(amountML: Int, source: EntrySource = .manual) {
        self.amountML = amountML
        self.timestamp = .now
        self.source = source
    }
}
```

## Formatting

- 4-space indentation (Xcode default)
- Maximum line length: 120 characters
- One blank line between functions
- Opening braces on the same line (`K&R style`)
- No trailing whitespace

## Access Control

- Default to `private` or `internal`; only use `public` when needed for testing or frameworks
- Mark `final` on classes that aren't designed for subclassing

## Error Handling

- Use `throws` + `try/catch` for recoverable errors
- Use `Result<Success, Failure>` for async boundaries where appropriate
- Never use `try!` in production code; `try?` is acceptable when failure is expected and handled gracefully

## Async/Concurrency

- Use `async/await` over completion handlers
- Mark UI updates on `@MainActor`
- Use `Task { }` for fire-and-forget work; store the handle if cancellation is needed
- Avoid `DispatchQueue` — prefer structured concurrency

## Comments

- Write comments for non-obvious logic only
- Use `// MARK: -` to organize file sections
- Doc comments (`///`) on public/internal APIs

```swift
// MARK: - Webcam Detection

/// Analyzes the current camera frame to detect a drinking gesture.
func detectDrinkingGesture(in frame: CVPixelBuffer) async -> Bool { ... }
```

## File Organization

```
WaterTracker/
├── App/
│   └── WaterTrackerApp.swift
├── Models/
│   ├── WaterEntry.swift
│   └── BottleSize.swift
├── Views/
│   ├── MenuBar/
│   ├── Dashboard/
│   └── Settings/
├── ViewModels/  (if needed)
├── Services/
│   ├── CameraService.swift
│   └── NotificationService.swift
└── Extensions/
```
