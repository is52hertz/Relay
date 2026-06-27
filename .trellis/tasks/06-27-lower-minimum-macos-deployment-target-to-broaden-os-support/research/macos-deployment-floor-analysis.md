# Research: macOS Deployment-Target Floor Analysis (lower min OS toward 12.7)

- **Query**: Can Relay's minimum macOS be lowered from 26.5 toward 12.7? Determine the hard floors, every version-gated API in the code, and the cost per target tier.
- **Scope**: internal (Relay/Relay/**/*.swift + Relay.xcodeproj) + dependency inspection (KeyboardShortcuts 2.4.0)
- **Date**: 2026-06-27

## TL;DR

- **Current setting**: `MACOSX_DEPLOYMENT_TARGET = 26.5` (project.pbxproj, 4 build-config blocks).
- **Real effective floor today (max of all APIs actually used)**: **macOS 15.0** — caused by a single SwiftUI scene modifier, `defaultLaunchBehavior(.suppressed)`. Everything else used tops out at macOS 14.
- **Dependency is NOT the blocker**: KeyboardShortcuts 2.4.0 declares `.macOS(.v10_15)`. The limiter is Relay's own SwiftUI architecture.
- **12.7 is technically possible but requires an AppKit shell rewrite** (MenuBarExtra→NSStatusItem, Window scene→NSWindow, SMAppService→legacy login-item helper, plus replacing the whole `@Observable` layer). Not advisable for a single-dev unsigned agent.
- **Recommended target: macOS 14.0** (sweet spot, ~1 file touched). macOS 13.0 is achievable at the cost of an Observation→ObservableObject rewrite.

---

## 1. Hard floor from dependencies

### KeyboardShortcuts (sindresorhus/KeyboardShortcuts), pinned 2.4.0

- `Package.resolved`: revision `1aef855…`, version `2.4.0`
  (`Relay/Relay.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:8-11`)
- `Package.swift` of the resolved checkout declares:
  ```
  // swift-tools-version:6.1
  platforms: [ .macOS(.v10_15) ]
  ```
  (`~/Library/Developer/Xcode/DerivedData/Relay-…/SourcePackages/checkouts/KeyboardShortcuts/Package.swift:1,7-9`)

**Conclusion**: the dependency's declared minimum is **macOS 10.15**, far below 12.7 — it imposes **no floor**. Git history shows the package has targeted 10.15 for years (commit `04b8db6 "Target macOS 10.15"`), so no older KeyboardShortcuts version is needed to go lower.

**Caveat**: `swift-tools-version:6.1` means the package needs a recent *build toolchain* (Xcode 16/26-era). That constrains the developer's Xcode, **not** the app's deployment target — unrelated to how low macOS the app can ship to.

---

## 2 & 3. Version-gated API sweep (grouped by required macOS)

**No `@available` / `if #available` / `@available(macOS 26…)` guards exist anywhere in the codebase** — the code currently assumes everything is present (i.e., assumes 26.5). Every API below would become a compile error at a lower deployment target unless guarded or replaced.

**No macOS 26-only APIs found**: no `glassEffect` / `.glass` / `glassBackgroundEffect` / `backgroundExtensionEffect` / `scrollEdgeEffect` / `containerBackground`. Liquid Glass is entirely automatic (standard containers), so nothing 26-specific is coded.

### Requires macOS 15.0  (the current real floor)

| API | File:line | Replace-with for ≤14 |
|---|---|---|
| `.defaultLaunchBehavior(.suppressed)` (Scene modifier) | `RelayApp.swift:36`, `RelayApp.swift:50` | Drop modifier; suppress launch windows the pre-15 way — `LSUIElement=YES` agent already prevents auto-window; gate with `if #available(macOS 15, *)` or remove. |

### Requires macOS 14.0

