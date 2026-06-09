# Redesign FocusBehavior → per-state behavior model

## Goal
The current 4 fixed presets (Return to Previous / Launch or Focus / Toggle Hide / Focus Only) hide *what actually varies* and mislead users. Replace the opaque single-label picker with a model that makes explicit, per app-state (未启动 / 后台 / 前台), what action runs — and let users customize (and possibly name) those combinations.

## What I already know (from code inspection)
- `Models/FocusBehavior.swift` — `nonisolated enum FocusBehavior: String, Codable, CaseIterable` with 4 cases + `displayName` + `summary`.
- `Services/AppActivationDecision.swift` — pure decision: `RuntimeState {notInstalled, notRunning, running, frontmost} × FocusBehavior → Action {none, markInvalid, launch, focus, hide, returnToPrevious}`.
- Stored per-binding: `HotkeyBinding.behavior: FocusBehavior`; global default: `AppConfiguration.defaultBehavior: FocusBehavior`. Persisted as Codable JSON raw strings.
- UI pickers iterate `FocusBehavior.allCases`: `UI/GeneralSettingsView.swift` (global default) and `UI/BindingRow.swift` (per-binding).

### Current behavior matrix (the key insight)
| Preset | 未安装 | 未启动 | 后台(running) | 前台(frontmost) |
|---|---|---|---|---|
| Return to Previous | invalid | launch | focus | return-to-prev |
| Launch or Focus | invalid | launch | focus | none |
| Toggle Hide | invalid | launch | focus | hide |
| Focus Only | invalid | none | focus | none |

**Constants across all presets**: 未安装→invalid; 后台→focus.
**Only two axes actually vary**: 未启动 ∈ {launch, none}; 前台 ∈ {return-to-prev, hide, none}.
→ The 4 presets are just 4 of the 6 points in a (2 × 3) space.

## Direction (chosen by user)
**C — a named, user-editable config table in the General view** (add/remove/rename rows, each row assigns per-state actions). Chosen because the user plans to add more per-state behaviors later (前台 minimize/hide, 后台 hide/keep), so an extensible table beats fixed presets. Bindings reference a config; the table is global (shared across profiles).

## Boundary conditions (discovered in code)
**[CRITICAL] B1 — Migration is mandatory and the current loader silently wipes on mismatch.**
`PersistenceStore.load()` = `try? decoder.decode(...)` → ANY schema mismatch returns nil and the caller falls back to `makeDefault()`. Changing `HotkeyBinding.behavior` (enum→config-id) + adding a config table is a breaking schema change, so an existing `config.json` would fail to decode and **silently erase all profiles/bindings**. Must bump `schemaVersion` 1→2 AND add a decode-tolerant migration (read old shape → transform → new shape) before the strict path.

**[CRITICAL] C1 — `前台最小化` is likely NOT buildable within current constraints.**
Minimizing another app's window needs Accessibility (`AXUIElement` `kAXMinimizedAttribute`). AGENTS.md forbids Accessibility/private APIs. `NSRunningApplication` only offers hide/unhide/activate/terminate — no minimize. So "前台最小化" ≠ "前台隐藏(hide)". Either drop minimize, or it requires a product-level scope expansion into Accessibility. **Gates the action vocabulary.**

**B2 — Referential integrity.** Bindings/default reference a config by id: deleting an in-use config must not dangle (forbid, or reassign to default); must always keep ≥1 config + a valid global default; decide whether the 4 seeded defaults are protected or freely deletable/renameable.

**B3 — Per-state action sets differ (not a free grid).** 未安装→invalid (fixed, not editable); 未启动 ∈ {Launch, None}; 后台 ∈ {Focus, Hide, None}; 前台 ∈ {Return-to-prev, Hide, None (+Minimize iff Accessibility)}. Editor must constrain options per column.

