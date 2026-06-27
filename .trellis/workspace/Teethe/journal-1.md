# Journal - Teethe (Part 1)

> AI development session journal
> Started: 2026-06-05

---

## 2026-06-05 — Relay 立项 + PR1 骨架

**任务**: `06-05-relay-hotkey-switcher`（planning → in_progress）

**设计收敛（全部经用户确认，记于 prd.md ADR）**:
- P0：关沙箱 / 部署 26.5 / 全局热键用 KeyboardShortcuts / v1 单一 active profile / 默认 FocusBehavior=Return to Previous 可按 binding 覆盖。
- P1：FocusBehavior 收敛 4 种（含矩阵）；Previous = 模型 A（全局动态 (current,previous)，等价 ⌘Tab MRU 深度2，零空闲开销）；无窗兜底；菜单栏 agent；菜单栏切 profile + 登录启动(默认关) 进 v1，热键切/前台自动切延后；冲突检测组内可靠+系统 best-effort；Codable JSON 持久化。

**文档核对（research/，不臆造 API）**: KeyboardShortcuts（setShortcut/getShortcut/disable/enable、carbon 码 init、Binding 模式 Recorder 不自动注册、**注册失败不暴露**）；Liquid Glass（glassEffect/GlassEffectContainer 等确认存在，v1 靠自动采用）；跨 App 激活（activate(from:)/hide/unhide、openApplication reopen、FrontmostTracker）。

**PR1 落地**: pbxproj 关沙箱+LSUIElement；新增 Models/Persistence/State/UI；删 ContentView；RelayApp 改 MenuBarExtra+Settings。`xcodebuild build` 绿；`RelayTests` 3 用例全过。坑：默认实参不能调 @MainActor init（移进 init body）。

**下一步**: PR2 焦点引擎 + FrontmostTracker。
**遗留**: 项目级 Swift spec 未写（`.trellis/spec` 仍 web 占位）。

## 2026-06-05 — PR2 焦点引擎

主会话直接实现（未派 sub-agent：harness 限制冷启动 spawn，且主会话已持全量 PR1 上下文；已向用户说明可改回 Trellis sub-agent 流）。

- `AppActivationDecision`(nonisolated 纯决策)：运行态合并 notInstalled/notRunning/running/frontmost；decision = state × FocusBehavior（与 PRD 矩阵一致）。
- `TargetAppResolver`：bundleId→URL 回退 path、运行实例、图标(按 path 缓存)。
- `FrontmostTracker`(模型 A)：didActivateApplicationNotification 维护 (current,previous)、排除自身、main 队列 + assumeIsolated。
- `AppActivationService`：runtimeState 判定 + perform；launch/focus 统一 `bringToFront`(unhide+openApplication 兜底无窗)；returnToPrevious 无 previous→hide；activate(from:.current) 协作式激活。
- 测试：`AppActivationDecisionTests` 覆盖 16 组合。`xcodebuild test` 全绿（7 用例）。

**下一步**: PR3 KeyboardShortcuts SPM 接入 + 注册/切换/冲突。

## 2026-06-05 — PR3 热键注册 + Profile 切换

- **手工把 KeyboardShortcuts(SPM) 加进 .xcodeproj**：pbxproj 5 处编辑（PBXBuildFile / Frameworks phase / target packageProductDependencies / PBXProject packageReferences / 新增 XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency 两节；ID 前缀 `DEADBEEF…`）。`xcodebuild -resolvePackageDependencies` → 2.4.0 解析成功。
- `Hotkey+KeyboardShortcuts`：Hotkey↔Shortcut(carbon 码) 互转 + displayString。
- `HotkeyConflicts`(纯)：组内重复 binding 检测（2 单测）。
- `HotkeyRegistrationService`：仅注册 active profile（动态 Name(binding.id)、setShortcut+enable+onKeyDown）；切换 deactivateAll(set nil/disable)；handler 每 Name 装一次读 bindingsByName；组内重复只注册第一个。
- `AppController` 组合根接线 model.hotkeysDidChange→registration.activate；RelayApp 改用 controller。AppModel 加 `@ObservationIgnored hotkeysDidChange` 钩子保持无 AppKit 依赖。
- 加 `.gitignore`（Xcode/SPM；保留 Package.resolved）；`git rm --cached` xcuserstate。
- 坑：MEMBER_IMPORT_VISIBILITY 开启 → 用 UUID.uuidString 的文件需显式 `import Foundation`。
- `xcodebuild test` 全绿（9 用例）。

