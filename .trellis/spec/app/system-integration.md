# macOS System Integration

Cross-app control uses **public AppKit APIs by default — no Input Monitoring, no private APIs.**
That constraint is a product rule (AGENTS.md); honor it. The one allowed exception is
**Accessibility, requested lazily and degrading safely** — it powers the window-management
actions and is confined to a single service (see *Window management via Accessibility* below).
Global hotkeys never need it.

## Global hotkeys (`HotkeyRegistrationService` + `KeyboardShortcuts`)

- Register **only the active Profile's** bindings. Each binding gets a dynamic
  `KeyboardShortcuts.Name(binding.id.uuidString)`; `setShortcut` + `enable` + `onKeyDown`.
- On profile switch: `deactivateAll()` (set shortcut `nil` + `disable`) then register the new
  set. Install each Name's `onKeyDown` handler **once** (handlers can't be removed); the handler
  reads the current binding from `bindingsByName`, gated by whether a shortcut is set/enabled.
- Within a profile, register only the **first** binding per identical combo (skip later dupes).
- **Never** use `CGEventTap` or global `NSEvent` monitors — they need Accessibility/Input
  Monitoring and are out of scope.

### App-command hotkeys (always-on, profile-independent)

There is a **second registration category** beyond per-app-target bindings: **global app commands**
(`AppCommand` enum → a stable `KeyboardShortcuts.Name`, e.g. `"appCommand.toggleMenuBarIcon"`).
This is an **intentional, spec-noted exception** to "register only the active Profile" — an app
*control* command, not a target binding, but still via `KeyboardShortcuts` (Carbon key+modifier),
just **always-on**.

- `HotkeyRegistrationService.setAppCommandShortcut(_:to:)` sets/clears the command's shortcut and
  installs its `onKeyDown` **once** (handler reads the injected action). `setAppCommandAction(_:action:)`
  injects the side effect (wired in `AppController`).
- **`deactivateAll()` must NOT clear app-command Names** — it only clears profile-binding Names
  (`activeNames`). App commands survive profile switches; that's the whole point (the menu-bar
  toggle hotkey must work in any profile).
- First user: **toggle menu-bar icon** (`showMenuBarIcon`). Its handler flips visibility via
  `AppModel.setMenuBarIconVisible`, which enforces the **lockout guard**
  (`MenuBarIconLockout.canSet`): the icon may be hidden **only when a toggle hotkey is set**, so a
  menu-bar agent can never lock the user out. Clearing the toggle hotkey while hidden auto-restores
  the icon.
- **Conflict risk** (a profile binding sharing the command's physical combo) is *undefined /
  first-wins* in Carbon `RegisterEventHotKey`. MVP surfaces nothing and does not auto-resolve —
  just a code comment.

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

## Window management via Accessibility (`WindowMinimizer`)

`WindowMinimizer` is the **sole Accessibility entry point** — the only place that touches
`AXUIElement`. Two FrontmostActions are AX-driven:

- **`minimize`** — minimize the focused/main window (`kAXMinimizedAttribute`).
- **`cycleWindowsThenHide`** — when the target is already frontmost, each press raises the next
  window; after the last window has been shown, the next press hides. Uses public AX only:
  `kAXWindowsAttribute` (enumerate), `kAXFocusedWindowAttribute` (cursor start), unminimize +
  `kAXRaiseAction` (raise). **No private window-id APIs** (`_AXUIElementGetWindow`) — window
  identity across presses is `CFEqual` reference equality.

Rules that both must follow:

- **Lazy permission, never at launch.** Request `AXIsProcessTrustedWithOptions` only when the user
  picks one of these actions in the editor (wired from `AppController`); read-only `isTrusted`
  checks elsewhere never prompt.
- **Safe degradation.** Without permission, do **not** silently no-op or do the wrong thing —
  fall back to plain `hide` and fire the shared one-time `onPermissionDenied` notice.
- **Cycle state is in-memory only** (`[bundleID: CycleState]` on `AppActivationService`), never in
  `AppModel`, never persisted. Order is a **snapshot taken at cycle start**, not re-derived from
  live z-order each press (raising mutates z-order → two windows would ping-pong). State resets
  when the app loses frontmost, via `FrontmostTracker.onAppResignedFrontmost` (the tracker only
  broadcasts the bundle ID; it holds no cycle state).

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

## Language switch & relaunch (`LanguageService`)

- The picked UI language is OS-side state: write the locale code to `AppleLanguages` (the app's
  own `UserDefaults` domain), keep the user's pick in our own `RelayPreferredLanguage` key, and
  `synchronize()` before relaunching. **Never** put language in the Codable JSON (avoid double
  source of truth — same posture as `LoginItemService`).
- Relaunch = spawn a fresh instance (`open -n <bundlePath>`) then `NSApp.terminate(nil)`; the new
  instance reads the updated `AppleLanguages` on launch.
- **Do two things synchronously BEFORE `open -n`**, via a single injected
  `beforeRelaunch: @MainActor () -> Void` hook from the composition root (`AppController` passes
  `{ [model, registration] in model.saveNow(); registration.deactivateAll() }`).
  `LanguageService` calls it first in `relaunch()` and must not depend on the concrete types of
  `AppModel` / `HotkeyRegistrationService` — only the closure.
  1. **Flush `AppModel`** (not just via the `willTerminate` handler): the debounced save (400 ms)
     plus the terminate-time flush race the new instance's disk read — `open -n` can boot and load
     stale JSON before the old instance flushes, then overwrite the just-saved edit → lost data
     (real P1 bug).
  2. **Release global hotkeys** (`deactivateAll()`): `NSApp.terminate` is async, so without this
     the new instance registers its Carbon hotkeys while the old process still owns the same combos.
     Cross-process `RegisterEventHotKey` handoff is not guaranteed, `KeyboardShortcuts` swallows
     registration failures (see above), and there is no retry — so hotkeys could come back dead
     after a language switch (real P2 bug). Releasing in the old process first removes the overlap.

## Build / signing posture (don't regress)

`ENABLE_APP_SANDBOX = NO` (the app controls other apps), `ENABLE_HARDENED_RUNTIME = YES`,
`LSUIElement = YES`, deployment target `26.5`. No paid Apple Developer account — local/self-use;
not MAS. Adding the `KeyboardShortcuts` SPM package required manual `project.pbxproj` edits
(package reference, product dependency, frameworks phase) — IDs use a `DEADBEEF…` prefix.