| API | File:line | Replace-with for ≤13 |
|---|---|---|
| `@Observable` macro + `import Observation` | `AppModel.swift:10,13`; `BackupService.swift:12,40`; `LanguageService.swift:11,44`; `TargetAppResolver.swift:10,13`; `WindowMinimizer.swift:12,15`; `LaunchCoordinator.swift:10,13` (**6 types**) | `ObservableObject` + `@Published` |
| `@Environment(SomeType.self)` (Observable-in-Environment) | `ActivationConfigPicker.swift:13`; `ProfilesView.swift:13`; `DataSettingsView.swift:15,16`; `PersonalizationSettingsView.swift:14,15`; `BindingsDetailView.swift:15,16`; `GeneralSettingsView.swift:13,14`; `MenuBarContent.swift:12`; `BindingRow.swift:17,18` | `@EnvironmentObject` |
| `.environment(observableInstance)` injection | `RelayApp.swift:19,32,33,45-48` | `.environmentObject(...)` |
| `ContentUnavailableView` | `ProfilesView.swift:103`; `BindingsDetailView.swift:27` | Custom empty-state VStack |
| `.toolbar(removing: .sidebarToggle)` | `ProfilesView.swift:87`; `SettingsRootView.swift:49` | Remove / guard (no pre-14 equivalent) |
| `onChange(of:) { old, new in }` (two-param closure) | `RelayApp.swift:100`; `ProfilesView.swift:79` | `onChange(of:perform:)` single-param (deprecated but available 11–14) |
| `NSApplication.shared.activate()` (zero-arg) | `RelayApp.swift:82`; `DataSettingsView.swift:292,307,319,331`; `MenuBarContent.swift:36,43`; `AppController.swift:122`; `DockIconController.swift:16` | `activate(ignoringOtherApps: true)` (already used at `RelayApp.swift:118`) |

### Requires macOS 13.0

| API | File:line | Replace-with for 12.7 |
|---|---|---|
| `MenuBarExtra` scene (incl. `isInserted:`) | `RelayApp.swift:17` | `NSStatusItem` + `NSMenu`/`NSPopover` (AppKit) — major rearchitecture |
| `Window(_:id:)` scene (×2) | `RelayApp.swift:30,43` | `NSWindow` + `NSWindowController` |
| `.windowResizability(.contentMinSize)` | `RelayApp.swift:37,51` | Set `NSWindow` min size manually |
| `SMAppService.mainApp` (login item) | `LoginItemService.swift:9,15`; refs `AppController.swift:90`, `AppDelegate.swift:33` | `SMLoginItemSetEnabled` + separate helper login-item bundle (deprecated path) |
| `NavigationSplitView` | `ProfilesView.swift:26`; `SettingsRootView.swift:44` | `NavigationView` (deprecated) or AppKit split |
| `LabeledContent` | `DataSettingsView.swift:52,66,69`; `PersonalizationSettingsView.swift:56,135`; `AboutSettingsView.swift:68`; `GeneralSettingsView.swift:27` | Manual `HStack { Text…; Spacer; … }` |

### Available at macOS 12.7 (no change needed)

`Table` (`GeneralSettingsView.swift:63`, macOS 12), `String(localized:)` (DataSettingsView/ProfilesView, macOS 12), `.tint` (macOS 12), `.popover` (`BindingRow.swift:44`, 10.15), `.help` (11), `ToolbarItem`/`.toolbar` (11), `CommandGroup(replacing: .appSettings)` (11), `NSImage(systemSymbolName:…)` (11), `NSWorkspace.openApplication(at:configuration:…)` (11), all AX/`NSRunningApplication`/`FrontmostTracker` APIs (≤11), `.fixedSize` (11).

---

## 4. Cost / scope tiers

Build is done with the macOS 26.5 SDK; lowering the deployment target means every API above the target must be `@available`/`if #available`-guarded with AppKit fallbacks, or removed.

### Tier A — macOS 14.0  ·  cost: TRIVIAL

- Only one API is above 14: `defaultLaunchBehavior` (2 call sites in `RelayApp.swift`).
- Action: drop or `#available`-guard the modifier; change deployment target in 4 pbxproj blocks.
- **Files touched: ~1** (RelayApp.swift) + project settings. **Risk: low.** `@Observable`, MenuBarExtra, Window, SMAppService, NavigationSplitView, ContentUnavailableView, toolbar(removing:) all remain valid.

### Tier B — macOS 13.0  ·  cost: MEDIUM–HIGH