**下一步**: PR4 设置 UI（绑定行 + 录入器 + 行为 Picker + 徽章 + 增删 App）。

## 2026-06-05 — PR4 设置 UI

- AppModel 加 binding CRUD（add/update/remove(Set)/setBindings + didMutateProfile→active 则重注册）；视图把 onDelete/onMove 解析成调用，AppModel 保持无 SwiftUI。
- TargetAppResolver 改 @Observable（stored 属性 @ObservationIgnored 防更新循环）+ makeTargetApp(from url)；经 environment 注入。
- SettingsRootView：Profile 侧栏（contextMenu 设 active/改名(alert+TextField)/删）+ active 标识(bolt)。BindingsDetailView：增 App(NSOpenPanel /Applications)、排序、空状态、active toolbar。BindingRow：图标/失效/冲突徽章/录入器/行为 Picker。
- **关键坑**：KeyboardShortcuts 2.4.0 SwiftUI Recorder 只有 Name 模式（自动注册+UserDefaults），无 binding 模式 → 自绘 `ShortcutRecorder`(NSViewRepresentable + 本地 addLocalMonitorForEvents(.keyDown) + Shortcut(event:) 解析)；保持 SoT=我方 JSON、仅 active profile 注册。Esc 取消 / Delete 清空。
- build+test 绿(9)；`open Relay.app` smoke：启动、常驻、退出正常。

**下一步**: PR5 登录启动 + Dock 图标开关 + 通用设置 + 打磨。

## 2026-06-05 — PR5 收尾（PRD 完成）

- `LoginItemService`(SMAppService 幂等 register/unregister)、`DockIconController`(activationPolicy)。
- `GeneralSettingsView`(登录启动/Dock/默认行为，写 AppModel.settings)、`SettingsContainer`(Settings 分页 Profiles+General)。RelayApp Settings 改用容器。
- AppModel 加 `settingsDidChange` 钩子；AppController 接 loginItem/dockIcon 并启动同步。
- **两个真崩溃修复**：
  1. 测试宿主崩溃（SMAppService 在 XCTest 宿主）→ AppController 启动副作用用 `XCTestConfigurationFilePath` 判定跳过。
  2. 真机启动崩溃 `DockIconController:13 nil`：AppController 在 `@State` 初始化期早于 NSApp → 改 `NSApplication.shared`（非 `NSApp`）。
- 验证：`xcodebuild test` 绿(9)、直接跑二进制 smoke 无崩溃常驻。

**状态**: PRD 全部 5 PR 完成。待办：项目级 Swift spec bootstrap；可选 finish-work。

## 2026-06-05 — 手测第一轮修复

用户真机手测报告，定位到两个根因 + 几个小修：
- **根因 1：管理 UI 放在 `Settings` 场景** → Settings 不支持自定义 toolbar（Add App/Profile、Set as Active 全失效）、切激活策略时窗口异常。**改为真正的 `Window`(id main) + `.defaultLaunchBehavior(.suppressed)`**；菜单栏「Open Relay…」openWindow+activate。修复 1.2/4.1–4.6/5.x/7.2/8.4 一连串。
- **根因 2：Return to Previous 用 `activate(from: .current)`** → agent 非前台时协作激活静默失败（3.3/3.4 切不回）。**改用 `openApplication(at: previous.bundleURL)`**（与 launch/focus 同路径）。
- 小修：BindingRow 右键 Remove（1.3）；菜单栏 active Profile 显式 checkmark（0.2）；DockIconController 切策略后 `activate()` 防窗口隐藏（7.1）。
- 澄清：1.5 改名仍识别=正确（bundleId 不变）；6.2 是 shell 引号假报（路径含空格）。
- build+test 绿(9) + smoke 启动正常。待用户复测。

## 2026-06-05 — 手测第二轮（32/36 过）+ 录入器修复

