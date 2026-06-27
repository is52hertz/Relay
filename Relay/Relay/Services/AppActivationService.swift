//
//  AppActivationService.swift
//  Relay
//
//  焦点引擎的副作用执行层：判定运行态 → 用纯决策（AppActivationDecision）得到动作 → 执行。
//  大部分用公开 AppKit API；最小化经注入的 WindowMinimizer（唯一的 Accessibility 入口）。
//

import AppKit
import ApplicationServices

@MainActor
final class AppActivationService {
    private let resolver: TargetAppResolver
    private let frontmost: FrontmostTracker
    /// 最小化能力（唯一 AX 入口）；AX 信任态/降级在其内部处理（见 PRD D3/D4）。
    private let minimizer: WindowMinimizer
    private let workspace = NSWorkspace.shared

    /// cycleWindowsThenHide 的每 App 轮换状态（仅内存、不持久化，PRD R3）：
    /// 启动一轮时快照窗口顺序（z-order），之后每按一次只推进游标抬升下一个窗口，
    /// 绝不每次重新按实时 z-order 取序——抬升会改 z-order，否则两个窗口会来回 ping-pong（PRD R4 关键陷阱）。
    private struct CycleState {
        var windows: [AXUIElement] // 起始 z-order 快照，AXUIElement 作稳定身份（CFEqual 匹配）
        var cursor: Int            // 上次停留的窗口下标（首次进入 = 焦点窗口下标，无焦点 = -1）
    }
    /// key = bundleIdentifier。切走该 App 时由 onAppResignedFrontmost 清空（PRD R3）。
    private var cycleStates: [String: CycleState] = [:]

    init(resolver: TargetAppResolver, frontmost: FrontmostTracker, minimizer: WindowMinimizer) {
        self.resolver = resolver
        self.frontmost = frontmost
        self.minimizer = minimizer
    }

    /// 清空指定 App 的窗口轮换状态（App 失去前台时调用，PRD R3）。由 AppController 接到 FrontmostTracker。
    func resetWindowCycle(forBundleID bundleID: String) {
        cycleStates[bundleID] = nil
    }

    // MARK: - 运行态判定

    /// PRD D8：「前台」要求有可见窗口（后台 = 用户看不到 / 无可见窗口）。
    /// 目标为当前活跃 App 时，且 AX 已信任，再问 WindowMinimizer 是否有可见（未最小化）窗口：
    /// 有 → .frontmost；全部最小化 / 0 窗口 → .running（后台，命中默认 focus → D7 取消最小化并置前）。
    /// AX 未信任 / 读取失败 → 与今日一致：活跃 App 即 .frontmost（全最小化未切换的场景为已知局限）。
    /// 绝不在此为 AX 弹窗（与 D7 一致）。
    func runtimeState(for app: TargetApp) -> AppActivationDecision.RuntimeState {
        guard resolver.isInstalled(app) else { return .notInstalled }
        let instances = resolver.runningInstances(of: app)
        guard !instances.isEmpty else { return .notRunning }
        let frontBundleID = workspace.frontmostApplication?.bundleIdentifier
        guard frontBundleID == app.bundleIdentifier else { return .running }
        // 目标是当前活跃 App：仅在 AX 已信任时按「是否有可见窗口」细分前台/后台。
        if minimizer.isTrusted, let pid = instances.first?.processIdentifier {
            return minimizer.hasVisibleWindow(ofPID: pid) ? .frontmost : .running
        }
        return .frontmost
    }

    // MARK: - 主入口

    /// 处理一条绑定的热键触发（按其引用的激活配置决策），返回实际执行的动作（便于上层提示/测试）。
    @discardableResult
    func handle(_ binding: HotkeyBinding, config: ActivationConfig) -> AppActivationDecision.Action {
        let state = runtimeState(for: binding.app)
        let action = AppActivationDecision.action(for: state, config: config)
        perform(action, for: binding.app)
        return action
    }

    // MARK: - 执行

    private func perform(_ action: AppActivationDecision.Action, for app: TargetApp) {
        switch action {
        case .none:
            break
        case .markInvalid:
            break // App 失效的 UI 标记在 PR4；执行层无副作用。
        case .launch, .focus:
            bringToFront(app)
        case .launchWithoutFocus:
            launchWithoutFocus(app)
        case .hide:
            hideTarget(app)
        case .quit:
            quitTarget(app)
        case .returnToPrevious:
            returnToPrevious(from: app)
        case .showWithoutFocus:
            showWithoutFocus(app)
        case .minimize:
            minimizeTarget(app)
        case .cycleWindowsOrHide:
            cycleWindowsOrHide(app)
        }
    }

