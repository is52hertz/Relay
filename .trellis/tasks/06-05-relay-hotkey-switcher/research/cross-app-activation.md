# Research: 跨 App 激活/隐藏/启动 — Relay 焦点引擎

Verified 2026-06-05 via Apple Docs MCP（AppKit）。**全部公开 API，无需 Accessibility/私有 API。**

## 状态判定
- 运行集合：`NSWorkspace.shared.runningApplications` 或 `NSRunningApplication.runningApplications(withBundleIdentifier:)`。空 = 未运行。
- 前台：`NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target` → frontmost。
- 隐藏：`runningApp.isHidden`（KVO 可观察）。
- ⚠️ **「运行但无可见窗口」无法用公开 API 精确判定**（需 AX 数窗）。→ 统一兜底：unhide + activate + 再 `openApplication`(reopen)。已在 P1-8 接受。

## 激活（现代协作式，macOS 14+）
- `NSRunningApplication.activate(from:options:)` — **推荐**，协作式激活；`from:` 传 `NSRunningApplication.current`。
- 旧 `activate(options: .activateIgnoringOtherApps)` 在 14 起弃用，避免。
- 辅助：`NSApplication.yieldActivation(toApplicationWithBundleIdentifier:)`（让出激活，可选）。
- 由用户热键（用户操作）触发，抢焦点正常，无 focus-stealing 阻拦。

## 隐藏/取消隐藏
- `runningApp.hide()` / `runningApp.unhide()`（公开，非 AX）。
- 监听 `NSWorkspace.didUnhideApplicationNotification` / `didHideApplicationNotification`（如需）。

## 启动 / reopen（建窗）
- 启动未运行：`NSWorkspace.shared.openApplication(at: url, configuration:)`（异步，completion/async）。
- 运行但无窗：再次 `openApplication` 触发 App 的 reopen（`applicationShouldHandleReopen`），多数 App 会建窗；**不保证所有 App**（诚实）。

## FrontmostTracker（模型 A，落实 P1-7）
- 订阅 `NSWorkspace.shared.notificationCenter` 的 `didActivateApplicationNotification`。
- 维护 `(current, previous)`：新激活 App ≠ current 时 `previous = current; current = newApp`；**排除 Relay 自身 bundleId**。
- 启动用 `NSWorkspace.shared.frontmostApplication` 初始化 current。
- 纯事件驱动、低频、O(1)、零空闲开销。

## 解析 App / 图标（落实 P1-12）
- 路径解析：`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`；失败回退 `lastKnownPath`；都失败 → missing。
- 图标：`NSWorkspace.shared.icon(forFile: path)`（运行时取，不入库），NSCache 缓存。

## 沙箱注意
- 以上跨 App 控制在**关闭沙箱**（已定 P0-1）下完整可用；沙箱开启会受限——故 PR1 关沙箱。
