# Concurrency & Isolation

The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 5 language mode,
approachable concurrency). **Unannotated types and functions are `@MainActor`-isolated by
default.** This is the single most important fact for writing code here.

## Data models must be `nonisolated`

Pure data models are value types that need `Codable` / `Hashable` / `Sendable` conformances —
those witnesses must be nonisolated, and the values must be usable off the main actor
(decoding, hashing). So every model is declared `nonisolated` and must **not** import
AppKit/SwiftUI.

```swift
// Relay/Models/Hotkey.swift
nonisolated struct Hotkey: Codable, Hashable, Sendable {
    var carbonKeyCode: Int
    var carbonModifiers: Int
}
```

Same for `FocusBehavior`, `TargetApp`, `HotkeyBinding`, `Profile`, `AppConfiguration`,
`AppSettings`. If you add a model, mark it `nonisolated` — otherwise its `Codable`/`Hashable`
conformance becomes main-actor-isolated and breaks decoding/use off-main.

## Everything touching AppKit/SwiftUI stays on MainActor

Services and views are left at the default (`@MainActor`). `@Observable` state classes
(`AppModel`, `TargetAppResolver`) and services (`AppActivationService`,
`HotkeyRegistrationService`, `FrontmostTracker`, `LoginItemService`, `DockIconController`)
are all `@MainActor final class`.

## `@Observable` + `@ObservationIgnored`

State/observable services use `@Observable`. Mark stored dependencies that are **not** view
state with `@ObservationIgnored`, or you get spurious view updates / update loops:

```swift
@MainActor @Observable
final class TargetAppResolver {
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]   // mutated during body → must be ignored
}
// AppModel: closures hotkeysDidChange / settingsDidChange are @ObservationIgnored too.
```

## Pitfalls hit in this codebase (do not repeat)

- **Default arguments can't call a `@MainActor` initializer** (default-arg expressions are a
  nonisolated context). Construct inside the init body instead:
  ```swift
  init(store: PersistenceStore? = nil) {
      let store = store ?? PersistenceStore()   // NOT `store: PersistenceStore = PersistenceStore()`
      ...
  }
  ```
- **`MEMBER_IMPORT_VISIBILITY` is on**: you must import the module that *defines* a member you
  use, even if another import would transitively expose it. E.g. a file using `UUID.uuidString`
  needs `import Foundation` even if it already imports `KeyboardShortcuts`. (AppKit re-exports
  Foundation, so files importing AppKit are fine.)
- **Notification observers / `NSEvent` monitors** are `@Sendable` and deliver on the main
  thread; capture a `@MainActor` self (it's `Sendable`) and hop with `MainActor.assumeIsolated`
  inside. See `FrontmostTracker` (didActivate) and `ShortcutRecorder` (local keyDown).
- **Do not touch `NSApp` during early `@State`/composition-root init** — it is `nil` before
  AppKit finishes launching and force-unwraps trap. Use `NSApplication.shared` (non-optional,
  lazily created). See `DockIconController`.
- **Launch-time system side effects must be skipped under tests** — the XCTest host runs the
  app's `@main`, and `SMAppService` crashes there. `AppController` guards with
  `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`.

## Async work

Debounce with a cancellable `Task` + `Task.sleep`, capturing a value snapshot (see
`AppModel.scheduleSave`). Hotkey callbacks and activation run on the main actor.