- Tier A, **plus** replace the entire Observation layer:
  - 6 `@Observable` types → `ObservableObject`/`@Published`
  - ~10 UI files: `@Environment(Type.self)` → `@EnvironmentObject`; RelayApp injection `.environment` → `.environmentObject`
  - `ContentUnavailableView` ×2 → custom views
  - `.toolbar(removing: .sidebarToggle)` ×2 → remove/guard (cosmetic regression: system sidebar toggle reappears)
  - `onChange` two-param ×2 → single-param
  - `NSApplication.activate()` zero-arg (≈9 sites) → `activate(ignoringOtherApps:)`
- **Files touched: ~16–18.** **Risk: medium** — rewrites the single source of truth (`AppModel`) and every view's data binding; needs full manual re-test.

### Tier C — macOS 12.7 (user's ask)  ·  cost: HIGH (shell rewrite)

- Tier B, **plus** rebuild the AppKit shell:
  - `MenuBarExtra` → `NSStatusItem` + `NSPopover`/`NSMenu` hosting SwiftUI (the whole app entry is MenuBarExtra-based → significant rearchitecture of `RelayApp.swift`)
  - 2× `Window` scenes → `NSWindow`/`NSWindowController` (and re-wire `openWindow` env actions + `CommandGroup(.appSettings)` ⌘,)
  - `SMAppService` → `SMLoginItemSetEnabled` + a **separate helper login-item bundle** (deprecated; extra target, packaging, and the un-signed app makes this fragile)
  - `NavigationSplitView` ×2 → `NavigationView`/AppKit; `LabeledContent` (≈7) → manual layout; `windowResizability` → manual `NSWindow` min sizes
- **Files touched: ~20+ and 2 net-new AppKit subsystems (status item, window controllers, login-helper target).** **Risk: high** — touches every architectural pillar; large manual-test surface; the project's whole "SwiftUI-first, MenuBarExtra + Window" design (per CLAUDE.md) would be inverted.

---

## 5. Recommendation

**Lowest *realistic* deployment target: macOS 14.0** — and it is nearly free (one scene modifier). It preserves `@Observable` (the documented single-source-of-truth pattern), MenuBarExtra, the Window-based management UI, and `SMAppService`, all of which are load-bearing in the current architecture.

- **macOS 13.0** is a reasonable stretch if broader reach matters, but it costs a full Observation→`ObservableObject` migration across ~16 files — meaningful churn on the app's core state layer for incremental coverage.
- **macOS 12.7 is not advisable.** It requires replacing MenuBarExtra, the Window scenes, and the login-item mechanism with legacy AppKit equivalents — effectively a shell rewrite that contradicts the project's SwiftUI-first design, for a rapidly shrinking 12.x user base. The dependency does not block 12.7; Relay's own architecture does.

**Bottom line**: go to **macOS 14** now (cheap, safe). Reconsider 13 only if real users on 13.x appear. Skip 12.7.

## Caveats / Not Found

- API version floors above are from Apple's published availability (e.g. `@Observable`/`ContentUnavailableView`/`toolbar(removing:)` = macOS 14; `MenuBarExtra`/`Window`/`SMAppService`/`NavigationSplitView`/`LabeledContent` = macOS 13; `defaultLaunchBehavior` = macOS 15). The external web-search tool was unavailable this session, so these were not re-fetched live — verify against Apple docs before relying on the exact `.0` for any single API.
- `Info.plist` is auto-generated (`GENERATE_INFOPLIST_FILE`, `INFOPLIST_KEY_LSUIElement = YES`); there is no hand-set `LSMinimumSystemVersion` — Xcode derives it from `MACOSX_DEPLOYMENT_TARGET`, so only the build setting needs changing.
- **SF Symbols degrade safely**: the menu-bar icon picker lets users choose arbitrary symbols, but `resolvedIconName` validates via `NSImage(systemSymbolName:…)` and falls back to a default when nil (`RelayApp.swift:109-114`, `PersonalizationSettingsView.swift:227`). Symbols introduced after the target OS simply fall back — not a crash, but a cosmetic caveat on older systems.
- Did not attempt a trial build at a lowered target; counts are from static grep, so secondary compile errors (transitive availability) may surface during an actual Tier B/C build.
