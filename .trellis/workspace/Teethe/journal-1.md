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