复测：核心全过（Return to Previous、Profile 切换、Dock 等）。剩余：
- 用户指出真痛点：**录制时按下组合会触发已注册的全局热键（启动别的 App）**，导致重复组合根本录不进、连带冲突 Warn 不可达。
- 修：`ShortcutRecorder` 录制期间 `KeyboardShortcuts.isEnabled=false`，stop()/dismantleNSView 恢复 true。
- 决策：保留冲突 Warn（修好录入器后重复组合可录入 → 第二个静默跳过，Warn 是唯一提示）。[user 同意修录入器；Warn 去留待最终拍板，暂留]
- 6.2 仍是 shell tilde-in-quotes 假报（配置确在 ~/Library/Application Support/cn.Teethe.Relay/config.json）。
- build+test 绿(9) + smoke 正常。

**状态**: 功能全绿，准备 finish-work。



## Session 1: Relay v1 — 类 Thor 全局应用快捷切换器（PR1–PR5 + 两轮手测修复）

**Date**: 2026-06-05
**Task**: Relay v1 — 类 Thor 全局应用快捷切换器（PR1–PR5 + 两轮手测修复）
**Branch**: `feat/relay-mvp`

### Summary

需求审计→PRD/ADR→分5个PR实现：模型/持久化/AppModel(SoT)、焦点引擎(纯决策+模型A FrontmostTracker)、KeyboardShortcuts接入+按active profile注册+组内冲突、设置UI(自绘录入器)、登录启动/Dock/通用设置。两轮真机手测修复：管理UI移到Window(Settings不支持toolbar)、Return-to-Previous改openApplication、录制时停用全局热键、冲突提示改即时popover。全程build+RelayTests(9)绿。沙箱关、agent(LSUIElement)、目标macOS26.5、无付费账号本机自用。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `a7576a4` | (see git log) |
| `5e57290` | (see git log) |
| `b4bed56` | (see git log) |
| `ab09602` | (see git log) |
| `999888d` | (see git log) |
| `72cdb8f` | (see git log) |
| `8887af4` | (see git log) |
| `6ab4a49` | (see git log) |
| `b671a01` | (see git log) |
| `4545e5d` | (see git log) |
| `f9c0876` | (see git log) |
| `ab84607` | (see git log) |
| `dfe4fea` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: AGENTS.md 补全 + .trellis/spec 重塑为 Swift/macOS 规范

**Date**: 2026-06-05
**Task**: AGENTS.md 补全 + .trellis/spec 重塑为 Swift/macOS 规范
**Branch**: `feat/relay-mvp`

### Summary

补全 AGENTS.md 的 Product/Project Phase/Coding Standards/Trellis 占位（summary 语言设为中文）。完成 00-bootstrap-guidelines：把 .trellis/spec 从 web 模板(backend/frontend)重塑为贴合 Relay 真实代码的 Swift 层 swift/app/ui（+顶层 index，保留 guides），规则全部 source-backed、无占位。提交 codex 配置更新。推送 main 与 feat/relay-mvp 到 origin。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `77134d0` | (see git log) |
| `c03d9b0` | (see git log) |
| `b59d19d` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: PR#1 审查修复 + Codex 独立验证

**Date**: 2026-06-07
**Task**: PR#1 审查修复 + Codex 独立验证
**Branch**: `feat/relay-mvp`

### Summary

修复 PR#1 四条 P2 审查意见：(1) AppController 监听 willTerminate 调 saveNow 退出前 flush 去抖保存；(2) bringRunningAppToFront 改 bundleURL/bundleID 解析 + openApplication，移除 agent 下静默失败的 activate() 兜底；(3) returnToPrevious 加 !isTerminated，previous 已退出退化为 hideTarget；(4) ShortcutRecorder 监听 didResignActive，录制中切走即取消并恢复 KeyboardShortcuts.isEnabled。逐条回复 PR 评论并推送。Codex gpt-5.5 xhigh 独立验证：0 blocker/0 should-fix，2 nit；采纳 nit 1（bringRunningAppToFront 返回 Bool + 再判 isTerminated，URL 解析失败也退化 hideTarget），跳过 nit 2（冗余/外观）。构建与 RelayTests 全绿。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `df81339` | (see git log) |
| `f0569c3` | (see git log) |
| `0eec022` | (see git log) |
| `d819bd9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: Apply Icon Composer app icon

**Date**: 2026-06-08
**Task**: Apply Icon Composer app icon
**Branch**: `main`

### Summary

Wired user-authored Icon.icon as Relay's app icon: moved into the filesystem-synchronized Relay/Relay/ folder, set ASSETCATALOG_COMPILER_APPICON_NAME=Icon (Debug+Release), removed empty AppIcon.appiconset placeholder. Verified via Debug build (actool -> Icon.icns, CFBundleIconName=Icon). Added relative root symlink Icon.icon -> Relay/Relay/Icon.icon for root-path access.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `6aa0c8a` | (see git log) |
| `9710c69` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: Generic branch policy in AGENTS.md

**Date**: 2026-06-08
**Task**: Generic branch policy in AGENTS.md
**Branch**: `main`

### Summary

Removed stale active-branch reference from AGENTS.md Project Phase (feat/relay-mvp already merged to main) and added a branching convention: per-feature work uses feat/* branches; merged feat/* branches are kept as historical archives and never deleted.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8d60555` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: Per-state ActivationConfig (redesign FocusBehavior)

