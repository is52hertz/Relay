# Data Management — Backup / Restore / Reset (with rolling snapshots)

## Goal

Give the user first-class, in-app control over their Relay data: **export** a
portable backup file, **import** (restore) one, and **reset** to defaults — all
from a dedicated Settings pane, with **automatic rolling snapshots** taken
before any destructive operation as an undo safety net. This replaces the
fragile "copy config.json from a shell" approach with a structured, versioned,
validated, app-managed mechanism.

## What I already know (from repo inspection)

- Single source of truth: `AppModel.configuration` (`@MainActor @Observable`),
  persisted as `AppConfiguration` Codable JSON at
  `~/Library/Application Support/cn.Teethe.Relay/config.json` via
  `PersistenceStore` (atomic write, debounced 400 ms save + `saveNow()` on
  terminate).
- `AppConfiguration` (`Models/AppConfiguration.swift`): `schemaVersion` (= 3),
  `profiles`, `activeProfileID`, `activationConfigs`, `settings` (`AppSettings`:
  `showDockIcon`, `launchAtLogin`, `defaultConfigID`, `menuBarIconName`).
  Backward-compat custom decoder already exists on `AppSettings`.
- Defaults: `AppConfiguration.makeDefault()` (1 "Default" profile + 4 seed
  `ActivationConfig`s).
- **No whole-config replacement method exists** — must add
  `AppModel.replaceConfiguration(_:)` that swaps `configuration`, sanitizes
  dangling references, then fires the existing side-effect hooks.
- Side-effect hooks wired in `AppController`: `model.hotkeysDidChange` →
  `registration.activate(profile)`; `model.settingsDidChange` →
  `loginItem.setEnabled` + `dockIcon.setDockIconVisible`; plus `saveNow()`.
- Settings UI: `SettingsRootView` NavigationSplitView with `Pane` enum
  (`.general`, `.personalization`). Adding a pane = enum case + title/icon +
  detail switch. Existing reusable patterns: `NSOpenPanel`
  (`BindingsDetailView.swift:94`), `NSAlert` (`AppController.swift:103`),
  SwiftUI `confirmationDialog` (`GeneralSettingsView.swift:44`).

## Confirmed decisions (from brainstorm)

- **Backup scope = `AppConfiguration` only.** Includes profiles/bindings/
  activation configs/settings (and `menuBarIconName`). **Excludes** OS-side
  state: UI language (`AppleLanguages` / `RelayPreferredLanguage`) and
  login-at-login (`SMAppService`) — they are machine/environment state, not
  portable. [user A1]
- **Automatic rolling snapshots = yes**, as the undo safety net before every
  destructive op (reset / restore / import). [user A2]
