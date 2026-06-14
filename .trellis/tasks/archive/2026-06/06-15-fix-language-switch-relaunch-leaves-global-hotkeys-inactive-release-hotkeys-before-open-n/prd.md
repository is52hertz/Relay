# Fix: 切换语言重启可能让全局热键失效（重启前先释放热键）

## Goal

修复 PR #12 codex 审核报出的 P2：`LanguageService.relaunch()` 先 `open -n` 拉起新实例、再 `NSApp.terminate`，新实例在旧进程仍持有全局热键时注册，可能导致切语言后 UI 已是新语言但**全局热键失效**，直到再注册或手动重启。改动只在重启路径，不影响其它功能。

## Background（已核实根因）

- `relaunch()`（`LanguageService.swift:84-91`）顺序：`flushBeforeRelaunch()` → `open -n`（拉起新实例）→ `NSApp.terminate(nil)`。
- 新实例 `AppController.init`（`AppController.swift:69`）调 `registration.activate(model.activeProfile)` → 经 `KeyboardShortcuts` 调 Carbon `RegisterEventHotKey` 注册全局热键。
- 注册时**旧进程可能仍持有同一组全局热键**（terminate 是异步、尚未完成）。`KeyboardShortcuts` **吞掉 `RegisterEventHotKey` 失败**（见 `spec/app/system-integration.md`：系统级冲突不可检测），且此路径**无重试**。
- Carbon 跨进程同一热键的注册/交接语义不保证 → 新实例热键可能不灵，直到重新注册/手动重启。低频（切语言是一次性设置）、可恢复，但真实。

## Confirmed decisions（this turn）

- 现在修，走 Trellis fix 流程，提交到 `fix/profile-uiux` 更新 PR #12。[user]
- **修法**：消除「新旧进程同时持有全局热键」的重叠窗口 —— 在**旧进程** `open -n` **之前**调用 `registration.deactivateAll()`（`setShortcut(nil)+disable`，释放 Carbon 注册）。[self, user-approved]
- **接线方式**：把 `LanguageService` 现有的 `flushBeforeRelaunch` **泛化为 `beforeRelaunch: @MainActor () -> Void`**，由组合根 `AppController` 组合「flush + deactivateAll」两件副作用；`LanguageService` 不感知具体内容，沿用 P1 修复时的注入 seam。[self, user-approved]
- 不采用「等父进程退出再 open 的中转脚本」方案（对该 P2 过度工程，且引入 shell helper）。[self]
- 范围严格限定 `LanguageService.swift` + `AppController.swift`；不改热键注册逻辑本身。[self]

## Requirements

### R1 — 重启前释放全局热键
- `LanguageService` 将 `flushBeforeRelaunch` 重命名/泛化为 `beforeRelaunch: @escaping @MainActor () -> Void`（默认 `{}`），存为属性，在 `relaunch()` 中 `task.run()`（`open -n`）**之前**调用。
- `AppController`（`AppController.swift:46`）注入组合闭包：先 `model.saveNow()`（保留 P1 的 flush），再 `registration.deactivateAll()`。两者顺序不敏感，但都必须在 `open -n` 前完成。
- `registration` 在 `AppController.init` 中需对该闭包可见（局部变量 `registration` 已于 init 内创建，按现有 `[model]`/`[registration]` 捕获惯例捕获）。
- 不破坏 P1：`AppModel` 仍在 `open -n` 前同步落盘。

## Acceptance Criteria

- AC1：`relaunch()` 在 `open -n` 之前同时完成 `saveNow()`（落盘）与 `deactivateAll()`（释放热键）。
- AC2：旧进程释放热键后再拉起新实例，新实例注册时无旧进程占用 → 不存在重叠窗口。
- AC3：`LanguageService` 仍不依赖 `AppModel` / `HotkeyRegistrationService` 的具体类型（仅经 `@MainActor () -> Void` 闭包）；保持 `@MainActor @Observable`。
- AC4：改动仅限 `LanguageService.swift`、`AppController.swift`。
- AC5：`xcodebuild`（Debug / macOS）编译通过。

## Out of Scope

- 不改 `HotkeyRegistrationService` 的注册/重试逻辑、不加跨进程交接探测。
- 不引入等待父进程退出的中转脚本。
- 不动本地化文案 / 其它已合并代码。