**Date**: 2026-06-09
**Task**: Per-state ActivationConfig (redesign FocusBehavior)
**Branch**: `feat/per-state-activation-config`

### Summary

Replaced 4-preset FocusBehavior with a global, user-editable per-state ActivationConfig (General Table + ± + two-step delete confirm). Three per-state action enums; new launchWithoutFocus/quit; Background column + Frontmost Minimize are disabled placeholders; configResolver resolves live at key-down. No migration (app unreleased). Build + RelayTests 10/10 green. Manual UI test surfaced 3 Table polish issues (deselect-on-outside-click, rename-end-on-outside-click, picker text centering); a fix attempt was rolled back and the issues filed as GitHub #3/#4/#5 for follow-up. Feature lives on feat/per-state-activation-config (44f9736), not yet pushed.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `44f9736` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 7: Background-editable + minimize via Accessibility

**Date**: 2026-06-09
**Task**: Background-editable + minimize via Accessibility
**Branch**: `feat/background-minimize-accessibility`

### Summary

Made the placeholder actions real: Background column editable; minimize (Frontmost+Background) via a new @MainActor WindowMinimizer (sole AX entry, kAXMinimizedAttribute) with lazy permission (prompts only on selecting Minimize) and safe degradation (no-op + once-per-session NSAlert when untrusted). Refinements from manual test: showWithoutFocus = raise-then-return-focus (D6); focus opportunistically un-minimizes when already trusted (D7); runtimeState treats an active app with no visible window (all minimized/zero) as background so it restores via the focus path (D8). AppActivationDecision stays pure; AGENTS.md relaxed to a general lazy-permission principle. Build+RelayTests green (11); trellis-check clean. Added Test/relay-minimize-test-checklist.html. Known limitation: untrusted + all-minimized-without-switching won't restore. On feat/background-minimize-accessibility, not yet pushed.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `d0fed3a` | (see git log) |
| `1a8516b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 8: Split Profiles main window and General Settings scene

**Date**: 2026-06-10
**Task**: Split Profiles main window and General Settings scene
**Branch**: `feat/profiles-window-settings-split`

### Summary

Split the single TabView Window into a Profiles main Window plus a real Settings scene (General only, system Cmd+, / Settings menu). Added launch-source awareness: login-item launch stays menu-bar-only, explicit launch opens the Profiles window. Forced NSToolbar so the Settings sidebar extends under the traffic lights. Cleaned up old SettingsContainer/SettingsRootView naming, synced spec + notice, and added reset-relay-state.sh for first-launch testing.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8af24f4` | (see git log) |
| `dcaa557` | (see git log) |
| `694c154` | (see git log) |
| `007df01` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 9: Pin Profiles sidebar (always visible, no collapse toggle)

**Date**: 2026-06-10
**Task**: Pin Profiles sidebar (always visible, no collapse toggle)
**Branch**: `feat/profiles-sidebar-always-visible`

### Summary

