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

