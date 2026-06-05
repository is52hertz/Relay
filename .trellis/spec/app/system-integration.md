# macOS System Integration

All cross-app control uses **public AppKit APIs only — no Accessibility, no Input Monitoring,
no private APIs.** That constraint is a product rule (AGENTS.md); honor it.

## Global hotkeys (`HotkeyRegistrationService` + `KeyboardShortcuts`)

- Register **only the active Profile's** bindings. Each binding gets a dynamic
  `KeyboardShortcuts.Name(binding.id.uuidString)`; `setShortcut` + `enable` + `onKeyDown`.
- On profile switch: `deactivateAll()` (set shortcut `nil` + `disable`) then register the new
  set. Install each Name's `onKeyDown` handler **once** (handlers can't be removed); the handler
  reads the current binding from `bindingsByName`, gated by whether a shortcut is set/enabled.
- Within a profile, register only the **first** binding per identical combo (skip later dupes).
- **Never** use `CGEventTap` or global `NSEvent` monitors — they need Accessibility/Input
  Monitoring and are out of scope.

### Conflict detection (what's possible)

- Intra-profile duplicates: detect ourselves with `HotkeyConflicts.duplicateBindingIDs(in:)`
  (reliable, library-independent) and badge them in the UI.
- System / other-app conflicts: **not programmatically detectable** — `KeyboardShortcuts` does
  not surface `RegisterEventHotKey` failures. Do not pretend to detect them.

## App activation / focus (`AppActivationService` + `AppActivationDecision`)

- Keep the **decision pure and the side effects separate**: `AppActivationDecision` (nonisolated)
  maps `RuntimeState × FocusBehavior → Action`; `AppActivationService` reads runtime state and
  performs the action.
- Runtime state is `notInstalled / notRunning / running / frontmost`. **"Running but no visible
  window" can't be detected without Accessibility**, so it folds into `running`; the executor
  covers it with `unhide` + `openApplication` (reopen).
- **Bring an app forward with `NSWorkspace.openApplication(at: bundleURL)`** (launch, focus, and
  Return-to-Previous all use this). **Do not use `NSRunningApplication.activate(from: .current)`**
  — cooperative activation silently fails from a background agent that isn't frontmost (this was
  a real bug). Hiding uses `NSRunningApplication.hide()/unhide()`.

### Return to Previous — "model A"

`FrontmostTracker` observes `NSWorkspace.didActivateApplicationNotification` and keeps a global
`(current, previous)` pair, **excluding Relay itself**. Equivalent to ⌘-Tab's depth-2 MRU; pure
event-driven, zero idle cost. When the target is frontmost, activate `previous` (via
`openApplication`); if none, fall back to hiding the target.

## Shortcut recording (`ShortcutRecorder`)

- Custom `NSViewRepresentable` using a **local** `NSEvent` keyDown monitor +
  `KeyboardShortcuts.Shortcut(event:)`. Do **not** use the library's SwiftUI `Recorder` — in
  2.4.0 it is Name-based only and auto-registers a global hotkey, which would break the
  "active-profile-only" invariant and keep our JSON from being the source of truth.
- **Disable global hotkeys while recording** (`KeyboardShortcuts.isEnabled = false`), restore on
  `stop()` and in `dismantleNSView`. Otherwise a live global hotkey intercepts the combo and
  launches that app instead of being recorded. Esc cancels, Delete/⌫ clears.

## Login item & Dock icon

- `LoginItemService` wraps `SMAppService.mainApp` register/unregister (idempotent against
  `.status`). Failures are non-fatal (`NSLog`) — may not persist without proper signing / when
  run from Xcode rather than `/Applications`.
- `DockIconController` toggles `NSApplication.shared.setActivationPolicy(.regular/.accessory)`
  then `activate()` (so switching to `.accessory` doesn't hide the open window). Baseline is
  agent (`LSUIElement = YES`).

## Build / signing posture (don't regress)

`ENABLE_APP_SANDBOX = NO` (the app controls other apps), `ENABLE_HARDENED_RUNTIME = YES`,
`LSUIElement = YES`, deployment target `26.5`. No paid Apple Developer account — local/self-use;
not MAS. Adding the `KeyboardShortcuts` SPM package required manual `project.pbxproj` edits
(package reference, product dependency, frameworks phase) — IDs use a `DEADBEEF…` prefix.