Fixed the unnatural sidebar hide/show transition in the Profiles main window by pinning the sidebar: NavigationSplitView now uses columnVisibility .constant(.doubleColumn) and removes the system sidebar-toggle, mirroring the verified SettingsRootView pattern. This eliminates the SwiftUI collapse reflow where the leading toolbar buttons jump beside the traffic lights into a glass capsule. Add Profile and detail toolbars unchanged; single-file change in ProfilesView.swift plus a swiftui.md spec sync. Build + RelayTests (11) green; trellis-check clean.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ce9ffad` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 10: Profile sidebar keyboard shortcuts + active-bolt styling

**Date**: 2026-06-12
**Task**: Profile sidebar keyboard shortcuts + active-bolt styling
**Branch**: `fix/profile-uiux`

### Summary

Added keyboard-shortcut glyph hints to Profiles sidebar context menu (⌘↩ Set as Active, ↩ Rename, ⌫ Delete) aligned with real handlers; bindings detail list gains row selection + .onDeleteCommand to remove the selected binding via Delete/⌫, with BindingRow Remove showing ⌫; active-profile bolt switched to .body sizing. Verified via xcodebuild (BUILD SUCCEEDED).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `27da131` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 11: Localization (zh-Hans/zh-Hant) + Personalization settings tab

**Date**: 2026-06-14
**Task**: Localization (zh-Hans/zh-Hant) + Personalization settings tab
**Branch**: `feat/localization-i18n`

### Summary

Localized Relay UI for zh-Hans/zh-Hant, added a Personalization settings tab for language selection, translated 'Record Shortcut' and localized preset behavior names. Added the 06-14 localization PRD + jsonl context.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0baf3f3` | (see git log) |
| `99ce032` | (see git log) |
| `0c9b185` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 12: Fix PR #11 review findings: language-switch save race (P1) + picker reset on dialog dismiss (P2)

**Date**: 2026-06-14
**Task**: Fix PR #11 review findings: language-switch save race (P1) + picker reset on dialog dismiss (P2)
**Branch**: `feat/localization-i18n`

### Summary

Fixed two codex review findings on PR #11. P1: LanguageService now flushes AppModel synchronously (injected flushBeforeRelaunch closure from AppController) before 'open -n', closing a data-loss race. P2: moved picker revert into the dialogPresented binding's close branch so all dismissal paths reset selection. Recorded the relaunch-flush invariant in the system-integration spec. Build passed; codex re-review (commit b4efcc8) found no major issues.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `84b88e6` | (see git log) |
| `005a2dd` | (see git log) |
| `b4efcc8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 13: Fix PR #12 review finding: release global hotkeys before language-switch relaunch (P2)

**Date**: 2026-06-15
**Task**: Fix PR #12 review finding: release global hotkeys before language-switch relaunch (P2)
**Branch**: `fix/profile-uiux`

### Summary

Fixed a codex P2 on PR #12: LanguageService.relaunch() launched the replacement instance before releasing global hotkeys, so the new process could register Carbon hotkeys while the old one still owned them (KeyboardShortcuts swallows registration failures, no retry) -> hotkeys could be dead after a language switch. Generalized the pre-relaunch hook (flushBeforeRelaunch -> beforeRelaunch); AppController now composes model.saveNow() + registration.deactivateAll() before open -n. Updated the relaunch invariant in the system-integration spec. Build passed; codex re-review (a953eda) found no major issues. Also cherry-picked session-12 bookkeeping (06-14-fix archive + journal) onto fix/profile-uiux to repair branch divergence so main gets a complete journal via PR #12.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `f8dfc90` | (see git log) |
| `aa309df` | (see git log) |
| `a953eda` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 14: README group (en/zh-Hans/zh-Hant) + GPL LICENSE + first preview release v0.1.0-preview.1

**Date**: 2026-06-15
**Task**: README group (en/zh-Hans/zh-Hant) + GPL LICENSE + first preview release v0.1.0-preview.1
**Branch**: `main`

### Summary

Authored a 3-language README group (English authoritative + zh-Hans + zh-Hant), added GPL-3.0 LICENSE (FSF canonical, copied from sibling VideoPlayer repo), and docs/icon.png (user-provided 512x512). Feature claims traced to code. Merged via PR #13. Then published the first preview GitHub release v0.1.0-preview.1 (pre-release, target main): Release build -> codesigned Relay.app -> Relay-v0.1.0-preview.1.dmg (3.4MB, verified) -> gh release create with concise English notes (feature summary + launch instructions). Decisions: 3 languages (match app localization), tag v0.1.0-preview.1, attach .dmg, version-less Swift badge (project uses Swift 5 language mode).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ec289ed` | (see git log) |
| `7a971ad` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 15: Personalization: customizable menu bar icon (SF Symbol presets + custom)

