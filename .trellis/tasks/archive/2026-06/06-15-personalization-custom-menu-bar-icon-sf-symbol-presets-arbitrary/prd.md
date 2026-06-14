# PRD — Personalization: custom menu bar icon

## Goal
Let the user change Relay's menu-bar (status item) icon from the **Personalization**
settings tab. Currently the icon is hardcoded `Image(systemName: "command")` in
`RelayApp.swift`'s `MenuBarExtra` label. The choice persists and applies live.

## Scope
- 4 quick **presets**: `command` (current/default), `bolt`, `bolt.fill`,
  `righttriangle.split.diagonal`.
- A **custom SF Symbol** field: the user may type any SF Symbol name.
- Live update: changing the selection updates the menu-bar icon immediately.
- Persistence: store the chosen SF Symbol **name string** (library-independent).

## Out of scope
- Importing image files / non-SF-Symbol custom art.
- Per-Profile icons (single global icon only).
- Tinting / rendering-mode customization.

## Decisions
- **D1 — Control style (to be finalized by manual test):** build **all three**
  candidate controls at once inside Personalization (Style A segmented icons,
  Style B icon swatches with selection ring, Style C menu picker), all bound to the
  same setting, plus the custom field. User picks one by testing; the other two are
  then deleted before commit. (User asked to "build all three so I can test".)
- **D2 — Arbitrary SF Symbol allowed**, but **validated** in the view via
  `NSImage(systemSymbolName:accessibilityDescription:)`. Invalid name → inline notice +
  **do not write** the setting (menu bar never goes blank). Safe-degradation per AGENTS.md.
- **D3 — Persisted shape changes** → add `menuBarIconName: String` (default `"command"`)
  to `AppSettings`; bump `AppConfiguration.currentSchemaVersion` 2 → 3.
- **D4 — Backward-compat (data-loss guard):** Swift's synthesized `Decodable` requires
  every key present; existing on-disk `config.json` lacks the new key, so a plain add
  would throw → `PersistenceStore.load()` returns nil → `makeDefault()` **wipes the
  user's profiles/bindings**. Fix: custom `AppSettings.init(from:)` using
  `decodeIfPresent(...) ?? "command"` for the new field so old files still load.
- **D5 — Reactive label:** inject `controller.model` into the `MenuBarExtra` label;
  render `Image(systemName: settings.menuBarIconName)`. Defensive fallback to `"command"`
  if the stored name ever fails to resolve.

## Files (planned)
- `Models/AppConfiguration.swift` — `AppSettings.menuBarIconName` + custom `init(from:)`;
  static preset list; bump schemaVersion.
- `UI/PersonalizationSettingsView.swift` — new "Menu Bar Icon" section (3 candidate
  controls + custom field + validation), bound through `model.settings`.
- `RelayApp.swift` — label reads `model.settings.menuBarIconName`; inject model.

## Verification
- Build (Relay target).
- Manual: switch presets → menu bar updates live; type valid custom symbol → applies;
  type invalid → notice, no blank icon; quit & relaunch → choice persists; existing
  config.json (no new key) loads without wiping profiles.

## Follow-up (post-test)
- Remove the two non-chosen control styles; keep the winner + custom field.
