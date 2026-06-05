# SwiftUI / AppKit UI Conventions

## Scenes

- `MenuBarExtra` (menu style) is the primary surface: profile switcher (active row shows a
  `checkmark`), "Open Relay…", "Quit".
- The management UI is a **`Window` (id `"main"`)**, opened from the menu via
  `@Environment(\.openWindow)` + `NSApplication.shared.activate()`, with
  `.defaultLaunchBehavior(.suppressed)` so the agent doesn't auto-open it at launch.
- **Do not put the management UI in the `Settings` scene.** Settings windows drop custom
  `.toolbar` buttons (Add App / Add Profile / Set Active became dead) and misbehave when the
  activation policy changes. `SettingsContainer` (a `TabView`: Profiles + General) lives in the
  Window.

## State injection & two-way editing

- Inject with `@Environment(AppModel.self)` and `@Environment(TargetAppResolver.self)`.
  An injected service must be `@Observable` (that's why `TargetAppResolver` is), with internal
  caches `@ObservationIgnored`.
- The model is read-only from views (`private(set) configuration`). For two-way controls, build
  an explicit binding that routes writes through `AppModel`:
  ```swift
  private var behaviorBinding: Binding<FocusBehavior> {
      Binding(get: { binding.behavior },
              set: { var b = binding; b.behavior = $0; model.updateBinding(b, in: profileID) })
  }
  ```
- Resolve list edits in the view, then call the model: `onDelete` → `model.removeBindings(...)`,
  `onMove` → reorder a copy → `model.setBindings(...)`. Keep `move/remove(atOffsets:)`
  (SwiftUI helpers) in the view; `AppModel` stays SwiftUI-free.

## Native HIG containers

- `NavigationSplitView` (sidebar list + detail). Sidebar uses `.contextMenu` (Set Active /
  Rename / Delete) and `.alert` with a `TextField` for rename.
- `Form` with `.formStyle(.grouped)` for settings; `List` + `.toolbar` for the binding editor
  (toolbars work in a `Window`).
- Empty / unavailable states use `ContentUnavailableView` ("No Apps", "No Profile Selected").
- Status is shown with small badges (red "Not installed" via resolver; conflict badge).

## Liquid Glass (macOS 26.5)

Rely on **automatic** Liquid Glass from standard containers (NavigationSplitView, toolbar, List,
Form, MenuBarExtra). **Do not hand-roll `.glassEffect` / `GlassEffectContainer`** — those are
only for bespoke floating surfaces, of which v1 has none. Don't over-decorate (no gratuitous
blur/gradient/shadow).

## Transient info: popover, not `.help`

For information the user actually needs, use a `.popover` (instant, modern) triggered by tap
and/or `.onHover`. The conflict badge is a `Button` that shows a popover. The legacy `.help`
tooltip has a long, non-configurable delay and dated styling — only acceptable for minor
supplementary hints on controls.

## Accessibility & appearance

- System controls give VoiceOver + keyboard navigation for free. Add `.accessibilityLabel` on
  icon-only elements (active indicator, conflict badge, app icon row).
- Support light/dark via semantic colors (`Color.primary`, `.secondary`, `.red`, `.orange`,
  `.tint`) — never hardcode RGB.

## AppKit bridges

When SwiftUI can't express it (custom key capture), use `NSViewRepresentable` with a
`@MainActor` `Coordinator`:

- Keep the captured combo flowing back through a `@Binding` to the model.
- Implement `dismantleNSView` to clean up (remove `NSEvent` monitors, restore global state).
- See `ShortcutRecorder` — the reference example.
