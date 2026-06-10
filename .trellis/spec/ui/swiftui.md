# SwiftUI / AppKit UI Conventions

## Scenes

- `MenuBarExtra` (menu style) is the primary surface: profile switcher (active row shows a
  `checkmark`), "Open Relay…" (no shortcut), "Quit". Its **label** view hosts the launch-source
  trigger (see below).
- The **management UI (Profiles)** is a **`Window` (id `"main"`)** — `ProfilesView`
  (NavigationSplitView with the "Add Profile" toolbar), injecting `AppModel` + `TargetAppResolver`.
  Like `SettingsRootView`, its sidebar is **pinned** (`columnVisibility: .constant(.doubleColumn)`,
  `.toolbar(removing: .sidebarToggle)`) — no collapse button, which avoids the SwiftUI collapse
  reflow where the leading toolbar buttons jump beside the traffic lights into a glass capsule.
  It must stay in a `Window`, **not** the `Settings` scene: Settings windows drop custom
  `.toolbar` buttons (Add App / Add Profile / Set Active go dead) and misbehave when the
  activation policy changes.
- **General lives in a dedicated `Window` (id `"settings"`)**, **not** the SwiftUI `Settings`
  scene — SwiftUI's `Settings` scene handles `NavigationSplitView` poorly (phantom detail-column
  inset, sidebar jitter) and doesn't resize reliably. The root is `SettingsRootView`
  (System-Settings-style `NavigationSplitView`, `columnVisibility: .constant(.doubleColumn)`,
  sidebar-toggle removed; detail → `GeneralSettingsView`, a plain `.formStyle(.grouped)` `Form`
  whose +/- are in-Form footer buttons). Inject `AppModel` + `WindowMinimizer` here. The system
  ⌘, shortcut and the app-menu "Settings…" item are reattached via
  `.commands { CommandGroup(replacing: .appSettings) { … } }` whose button calls
  `@Environment(\.openWindow)` for the settings window (⌘, is bound there, exactly once). The
  menu-bar "Settings…" item opens the same window but does **not** re-bind ⌘,.
- **Launch-source-aware window**: keep `.defaultLaunchBehavior(.suppressed)` on the Window (it
  never auto-restores). An `NSApplicationDelegateAdaptor` (`AppDelegate`) detects login-item launch
  in `applicationDidFinishLaunching` via `NSAppleEventManager.shared().currentAppleEvent`
  (`eventID == kAEOpenApplication` && `keyAEPropData` enum == `keyAELaunchedAsLogInItem`).
  **Login launch → stay hidden; explicit launch (or `applicationShouldHandleReopen`) → open the
  Window.** The delegate owns an `@Observable` `LaunchCoordinator` (no singleton); the MenuBarExtra
  label observes its flag and calls `@Environment(\.openWindow)`. "Open Relay…" is the manual path.

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