**B4 — State granularity limited by no-Accessibility.** `running` merges 后台/已隐藏/无可见窗口 (can't distinguish). A future "后台 hide/unhide toggle" can't detect "has visible window", so hidden↔visible toggles are imprecise. Constrains future 后台 semantics.

**B5 — `returnToPrevious` fallback persists.** No previous app / terminated / is-target → degrades to hide target. Keep and document.

**B6 — Keep the decision layer pure.** `AppActivationDecision.action(for:behavior:)` is pure + unit-tested. New: it maps `RuntimeState × <per-state config> → Action`. Only add `Action` cases for what is actually buildable.

## Decisions (confirmed with user)
- **D1 — No migration.** App is unreleased; no stored `config.json` to preserve. Drop the migration concern entirely; just seed sensible default configs in a fresh `makeDefault()`. (B1 risk no longer applies.)
- **D2 — Minimize is in scope, via Accessibility.** AGENTS.md security boundary will be updated to permit Accessibility for window minimize (pending edit — not done yet).
- **D3 — Lazy Accessibility permission.** Do NOT request at launch. Check `AXIsProcessTrusted()` / prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` only when the user first configures/uses a minimize action. App stays fully functional without it; only minimize is gated. Caveat: granted permission is App-level full AX access (cannot be scoped to just minimize) — document this in AGENTS.md.

- **D4 — Minimize: PLACEHOLDER this task.** 最小化 (前台, needs Accessibility) is deferred to a later task — UI shows it disabled/reserved; no Accessibility, no AGENTS.md change, no lazy-permission flow in THIS task. (D2/D3 become next-task concerns, kept as notes.)
- **D5 — 后台 column: PLACEHOLDER this task.** 后台 stays fixed = Focus; the column renders disabled/reserved. Editable 后台 ({Focus, Hide, Quit, None} + the isHidden split into 已隐藏/未隐藏) is the next task.
- **D6 — New atomic actions IN this task:** `launchWithoutFocus` (启动但不聚焦 — `openApplication` with `activates=false`, public API) and `quit` (退出 — `NSRunningApplication.terminate()`, public API).

## State model (confirmed complete)
Editable this task: **未启动, 前台**. Placeholder this task: **后台** (fixed=Focus). Fixed/never-editable: **未安装→invalid**.
Future split (public API, no Accessibility): 后台 → 已隐藏 (`isHidden==true`) vs 未隐藏 — lands in the next 后台 task. Finer than that (visible-window / per-window minimized) needs Accessibility.

## Action vocabulary (atomic)
- `launch` 启动并聚焦 · `launchWithoutFocus` 启动但不聚焦 [new this task] · `focus` 聚焦 · `showWithoutFocus` 显示不聚焦 (unhide, no activate) [placeholder] · `hide` 隐藏 · `returnToPrevious` 切回上一个 · `quit` 退出 [new this task] · `minimize` 最小化 [placeholder, needs Accessibility, next task] · `none` 不做事 · (internal `markInvalid`).
- Toggles (hide↔show) are NOT atomic actions — they emerge from per-state config.

## Per-state valid options (this task)
| 状态 | 可选动作 | 本期 |
|---|---|---|
| 未安装 | invalid | 固定，不入表 |
| 未启动 | 启动并聚焦 / 启动但不聚焦 / 不做事 | **可编辑·有功能** |
| 后台 | 聚焦 / 显示不聚焦 / 最小化 | **占位·选项可见但无功能**（引擎仍按聚焦执行；默认种子=聚焦） |
| 前台 | 切回上一个 / 隐藏 / 退出 / 不做事 / 最小化 | 可编辑·有功能（**最小化为占位禁用**） |

> 后台占位语义：下拉列出三项让设计完整，但本期不接引擎、也不改运行行为（下一个任务再接，并用 `isHidden` 拆 已隐藏/未隐藏）。

## Default seed configs (editable later)
| 名称(可改) | 未启动 | 后台(占位) | 前台 |
|---|---|---|---|
| Return to Previous | 启动并聚焦 | 聚焦 | 切回上一个 |
| Launch or Focus | 启动并聚焦 | 聚焦 | 不做事 |
| Toggle Hide | 启动并聚焦 | 聚焦 | 隐藏 |
| Focus Only | 不启动 | 聚焦 | 不做事 |

## Data model approach (concept)
- New global value type (working name `ActivationConfig`): `{ id: UUID, name, notRunning, background, frontmost }` actions; `nonisolated Codable`, no AppKit/SwiftUI.
- Root `AppConfiguration` gains `activationConfigs: [ActivationConfig]` (global, shared across profiles), seeded with the 4 defaults.
- `HotkeyBinding.behavior: FocusBehavior` → `configID: UUID`; `AppSettings.defaultBehavior` → `defaultConfigID: UUID`.
- No migration (D1) — fresh `makeDefault()` seeds configs + sets default id.
- Decision layer stays pure: `AppActivationDecision.action(for: RuntimeState, config: ActivationConfig) -> Action`; extend `Action` with `launchWithoutFocus`, `quit` (reserve `minimize`).
- UI: General view gains the config table (add / remove / rename / edit per-state); `BindingRow` per-binding picker + `GeneralSettingsView` default picker select from the config list by name.

## UI approach (macOS 26)
No single drop-in "editable config table" component exists. Build from standard parts so automatic Liquid Glass + keyboard/VoiceOver come for free (AGENTS.md — do not hand-roll glass):
- **`Table(of: ActivationConfig, selection:)`** — confirmed available on macOS (`init(_:selection:columns:)`, sortable/columnCustomization variants exist). Columns: **Name | 未启动 | 后台 | 前台**.
  - Name cell: inline-editable `TextField` (double-click to rename), bound to the row.
  - State cells: `Picker(...).pickerStyle(.menu)` → native pop-up; 后台 cell + 前台「最小化」rendered `.disabled` (placeholder).
- **Bottom editor bar**: standard macOS `＋ / －` footer (`Button { } label: { Image(systemName: "plus"/"minus") }`, `.borderless`). `－` disabled when nothing selected / would delete the global-default or last row.
- Lives inside the General `Form`/section (standard container → Liquid Glass applies automatically).
- **Fallback** if inline `Table` text-editing fights us: master–detail — `Table`/`List` of configs + a small editor `Form` (sheet or inline) for the selected row (name `TextField` + 3 `Picker`s). Decide during implementation; both are HIG-native.
- Pickers in `BindingRow` / `GeneralSettingsView` update live on config add/remove/rename.

## Research References
- SwiftUI `Table` (macOS) init family with `selection:` / `sortOrder:` / `columnCustomization:` — confirmed via apple-docs search (`documentation/SwiftUI/table/*`).

## Delete & integrity rules (confirmed)
- **Defaults NOT protected** — the 4 seed rows are ordinary, fully editable/deletable.
- **Delete any config is allowed**, with a two-step confirmation **only when it has dependents**:
  - Dialog part 1 (standard): warn that bindings depend on this config.
  - Dialog part 2: **list the dependents** (per dependent: `Profile › App`, across all profiles since configs are global).
  - On confirm → delete; **referencing bindings reassign to the global-default config**.
- No dependents → delete directly (no two-step dialog; standard `－` removes the row).
- **Always keep ≥1 config** (`－` disabled at the last row) so bindings/default can always resolve.
- **Deleting the global-default config**: allowed; first move `defaultConfigID` to another remaining config (top-most), then reassign dependents to that new default. (Edge noted — confirm acceptable.)

## Requirements (locked)
1. New global `ActivationConfig` value type (`nonisolated Codable`, no AppKit/SwiftUI): `{id, name, notRunning, background, frontmost}`.
2. `AppConfiguration.activationConfigs: [ActivationConfig]`, seeded with the 4 defaults; `makeDefault()` also sets `settings.defaultConfigID`.
3. `HotkeyBinding.behavior: FocusBehavior` → `configID: UUID`; `AppSettings.defaultBehavior` → `defaultConfigID: UUID`. Remove `FocusBehavior` enum. No migration.
4. Decision layer pure: `AppActivationDecision.action(for: RuntimeState, config: ActivationConfig) -> Action`; `Action` += `launchWithoutFocus`, `quit`; reserve `minimize`, `showWithoutFocus`.
5. Execution: `launchWithoutFocus` via `openApplication(activates:false)`; `quit` via `runningInstances.terminate()`. 后台 engine behavior unchanged (always focus this task).
6. General view: editable config `Table` (name + 3 state columns) + `＋/－` bar; per-state `Picker`s; 后台 column & 前台「最小化」disabled placeholders; delete-confirm dialog per rules above.
7. `BindingRow` + `GeneralSettingsView` pickers select a config by name from `activationConfigs`, live-updating on add/remove/rename.

## Acceptance Criteria
- [ ] Fresh launch seeds 4 default configs; existing 4-preset behaviors reproduce 1:1 (notRunning/frontmost matrix unchanged).
- [ ] A binding triggers the correct Action for each RuntimeState given its referenced config (unit tests on the pure decision fn, incl. new `launchWithoutFocus`/`quit`).
- [ ] `launchWithoutFocus` launches without stealing focus; `quit` terminates running instances.
- [ ] Add / rename / edit-per-state / delete configs from the General table; pickers elsewhere reflect changes live.
- [ ] Deleting an in-use config shows the two-step dialog listing dependents (`Profile › App`); on confirm, dependents fall back to the global default; `－` disabled at last row.
- [ ] 后台 column and 前台「最小化」are visible but disabled (no engine effect).
- [ ] Build + existing/extended unit tests green; no AppKit/SwiftUI import in models/decision layer.

## Out of Scope (this task)
- 后台 editable behavior + 已隐藏/未隐藏 split (next task).
- 最小化 action + Accessibility integration + lazy-permission flow + AGENTS.md security-boundary edit (next task).
- Any Accessibility-based finer state detection / per-window control.

## Technical Notes
- Data models must stay `nonisolated` Codable, no AppKit/SwiftUI import (AGENTS.md).
- Decision layer (`AppActivationDecision`) is pure/unit-tested — keep it pure.
- Any model change needs a JSON migration path for existing persisted bindings.
