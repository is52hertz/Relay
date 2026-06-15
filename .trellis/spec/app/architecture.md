# Architecture & Data Flow

## Layering

```
Models (pure data)
  → Persistence (PersistenceStore: Codable JSON)
  → State (AppModel: in-memory single source of truth)
  → Services (resolver / activation / hotkey registration / frontmost / login / dock)
  → UI (SwiftUI)
AppController = composition root that wires State ↔ Services.
```

## Single source of truth

`AppModel` (`@MainActor @Observable`) owns `AppConfiguration` and is the only mutable state.

- `configuration` is `private(set)`. **All mutations go through `AppModel` methods**
  (`addProfile`, `setActiveProfile`, `addBinding`, `updateBinding`, `removeBindings`,
  `setBindings`, `settings` setter, `replaceConfiguration` for bulk swap…). Never mutate config
  from outside.
- **Bulk swap = `replaceConfiguration(_:)`** (used by restore/reset): it **sanitizes dangling
  references** (`activeProfileID` → an existing profile or nil; `settings.defaultConfigID` → an
  existing config) before assigning, then fires the hooks and `saveNow()` (immediate, not the
  debounced path — a bulk swap must not be lost in the 400ms window). A hand-edited or older
  backup may dangle, so sanitization is mandatory.
- The UI reads via `@Environment(AppModel.self)` and writes via explicit
  `Binding(get:set:)` that call those methods (see ui/swiftui.md), or via small methods.
- **`AppModel` imports only `Foundation` + `Observation` — no AppKit/SwiftUI.** This keeps it
  unit-testable and forces side effects out through hooks.

## Side effects go through hooks, wired by AppController

`AppModel` exposes `@ObservationIgnored` closures, called after the relevant mutation:

- `hotkeysDidChange: ((Profile?) -> Void)?` — fires when the active profile or its bindings change.
- `settingsDidChange: ((AppSettings) -> Void)?` — fires when settings change.

`AppController.init` constructs the services and the model, wires the closures
(`model.hotkeysDidChange = { registration.activate($0) }`, etc.), then applies launch state
(register active profile, sync Dock/login) — **guarded so it does not run under the XCTest
host**. Services are passed by reference/injected; there are no singletons.

Views never call services directly for these concerns — they mutate `AppModel`, and the hook
fans out to the service.

## Persistence (`PersistenceStore`)

- JSON at `~/Library/Application Support/cn.Teethe.Relay/config.json`, atomic write,
  pretty-printed + sorted keys. `AppModel` debounces saves (~400ms, cancellable Task) and has
  `saveNow()`.
- `AppConfiguration` carries `schemaVersion` for future migration.
- **Persist stable identity, not derived/runtime data**: store `bundleIdentifier`,
  `lastKnownPath`, Carbon key codes. Do **not** persist app icons or running state — re-derive
  at runtime via `TargetAppResolver` / `NSWorkspace`.
- Keep persisted formats independent of third-party libraries: `Hotkey` stores Carbon codes,
  converted to/from `KeyboardShortcuts.Shortcut` only at the edges (`Hotkey+KeyboardShortcuts`).

## Backup / restore / reset (`BackupService`)

- **Backups are versioned envelopes, not raw `config.json`.** `BackupEnvelope`
  (`formatVersion`, `appVersion`, `exportedAt`, `schemaVersion`, `configuration`) wraps the
  `AppConfiguration`. Import **gates on `schemaVersion`**: an envelope newer than
  `AppConfiguration.currentSchemaVersion` is rejected (`BackupError.newerSchema`); equal/older
  decodes via the existing `decodeIfPresent` compat path. Corrupt input → `unreadable`, with **no
  mutation** to current data.
- **Automatic rolling snapshots** are the undo safety net: before every destructive op
  (reset / import / restore-from-snapshot) the *current* config is written to
  `…/cn.Teethe.Relay/Backups/` (reuse `PersistenceStore.containerDirectory()` — don't duplicate
  the bundle-id), keeping the newest **N=10**. Snapshot failure prompts Continue/Cancel — never a
  silent destroy. Snapshots survive a reset (reset only rewrites `config.json`); off-machine
  recovery is the manual export's job, not these.
- `BackupService` is **Foundation-only and injected from `AppController`** (AppKit-free → unit
  testable). The `NSSavePanel` / `NSOpenPanel` / `NSAlert` live in the UI layer
  (`DataSettingsView`), which hands chosen URLs to the service. Backup scope is the Codable
  `AppConfiguration` only — including `AppSettings` preferences (`launchAtLogin`, `showDockIcon`,
  `menuBarIconName`), which are re-applied via `settingsDidChange` on restore. The only excluded
  state is what lives **outside** `AppConfiguration`: the UI language
  (`AppleLanguages` / `RelayPreferredLanguage` in `UserDefaults`).

## Adding a feature — the path

1. Add/extend a `nonisolated` model in `Models/` (+ bump `schemaVersion` if the on-disk shape
   changes).
2. Add a mutation method on `AppModel`; if it has a system effect, call the appropriate hook
   (or add a new one) at the end.
3. Wire the hook in `AppController`.
4. Build the UI against `AppModel` (read via environment, write via `Binding`/methods).
5. Add a pure-function test if there's decidable logic.