    /// 前台时逐个轮换窗口、全部展示过后再隐藏（PRD R2）。状态机见 CycleState/WindowCycleDecision。
    /// 降级（PRD R5）：AX 未授权 → 退化为普通 hide，并触发与 minimize 同一套一次性权限提示（复用 minimizer 回调）。
    private func cycleWindowsOrHide(_ app: TargetApp) {
        // AX 未授权：退化为 hide + 一次性提示（onPermissionDenied 即 minimize 用的同一回调）。
        guard minimizer.isTrusted else {
            hideTarget(app)
            minimizer.onPermissionDenied?()
            return
        }
        guard let pid = resolver.runningInstances(of: app).first?.processIdentifier else { return }
        let bundleID = app.bundleIdentifier

        // 实时枚举当前窗口（仅用于「与快照比对」及「≤1 窗口直接 hide」；轮换顺序仍以快照为准）。
        let liveWindows = minimizer.orderedWindows(ofPID: pid)
        guard liveWindows.count > 1 else {
            // 单窗口 / 无窗口：等同普通 hide，并清掉可能残留的状态（PRD R6）。
            hideTarget(app)
            cycleStates[bundleID] = nil
            return
        }

        // 取 / 重建快照：无状态、或窗口集合变化（开/关了窗口）→ 重新快照并把游标定到焦点窗口下标（PRD Q2/Q3）。
        var state: CycleState
        if let existing = cycleStates[bundleID], sameWindowSet(existing.windows, liveWindows) {
            state = existing
        } else {
            let focusedIndex = minimizer.focusedWindowIndex(in: liveWindows, ofPID: pid) ?? -1
            state = CycleState(windows: liveWindows, cursor: focusedIndex)
        }

        // 纯逻辑推进游标：决定抬升下一个窗口还是 hide+清空。
        let result = WindowCycleDecision.advance(windowCount: state.windows.count, cursor: state.cursor)
        switch result.step {
        case .hideAndReset:
            hideTarget(app)
            cycleStates[bundleID] = nil
        case .raise(let index):
            minimizer.raiseWindow(state.windows[index])
            // 抬升单个窗口后还需把 App 真正带到前台（公开 API），否则后台 App 的窗口抬升用户看不到。
            bringAppForwardWithoutDisturbingWindows(app)
            state.cursor = result.nextCursor
            cycleStates[bundleID] = state
        }
    }

