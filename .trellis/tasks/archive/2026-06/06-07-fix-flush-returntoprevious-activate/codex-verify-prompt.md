# 独立验证请求（author≠reviewer）

你是 macOS / Swift / AppKit 资深审查者。下面是 Relay（一个 macOS 菜单栏 agent 应用：全局热键切换器）针对 PR#1 四条审查意见做的修复。请**独立、对抗性地**验证这些修复是否正确、是否符合 PRD 锁定的行为，以及**是否引入任何新问题**（并发、生命周期、retain cycle、线程隔离、AppKit 语义、边界条件、回归）。

Relay 关键事实：
- LSUIElement=YES 的后台 agent（默认无 Dock 图标）；沙箱关闭。
- 配置是内存唯一真相（AppModel，@MainActor @Observable），变更后 400ms 去抖保存；`saveNow()` 同步落盘（原子写）。
- 焦点引擎：纯决策层 `AppActivationDecision`（state×behavior→action，可单测，未改动）+ 副作用执行层 `AppActivationService`。
- `FrontmostTracker`（模型 A）：监听 `didActivateApplicationNotification` 维护全局 (current, previous)，排除 Relay 自身；**不监听 didTerminate**。
- 录入控件 `ShortcutRecorder` 用 local NSEvent monitor 捕获组合键，录制期间 `KeyboardShortcuts.isEnabled=false` 全局停用热键。

## PRD 锁定边界（必须符合）
1. FocusBehavior 矩阵「目标已在前台 + Return to Previous」→ 切回 previous app。
2. Return to Previous 共同边界：**previous 已退出/为空 → 退化为 hide 目标**；previous 是 Relay → 跳过（由 FrontmostTracker 排除）。
3. 跨 App 前台化：基线代码统一用 `NSWorkspace.openApplication(at:configuration:)`（activates=true），**不用** `NSRunningApplication.activate(from:)`——因为后台 agent 调用协作式激活会静默失败（既有 `bringToFront` 即此模式，PR reviewer 也认可）。
4. 退出 App 前必须 flush 去抖保存，避免丢失最后一次配置变更。

## 四处修复（diff 见 codex-verify.diff，与本文件同目录）

**修复1 — 退出 flush（AppController.swift）**：组合根监听 `NSApplication.willTerminateNotification`（`NotificationCenter.default`，`queue: nil` 同步执行 + `MainActor.assumeIsolated`）调 `model.saveNow()`。仅在 `!isRunningTests` 注册；deinit 注销。无 `NSSupportsSuddenTermination`（突然终止默认关闭）。

**修复2 — URL 兜底（AppActivationService.bringRunningAppToFront）**：`runningApp.bundleURL ?? urlForApplication(withBundleIdentifier:)` → openApplication；都解析不到则 return（**移除**了原来的 `runningApp.activate()` 兜底）。

**修复3 — isTerminated 退化（AppActivationService.returnToPrevious）**：判定加入 `!previous.isTerminated`，使「previous 已退出」退化为 `hideTarget`（而非被修复2的 URL 兜底重新拉起）。

**修复4 — 录制中切走（ShortcutRecorder）**：`start()` 监听 `NSApplication.didResignActiveNotification`（`queue: nil` + `MainActor.assumeIsolated`，`[weak self]`）→ App 失去前台即 `cancelIfRecording()`→`stop()` 恢复 `isEnabled`；observer 在 `stop()` 与 `deinit` 注销。

## 请回答
1. 每处修复是否**真正修好了**对应问题？是否符合上述 PRD 边界？
2. 是否引入**任何新问题/回归**？重点：retain cycle、observer 泄漏/重复移除、MainActor.assumeIsolated 是否在所有触发路径都确实在主线程、willTerminate/didResignActive 的投递时机与同步性、openApplication 对已隐藏 previous 的行为、TOCTOU、录制取消的 UX 边界。
3. 有无更稳妥/更符合 Apple API 语义的写法？
4. 给出明确结论：每处 = ✅通过 / ⚠️有顾虑 / ❌有缺陷，并按严重度（blocker/should-fix/nit）列出 findings 与具体 file:line 依据。

只做审查，**不要修改任何文件**。
