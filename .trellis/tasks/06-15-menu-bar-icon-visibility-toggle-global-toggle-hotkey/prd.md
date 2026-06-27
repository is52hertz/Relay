# Menu-Bar Icon Visibility Toggle + Global Toggle Hotkey

## Goal

Let the user **hide the menu-bar (status) icon** to declutter, and provide a
**global hotkey that toggles its visibility** so a menu-bar agent never locks
the user out. Mirrors SirThor's rows 1–2 ("show status icon" + "enable
⇧⌃⌥⌘+T to toggle show/hide"). The deactivation-key rows (3–5) are explicitly
**not** part of this — that feature is dropped.

## Features

- **F-A — visibility toggle**: a setting to show/hide the menu-bar icon.
- **F-B — global toggle hotkey**: an always-on, profile-independent hotkey that
  flips F-A's visibility. F-B is F-A's safety hatch (see lockout policy).

## What I already know (from repo inspection)

- `MenuBarExtra` is currently **always shown** — `RelayApp.swift:15` has no
  `isInserted:` binding. The label reads `settings.menuBarIconName` live.
- `AppSettings` (`Models/AppConfiguration.swift`): `showDockIcon`,
  `launchAtLogin`, `defaultConfigID`, `menuBarIconName`. `AppConfiguration`
  `schemaVersion` = 3, with a backward-compat `decodeIfPresent` decoder on
  `AppSettings` (the pattern to follow for new keys).
- `Hotkey` model (`Models/Hotkey.swift`): `carbonKeyCode` / `carbonModifiers` —
  **library-independent persisted combo** (the format to reuse for the toggle
  hotkey, per the "store Carbon codes, not a library type" rule).
- `HotkeyRegistrationService` registers **only the active Profile's** bindings;
  `deactivateAll()` clears them on profile switch. There is **no always-on
  "app command" hotkey path** today — F-B introduces one.
- `ShortcutRecorder` (`UI/ShortcutRecorder.swift`) is reusable for recording a
  key+modifier combo (disables global hotkeys while recording).
- Menu-bar icon customization already lives in `PersonalizationSettingsView`
  (`.personalization` pane) — the natural home for F-A + F-B UI.
- `KeyboardShortcuts` (Carbon `RegisterEventHotKey`) supports **key+modifier
  combos** (no bare modifiers / no double-tap — not needed here).

## Confirmed decisions (from brainstorm)

- **F-A + F-B = one task** (strongly coupled; B is A's safety net). [user]
- **Lockout policy = must set a toggle hotkey before hiding.** The icon can only
  be hidden when a valid F-B toggle hotkey is configured; otherwise the "hide"
  control is disabled with guidance. Guarantees an always-available way back.
  [user]
- **F-B infra = implement only the icon-toggle command now, but write the
  always-on "app command" registration path so it's reusable** for future global
  commands (e.g. open settings). No extra commands in this task. [user]

## Requirements

- R1. New `AppSettings.showMenuBarIcon: Bool` (default **true**). Bump
  `AppConfiguration.schemaVersion` 3 → 4; decode new keys with `decodeIfPresent`
  (`showMenuBarIcon` ?? true) so old `config.json` still loads and existing
  users keep the icon.
- R2. Bind `MenuBarExtra(isInserted:)` to `showMenuBarIcon`. Toggling it
  shows/hides the status item live (via `@Observable`); persists (debounced).
- R3. New `AppSettings.menuBarToggleHotkey: Hotkey?` (default **nil**). nil =
  unset/disabled. Stored as Carbon codes (library-independent). `decodeIfPresent`
  ?? nil.
- R4. **App-command hotkey path** (reusable): register a dedicated always-on
  `KeyboardShortcuts.Name` (e.g. `appCommand.toggleMenuBarIcon`) **independent of
  the active Profile** — registered once at launch, **not** cleared by
  `deactivateAll()` on profile switch. `onKeyDown` → flip `showMenuBarIcon` via
  an `AppModel` mutation. Model the command set as an enum so adding future
  commands reuses the path.
- R5. **Lockout guard**: `showMenuBarIcon` may be set to `false` **only when**
  `menuBarToggleHotkey` is non-nil and successfully registered. The UI disables
  the hide control (with an explanatory note) until a toggle hotkey is set.
- R6. UI in `PersonalizationSettingsView`: a "Menu Bar Icon" section with the
  show/hide control + a `ShortcutRecorder` row for the toggle hotkey (+ clear).
- R7. All new user-facing strings localized en / zh-Hans / zh-Hant.

## Acceptance Criteria

- [ ] New install / existing config: icon stays visible by default (schema-4
      decode is backward-compatible; old config.json loads without data loss).
- [ ] Setting a toggle hotkey then hiding the icon removes the status item;
      pressing the hotkey brings it back — works regardless of the active
      Profile and survives profile switches.
- [ ] With no toggle hotkey set, the hide control is disabled and explains why
      (lockout prevention).
- [ ] The toggle hotkey is not cleared when switching Profiles.
- [ ] Recording the toggle hotkey reuses `ShortcutRecorder` (global hotkeys
      suspended during recording; Esc cancels, ⌫ clears).
- [ ] New strings present in en / zh-Hans / zh-Hant.
- [ ] No `CGEventTap` / global `NSEvent` monitors; no private APIs; models stay
      AppKit/SwiftUI-free.

## Definition of Done

- Build + type-check green for the Relay target.
- Unit tests: schema-4 backward-compat decode (missing `showMenuBarIcon` →
  true, missing hotkey → nil), the lockout rule (can't hide without a hotkey),
  and the app-command enum/registration mapping where testable without AppKit.
- Manual test: hide → re-show via hotkey; profile switch keeps the toggle
  hotkey alive; hide control gating; both-icons-off recoverability.
- Localization complete; relevant `notice.md` / spec updated for the new
  always-on app-command hotkey concept (it's a deliberate addition beyond the
  "register only active Profile" binding rule).

## Out of Scope

- The deactivation-key feature (double-tap modifier to suspend hotkeys) — needs
  forbidden global monitoring; dropped entirely.
- Any global app command other than toggle-menu-bar-icon (path is reusable, but
  no new commands here).
- Changing Dock-icon behavior or the existing icon customization.
- Cross-conflict auto-resolution between the app-command hotkey and profile
  bindings (see Technical Notes — surfaced, not auto-resolved).

## Technical Notes

- **Schema coordination with the data-management task**: that task reads/writes
  `AppConfiguration` generically, so new fields are transparent to it. This task
  owns the 3→4 bump. Whichever lands first, the other adapts; the backup
  import's `schemaVersion` gate then correctly rejects v4 backups on a v3 app.
- **App-command hotkey vs "active-Profile-only" rule**: the CLAUDE.md/spec rule
  ("register only the active Profile") governs *per-app-target bindings*. The
  toggle is an *app control command*, still via `KeyboardShortcuts`
  (key+modifier, Carbon), just always-on. Document this as an intentional,
  spec-noted second registration category — not a violation.
- **Conflict risk**: if a Profile binding uses the same physical combo as the
  app-command hotkey, Carbon `RegisterEventHotKey` behavior is undefined / first
  wins. MVP: surface a warning if detected (reuse the conflict-badge idea); do
  not auto-resolve.
- Reuse `ShortcutRecorder`; keep `Hotkey` (Carbon) as the persisted form;
  flip `showMenuBarIcon` through an `AppModel` method (preserve "all mutations
  go through AppModel").