**Date**: 2026-06-15
**Task**: Personalization: customizable menu bar icon (SF Symbol presets + custom)
**Branch**: `feat/personalization-menu-bar-icon`

### Summary

Added a Menu Bar Icon picker to Settings → Personalization: 4 preset SF Symbols (swatch row, Style B) + a custom SF Symbol field with live NSImage validation (invalid never written; label falls back to default so the status item never goes blank). Persisted menuBarIconName in AppSettings with a backward-compat custom init(from:) (decodeIfPresent) to avoid wiping user data on legacy config.json; schemaVersion 2→3; added a legacy-decode unit test. MenuBarExtra label reads the setting live. Localized into zh-Hans/zh-Hant. Followed two-step confirmation; built 3 candidate control styles for live testing, user picked Style B; then tidied the custom row (borderless + placeholder).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `3ebaab7` | (see git log) |
| `d26e36b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 16: Frontmost cycle-windows-then-hide (opt-in FrontmostAction) + permission UX fix

**Date**: 2026-06-15
**Task**: Frontmost cycle-windows-then-hide (opt-in FrontmostAction) + permission UX fix
**Branch**: `feat/frontmost-cycle-windows-then-hide`

### Summary

新增可选 FrontmostAction.cycleWindowsThenHide：目标已在前台时连按热键循环抬升各窗口(最小化窗口先复原再抬升)、轮完再隐藏，复用 WindowMinimizer 公开 AX(无私有 API)、内存循环状态机经 FrontmostTracker 失焦重置、无 Accessibility 时安全降级为 hide。更新 system-integration.md 记录 AX 窗口管理例外。手测发现并修复两处权限 UX 缺口：降级提示文案通用化(不再误报最小化)、编辑器选轮换也懒申请权限。三语本地化齐全，build+RelayTests 均绿。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1eeed1e` | (see git log) |
| `f265c48` | (see git log) |
| `6b0b367` | (see git log) |
| `95686d8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 17: Data management: backup / restore / reset + rolling snapshots (with live list & hover delete)

**Date**: 2026-06-16
**Task**: Data management: backup / restore / reset + rolling snapshots (with live list & hover delete)
**Branch**: `feat/data-management-backup-restore-reset`

### Summary

新增设置「数据」pane：导出(版本化信封 .relaybackup)/导入(schemaVersion 闸门 + 损坏安全报错)/重置,均经新增 AppModel.replaceConfiguration(净化悬空引用 + 触发钩子 + 立即保存)。自动滚动快照(Backups/ 保留10份)作 reset/import 前安全网,DispatchSource 目录监听让列表实时(监听收敛到 pane 可见期,fd 安全)。每条快照可恢复/Finder 显示/悬停显露红色删除按钮(滑入动画)。BackupService Foundation-only 可单测,面板留 UI 层,备份仅含 AppConfiguration(语言/登录属偏好澄清)。更新 architecture.md;手测 29/30(1.4 为措辞已修正);新增 BackupService/replaceConfiguration 单测全绿;附手动测试清单 HTML。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1a22267` | (see git log) |
| `3225fa0` | (see git log) |
| `c5122d3` | (see git log) |
| `a2cf376` | (see git log) |
| `6c9f146` | (see git log) |
| `9691d77` | (see git log) |
| `35bb910` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 18: Settings About pane + Personalization Language reorder

**Date**: 2026-06-16
**Task**: Settings About pane + Personalization Language reorder
**Branch**: `feat/settings-about-page`

### Summary

新增设置「关于」pane：App 图标(applicationIconImage)+Relay+bundle 版本(1.0 (1),非硬编码)+简介+GitHub 链接+协议 GPL-3.0 链接+KeyboardShortcuts(MIT)致谢+© 2026 Teethe。纯静态只读、无模型/持久化/网络改动,三语本地化(Version %@ (%@) 两占位符在 zh 译文保留),版本格式化抽成语言无关单测。另把个性化面板的「语言」分区移到第一位(inline 小改)。build+RelayTests 全绿,trellis-check 0 问题。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `8bc33eb` | (see git log) |
| `495d5ad` | (see git log) |
| `d5d5214` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 19: Menu-bar icon visibility toggle + always-on global toggle hotkey

**Date**: 2026-06-16
**Task**: Menu-bar icon visibility toggle + always-on global toggle hotkey
**Branch**: `feat/settings-about-page`

### Summary

