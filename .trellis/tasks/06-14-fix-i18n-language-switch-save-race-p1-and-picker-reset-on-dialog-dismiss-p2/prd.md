# Fix: i18n 语言切换的保存竞态（P1）与确认框非按钮关闭的选择器回退（P2）

## Goal

修复 PR #11（`feat/localization-i18n`）代码审核（codex）报出的两个真实缺陷，二者都在本轮本地化新增代码内，且都不影响其它功能：

- **P1（数据丢失竞态）**：切换语言重启时，新实例可能在旧实例 flush 之前读到旧 JSON，导致最后一次未落盘的编辑被覆盖丢失。
- **P2（选择器状态错位）**：重启确认框经 Esc / 点击对话框外部关闭时，选择器停留在未生效的目标语言，且无法再次触发确认。

## Background（已核实的根因）

### P1 — `Relay/Relay/Services/LanguageService.swift` `relaunch()`
- `AppModel.saveNow()`（`AppModel.swift:230`）取消去抖任务并**同步**原子落盘；它**只**接在 `willTerminate`（`AppController.swift:80-90`）。
- 正常编辑走 `scheduleSave()` 的 **400ms 去抖**（`AppModel.swift:219-227`）。
- `relaunch()` 当前顺序：先 `open -n` 拉起新实例 → 再 `NSApp.terminate(nil)`。新实例启动读盘时旧实例可能尚未 flush（仍在去抖窗口）→ 读到旧数据；旧实例 `terminate` 才 flush，新实例内存里却是旧数据，之后一保存即覆盖刚 flush 的编辑 → 丢数据。纯靠「新进程启动慢于 flush」的时序，非确定性。

### P2 — `Relay/Relay/UI/PersonalizationSettingsView.swift` `dialogPresented`
- `dialogPresented` setter 关闭分支只 `pending = nil`，**未重置 `selection`**；`selection = language.current` 仅写在「Cancel」按钮 action 里。
- 经 Esc / 点击对话框外部关闭时只走 setter（不走 Cancel action）→ `selection` 停在未生效目标语言；选择器显示「已选」，再点同一项因已是选中态不触发 `set`，确认框不再弹。

## Confirmed decisions（this turn）

- 走正式 Trellis 流程修这两个 bug + 编译验证 + 提交推送，更新 PR #11。[user]
- **P1 修法**：在 `open -n` **之前**同步 flush。`LanguageService` 不持有 `AppModel`，按组合根注入闭包的既有惯例（同 `model.hotkeysDidChange`）注入 `flushBeforeRelaunch` 闭包，保持 AppModel 不依赖 AppKit 的边界。[self, user-approved]
- **P2 修法**：把 `selection = language.current` 回退移进 `dialogPresented` setter 的关闭分支，覆盖所有关闭路径（Esc / 点外部 / Cancel）；Cancel 按钮里重复的那行可去掉。[self, user-approved]
- 范围严格限定这两处缺陷，不顺手改其它本地化代码。[self]

## Requirements

### R1 — 修复 P1 保存竞态
- `LanguageService` 新增注入式 flush 钩子：`init(flushBeforeRelaunch: @escaping @MainActor () -> Void = {})`，存为属性。
- `relaunch()` 在 `task.run()`（`open -n`）**之前**调用 `flushBeforeRelaunch()`。
- `AppController`（`AppController.swift:46`）改为 `LanguageService(flushBeforeRelaunch: { [model] in model.saveNow() })`。
- 不得让 `AppModel` 或 `LanguageService` 引入对彼此具体类型的依赖（仅闭包）。

### R2 — 修复 P2 选择器回退
- `dialogPresented` setter 关闭分支同时 `pending = nil` 与 `selection = language.current`。
- 移除 Cancel 按钮 action 内现已冗余的 `selection = language.current`（避免双写、保持单一回退点）。
- 「Restart Now」「Cancel」「Esc / 点外部」三条路径下选择器回显都正确（生效后显示新语言，取消/关闭显示当前生效语言）。

## Acceptance Criteria

- AC1：改 binding/profile 后**立即**切换语言并确认重启，新实例加载的配置包含该次编辑（无丢失）。flush 在 `open -n` 之前发生。
- AC2：弹出重启确认框后按 Esc / 点对话框外部关闭，选择器回到当前生效语言；可再次选目标语言并重新弹出确认框。
- AC3：「Restart Now」仍正常切换并重启；「Cancel」仍回退到当前语言。
- AC4：改动仅限 `LanguageService.swift`、`PersonalizationSettingsView.swift`、`AppController.swift` 三个文件；其它本地化功能不受影响。
- AC5：`xcodebuild` 编译通过（Debug，目标 macOS）。

## Out of Scope

- 不改 String Catalog / 翻译内容、不动其它本地化代码路径。
- 不重构持久化/去抖机制本身（仅在重启前补一次同步 flush）。
- 不改 PR base / 合并策略（仍 `feat/localization-i18n → fix/profile-uiux`）。
