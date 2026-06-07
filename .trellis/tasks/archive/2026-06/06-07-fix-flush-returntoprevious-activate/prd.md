# PRD — 修复 PR#1 两条审查意见

## 背景
PR #1 (`feat/relay-mvp`) 收到两条 P2 审查意见，已核实均属实：
- `r3367161410`：退出 App 未 flush 去抖保存，可能丢失最后一次配置变更。
- `r3367161411`：`AppActivationService.bringRunningAppToFront` 在 `bundleURL == nil` 时回退到
  `runningApp.activate()`，与本方法注释「Relay 是后台 agent，协作式激活会静默失败」自相矛盾。

## 修复 1：退出前同步保存
- **机制**：在组合根 `AppController` 监听 `NSApplication.willTerminateNotification`，回调里调用
  `model.saveNow()`。覆盖所有正常退出路径（菜单 Quit 按钮、Window 聚焦时的标准 ⌘Q、注销/重启）。
- **关键实现细节**：observer 用 `queue: nil`，使回调在发帖线程（terminate 时即主线程）**同步**执行，
  保证 `saveNow()`（同步 IO）在进程退出前完成；用 `MainActor.assumeIsolated` 满足 `@MainActor` 隔离
  （照搬 `FrontmostTracker` 模式）。
- **守卫**：`!isRunningTests`，与现有系统副作用一致（避免测试宿主问题）。
- **不改** `MenuBarContent` 的 Quit 按钮——单一机制覆盖全部路径，避免重复保存。
- 项目无 `NSSupportsSuddenTermination` → 突然终止默认关闭 → `willTerminate` 可靠送达。
  无法覆盖强制退出/SIGKILL/崩溃（任何方案都无法覆盖，可接受）。

## 修复 2：returnToPrevious 的兜底改为解析 URL
- `bringRunningAppToFront`：URL 解析顺序 `runningApp.bundleURL`
  ?? `urlForApplication(withBundleIdentifier:)`；得到 URL → `openApplication`（与 launch/focus 同路径）。
- 无法解析时**不再调用** `activate()`（项目自身论断该调用对 agent 静默失败，并非真实兜底），直接放弃。
- 常见路径（`bundleURL != nil`）行为逐字不变，零回归。

## 验证
- `xcodebuild build` + 现有测试通过（无测试触及 saveNow/activation 路径）。

## 非目标
- 不引入 NSApplicationDelegateAdaptor / scenePhase 改造。
- 不改动持久化格式、热键、Dock/登录项逻辑。