新增菜单栏图标显隐开关(showMenuBarIcon)+常驻全局切换热键(menuBarToggleHotkey,Carbon 码),schemaVersion 3→4 向后兼容。引入第二类常驻 app 命令热键注册(AppCommand,切 Profile 不被 deactivateAll 清除,仅经 KeyboardShortcuts 无全局监听)。防锁死三层:逐次守卫 MenuBarIconLockout + 清热键自动恢复 + replaceConfiguration 批量导入重申不变量(review 发现并堵)。UI 在个性化 pane(隐藏开关 + ShortcutRecorder),三语本地化。手测暂时通过。补记:本应在 about 任务前 finish,实际在 about 分支补跑,记账落 PR #18,无碍。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `a99a06d` | (see git log) |
| `3247f83` | (see git log) |
| `76c39dd` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 20: GitHub CI release pipeline (auto-release on main merge) + v1.0

**Date**: 2026-06-27
**Task**: GitHub CI release pipeline (auto-release on main merge) + v1.0
**Branch**: `feat/ci-release-pipeline`

### Summary

搭好 CI/Release 管道（macos-26 托管，未签名 .zip+.dmg，合并 main 即发版，版本 bump 发正式版/同版发 prerelease），PR build-only 门禁，发布首个正式版 v1.0，release notes 改英文分段式并加 paths-ignore。

### Main Changes

### Main Changes

- 新增 GitHub Actions CI/Release 管道（此前仓库无任何 workflow）：
  - `release.yml`：`push: main` → 托管 `macos-26` 构建未签名 Relay（Release）→ `ditto` 打 `.zip` + `hdiutil` 打 `.dmg` → `softprops/action-gh-release` 发版。版本取自 `MARKETING_VERSION`。同版本首次→正式版 `v<ver>`（latest），后续→prerelease `v<ver>-<run>`（幂等）。`concurrency: release-main` 串行。
  - `ci.yml`：`pull_request` → build-only 门禁。**不跑测试**：托管 runner OS 26.4 < 部署目标 26.5，宿主 XCTest 无法启动（research 实证）。
- 前置：把 Relay scheme 设为 shared 并提交 `Relay.xcscheme`（否则 CI 干净检出 `-scheme Relay` 解析不到）。
- 收尾打磨：release body 改英文分段式（Download / First launch，动态版本号）；加 `paths-ignore`（`.github/**`、`.trellis/**`、`docs/**`、`**/*.md`）让纯文档/配置/簿记不发版；加 `workflow_dispatch` 手动口子。已发布的 v1.0 body 经 API 同步更新。
- 全链路真机验证：ci.yml + release.yml 在 `macos-26` 跑通；首个正式版 **v1.0** 发布（含 .dmg + .zip，标 latest）；paths-ignore 经 PR#20 合并验证确实不触发发版。

### Git Commits

| Hash | Message |
|------|---------|
| `069316f` | ci: auto-release on main merge + PR build gate |
| `cc863da` | chore(task): add CI release pipeline PRD + research + jsonl |
| `366ae46` | ci: bump actions to Node 24 majors |
| `6194762` | ci(release): polish release notes + scope release triggers |

（另：本轮还有独立的 #17 P1 修复 `29b8634` 及 #15–#19 的合并提交，不属本任务。）

### Testing

- [OK] 本地：`xcodebuild build` Release 成功 + ditto/.zip + hdiutil/.dmg + `minos 26.5` 校验。
- [OK] 真机：ci.yml build-only 绿（含升级 checkout@v5 后无弃用告警）；release.yml 全步骤绿。
- [OK] 产物：v1.0 含 `Relay-1.0.dmg`(3.37MB) + `Relay-1.0.zip`(2.91MB)，prerelease=false、latest。
- [OK] paths-ignore：PR#20（纯 .github + .md）合并后无 release run 触发。

### Status

[OK] **Completed**

### Next Steps

- README 三语仍写"signed with a personal Apple Development certificate"，与未签名 CI 产物不符，待更正。
- #15/#16 的 3 个 P2（cycle 游标重置 / 快照同秒撞名 / 恢复时悬空 binding.configID）仍未修。


### Git Commits

| Hash | Message |
|------|---------|
| `069316f` | (see git log) |
| `cc863da` | (see git log) |
| `366ae46` | (see git log) |
| `6194762` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
