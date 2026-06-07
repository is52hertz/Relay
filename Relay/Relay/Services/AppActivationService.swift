//
//  AppActivationService.swift
//  Relay
//
//  焦点引擎的副作用执行层：判定运行态 → 用纯决策（AppActivationDecision）得到动作 → 执行。
//  全部公开 AppKit API，无需 Accessibility/私有 API（见 cross-app-activation 研究）。
//

import AppKit

@MainActor
final class AppActivationService {
    private let resolver: TargetAppResolver
    private let frontmost: FrontmostTracker
    private let workspace = NSWorkspace.shared

    init(resolver: TargetAppResolver, frontmost: FrontmostTracker) {
        self.resolver = resolver
        self.frontmost = frontmost
    }

    // MARK: - 运行态判定

    func runtimeState(for app: TargetApp) -> AppActivationDecision.RuntimeState {
        guard resolver.isInstalled(app) else { return .notInstalled }
        guard !resolver.runningInstances(of: app).isEmpty else { return .notRunning }
        let frontBundleID = workspace.frontmostApplication?.bundleIdentifier
        return frontBundleID == app.bundleIdentifier ? .frontmost : .running
    }

    // MARK: - 主入口

    /// 处理一条绑定的热键触发，返回实际执行的动作（便于上层提示/测试）。
    @discardableResult
    func handle(_ binding: HotkeyBinding) -> AppActivationDecision.Action {
        let state = runtimeState(for: binding.app)
        let action = AppActivationDecision.action(for: state, behavior: binding.behavior)
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
        case .hide:
            hideTarget(app)
        case .returnToPrevious:
            returnToPrevious(from: app)
        }
    }

    /// 启动/聚焦统一路径：取消隐藏 + openApplication（启动/置前/reopen 建窗，兜底「无可见窗口」）。
    private func bringToFront(_ app: TargetApp) {
        for instance in resolver.runningInstances(of: app) where instance.isHidden {
            instance.unhide()
        }
        guard let url = resolver.resolvedURL(for: app) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration, completionHandler: nil)
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