- **Snapshot directory = `~/Library/Application Support/cn.Teethe.Relay/Backups/`**
  (inside Relay's container). Reset only rewrites `config.json`, so snapshots
  survive a reset. Off-machine / disaster recovery is the job of the manual
  Export, not these snapshots. [user A2-followup]
- **UI = a new dedicated `.data` pane** in `SettingsRootView` (icon
  `externaldrive`), holding Export / Import / Reset + the snapshot list. [user A3]

## Requirements

- R1. **Export (Backup)**: serialize the current config into a self-describing
  envelope and write it where the user chooses via `NSSavePanel`.
  - Envelope (new `nonisolated Codable` type), e.g.
    `BackupEnvelope { formatVersion: Int; appVersion: String; exportedAt: Date;
    schemaVersion: Int; configuration: AppConfiguration }`.
  - Default filename includes a timestamp; suggested extension `.relaybackup`
    (JSON under the hood). Atomic write.
- R2. **Import (Restore)**: pick a file via `NSOpenPanel`, decode + validate,
  confirm (destructive), then replace.
  - Validate `schemaVersion`: **reject** envelopes whose `schemaVersion` is
    **newer** than the app supports (message: created by a newer Relay);
    equal/older decode via the existing backward-compat path.
  - On accept: take a snapshot (R4), then `AppModel.replaceConfiguration(_:)`.
  - Invalid/corrupt file → clear error alert, **no change** to current data.
- R3. **Reset**: destructive confirm → snapshot (R4) →
  `AppModel.replaceConfiguration(AppConfiguration.makeDefault())`.
- R4. **Automatic rolling snapshots**: before any reset/import, write the
  *current* config as a timestamped file into `Backups/`; keep the most recent
  **N** (default 10), delete older. Snapshot write failure surfaces a warning
  and the user decides whether to proceed (never silently destroy without a net).
- R5. **Snapshot restore UI**: the Data pane lists recent snapshots
  (timestamp, maybe size) with **Restore** and **Reveal in Finder**; Restore
  routes through the same confirm + `replaceConfiguration` path.
- R6. `AppModel.replaceConfiguration(_:)`: swaps configuration, **sanitizes**
  dangling references (`activeProfileID` → existing profile or first;
  `settings.defaultConfigID` → existing config or first), then fires
  `hotkeysDidChange` (re-register active profile), `settingsDidChange`
  (login item + dock icon), and `saveNow()`.
- R7. All new user-facing strings localized en / zh-Hans / zh-Hant.

## Architecture (proposed)

- New `BackupService` (Foundation-only, injected from `AppController` — no
  singletons; AppKit-free so it's unit-testable): encode/decode the envelope,
  write/rotate snapshots, enumerate snapshots, read a snapshot/backup file into
  an `AppConfiguration`. The `NSSavePanel`/`NSOpenPanel` live in the Data pane
  **view** (UI layer); the view hands chosen URLs to the service.
- New `BackupEnvelope` + (optional) `SnapshotInfo` value types — `nonisolated`,
  no AppKit/SwiftUI import.
- `AppModel.replaceConfiguration(_:)` is the only mutation entry point for bulk
  swap (keeps "all mutations go through AppModel" invariant).
- New `SettingsRootView.Pane.data` + `DataSettingsView`.

## Acceptance Criteria

- [ ] Export writes a `.relaybackup` (valid JSON envelope w/ metadata) to the
      user-chosen location; re-importing it round-trips the exact config.
- [ ] Import of a valid backup replaces config; hotkeys re-register, dock/login
      side effects apply, data persists; a snapshot was taken first.
- [ ] Import of a corrupt file or a newer-schema file fails safely with a clear
      message and leaves current data untouched.
- [ ] Reset restores defaults after confirm; a snapshot was taken first.
- [ ] Snapshots accumulate in `Backups/`, capped at N (oldest pruned); the Data
      pane lists them and can restore/reveal them.
- [ ] Restoring a config with a dangling `activeProfileID` / `defaultConfigID`
      lands on a valid, consistent state (no crash, no empty UI).
- [ ] New strings present in en / zh-Hans / zh-Hant.
- [ ] No cloud/network code; models stay AppKit/SwiftUI-free; no private APIs.

## Definition of Done

- Build + type-check green for the Relay target.
- Unit tests for `BackupService` (envelope encode/decode round-trip, schema
  validation accept/reject, snapshot rotation keep-N) and
  `AppModel.replaceConfiguration` sanitization — all AppKit-free, testable.
- Manual test: export → reset → import-the-export → verify identical; corrupt
  file; snapshot rotation; restore-from-snapshot.
- Localization complete; `notice.md` updated if a durable contract emerges.

## Out of Scope

- iCloud / cloud / network sync (conflicts with the local-only security
  boundary; the app is local/self-use).
- Backing up OS-side state (UI language, login item).
- Encryption / password-protected backups.
- Scheduled/timed periodic snapshots (snapshots are only before destructive
  ops). Could be a future addition.
- Changing the `AppConfiguration` schema (this feature only reads/writes it).

## Technical Notes

- Keep `BackupService` Foundation-only; do file IO with atomic writes; the
  panels stay in the view.
- Snapshot filename: include sortable timestamp for ordering + pruning.
- `schemaVersion` is the compatibility gate; reuse `AppSettings`'
  `decodeIfPresent` posture for older envelopes.
- This is a separate task from the upcoming "menu-bar icon visibility + toggle
  hotkey" feature.