    /// 把目标 App 置前（用于窗口轮换：AX 已抬升某窗口，再用公开 API 把 App 带到最前）。
    /// 走 openApplication（activates=true）——与 bringToFront 同一可靠路径——但不调用 minimizer 取消最小化
    /// （取消最小化已由 raiseWindow 针对「当前轮到的那个窗口」精确完成，避免再动焦点/主窗口）。
    private func bringAppForwardWithoutDisturbingWindows(_ app: TargetApp) {
        guard let url = resolver.resolvedURL(for: app) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// 两组窗口快照是否为「同一集合」（顺序无关，用 CFEqual 逐一匹配）。
    /// 用于判断轮换期间窗口集是否变化（开/关窗口）→ 变了就重新快照（PRD Q2）。
    private func sameWindowSet(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
        guard a.count == b.count else { return false }
        // 每个 a 中的窗口都能在 b 中找到对应（数量相等 + 全包含 ⇒ 集合相等）。
        return a.allSatisfy { wa in b.contains { minimizer.windowsEqual(wa, $0) } }
    }

    /// 显示不聚焦（PRD D6「先抬升再还焦点」option b）：
    /// (1) 抓取触发时的前台 App（NSWorkspace.frontmostApplication——按键时即用户的 App，Relay 是后台 agent 非前台）；
    /// (2) 走 bringToFront 把目标抬到最前并聚焦（同时 unhide / 机会式取消最小化）；
    /// (3) 在 (2) 的 openApplication 完成后，用同样可靠的 openApplication 路径把原前台 App 重新激活，焦点还回去。
    /// 守卫：无抓到前台 App，或它即目标（bundleID 相同）时，跳过 (3)，留目标在前台。
    /// 仅公开 API，无 AX（取消最小化由 bringToFront 在已信任时机会式完成）。
    /// 已接受的取舍：被还焦的 App 窗口回到最上、与目标重叠处会盖住目标，并可能有一次轻微闪烁。
    private func showWithoutFocus(_ app: TargetApp) {
        let previousFrontmost = workspace.frontmostApplication
        // 抓取前台 App 即目标时跳过还焦（仅留目标在前台）。
        let shouldReturnFocus = previousFrontmost.map {
            $0.bundleIdentifier != app.bundleIdentifier
        } ?? false

        // 无需还焦：普通置前，FrontmostTracker 正常记录（目标成为 current）。
        guard shouldReturnFocus, let previousFrontmost else {
            bringToFront(app)
            return
        }

        // 合成 A→C→A 跳变会让 FrontmostTracker 把 previous 污染成目标 C（PR#7 Codex 反馈）：
        // 引用计数式抑制——begin 抓快照、end 归零时恢复，期间丢弃所有合成激活；
        // 重叠/快速重复的多次 showWithoutFocus 会正确嵌套，不会被先完成者提前解除（PR#7 Codex 第二轮）。
        frontmost.beginSuppression()
        // 强捕获 frontmost，保证即使 self 已释放也能解除抑制。
        bringToFront(app) { [weak self, frontmost = self.frontmost] in
            self?.bringRunningAppToFront(previousFrontmost)
            frontmost.endSuppression()
        }
    }

    /// 最小化目标的焦点/主窗口（经 AX）。pid 取首个运行实例；无实例则不做事。
    /// AX 信任态检查与降级（无操作 + 一次性提示）在 WindowMinimizer 内部（PRD D4）。
    private func minimizeTarget(_ app: TargetApp) {
        guard let pid = resolver.runningInstances(of: app).first?.processIdentifier else { return }
        minimizer.minimizeFocusedWindow(ofPID: pid)
    }

    /// 启动但不聚焦：openApplication 且 activates=false（公开 API，不偷取焦点）。
    private func launchWithoutFocus(_ app: TargetApp) {
        guard let url = resolver.resolvedURL(for: app) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// 退出目标的全部运行实例（公开 API）。
    private func quitTarget(_ app: TargetApp) {
        for instance in resolver.runningInstances(of: app) {
            instance.terminate()
        }
    }

    /// 启动/聚焦统一路径：取消隐藏 + openApplication（启动/置前/reopen 建窗，兜底「无可见窗口」）。
    /// PRD D7：若窗口被最小化到 Dock，openApplication 只激活 App 而不显示窗口；当 AX 已信任时
    /// 机会式取消最小化焦点/主窗口。focus 绝不申请权限/不提示——未信任则静默保持原行为。
    /// `onComplete`（可选）在 openApplication 异步完成后回到主 actor 调用——用于 showWithoutFocus 还焦时序（D6）。
    private func bringToFront(_ app: TargetApp, onComplete: (() -> Void)? = nil) {
        let instances = resolver.runningInstances(of: app)
        for instance in instances where instance.isHidden {
            instance.unhide()
        }
        if minimizer.isTrusted, let pid = instances.first?.processIdentifier {
            minimizer.unminimizeFocusedWindow(ofPID: pid)
        }
        guard let url = resolver.resolvedURL(for: app) else {
            onComplete?() // URL 解析失败也别吞掉后续时序（still attempt 还焦）。
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        guard let onComplete else {
            workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
            return
        }
        // openApplication 的回调是 @Sendable、在后台并发队列投递（非主线程），故显式跳回主 actor 再 onComplete。
        workspace.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in onComplete() }
        }
    }

    private func hideTarget(_ app: TargetApp) {
        for instance in resolver.runningInstances(of: app) {
            instance.hide()
        }
    }

    /// 切回上一个 App；previous 为空 / 已退出 / 即目标 / 无法拉前时退化为隐藏目标（PRD 锁定边界）。
    /// `isTerminated` 判定必要：FrontmostTracker 不监听 didTerminate，previous 可能已退出，
    /// 若直接交给 bringRunningAppToFront 会被其 URL 兜底重新拉起，违反「退出→hide 目标」。
    private func returnToPrevious(from app: TargetApp) {
        guard let previous = frontmost.previousApp,
              previous.bundleIdentifier != app.bundleIdentifier,
              bringRunningAppToFront(previous)
        else {
            hideTarget(app)
            return
        }
    }

    /// 把一个正在运行的 App 拉到前台，返回是否成功执行了拉前动作。统一走 openApplication
    /// （与 launch/focus 同路径，可靠）——而非 `activate(from: .current)`：Relay 是后台 agent、非前台，
    /// 协作式激活会静默失败。已退出或 URL 解析失败（优先 bundleURL，回退 bundleIdentifier）时返回
    /// false，交由调用方退化（不退化为 activate()，后者对 agent 同样静默失败，并非真实兜底）。
    /// `isTerminated` 再判一次以收紧 returnToPrevious 检查与此处之间的极窄竞态。
    @discardableResult
    private func bringRunningAppToFront(_ runningApp: NSRunningApplication) -> Bool {
        guard !runningApp.isTerminated else { return false }
        let url = runningApp.bundleURL
            ?? runningApp.bundleIdentifier.flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }
        guard let url else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
        return true
    }
}
