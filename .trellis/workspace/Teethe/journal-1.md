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

