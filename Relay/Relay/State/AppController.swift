//
//  AppController.swift
//  Relay
//
//  组合根：持有 AppModel(SoT) 与各服务，并把「active profile 变化 → 重注册热键」接起来。
//  让 AppModel 保持无 AppKit/第三方依赖、可单测；副作用集中在此。
//

import AppKit
import Foundation

@MainActor
final class AppController {
    let model: AppModel
    let resolver: TargetAppResolver
    /// 暴露给 UI（编辑器选 Minimize 时延迟申请 Accessibility 权限）。
    let minimizer: WindowMinimizer
    /// 暴露给设置 UI（个性化标签页的语言切换）。
    let languageService: LanguageService

    private let frontmost: FrontmostTracker
    private let activation: AppActivationService
    private let registration: HotkeyRegistrationService
    private let loginItem: LoginItemService
    private let dockIcon: DockIconController
    private var terminateObserver: NSObjectProtocol?
    /// AX 未授权提示只弹一次（每个 App 会话），避免每次触发都打扰（PRD D4）。
    private var didWarnAccessibilityDenied = false

    init() {
        let resolver = TargetAppResolver()
        let frontmost = FrontmostTracker()
        let minimizer = WindowMinimizer()
        let activation = AppActivationService(resolver: resolver, frontmost: frontmost, minimizer: minimizer)
        let model = AppModel()
        // 触发时按 id 解析最新激活配置（配置编辑不重注册热键，故实时读 model 的全局表）。
        let registration = HotkeyRegistrationService(activation: activation) { [model] id in
            model.activationConfig(id: id)
        }
        let loginItem = LoginItemService()
        let dockIcon = DockIconController()

        self.resolver = resolver
        self.frontmost = frontmost
        self.minimizer = minimizer
        // 重启前两件副作用须在 `open -n` 之前完成：flush 落盘（P1）+ 释放全局热键（P2，消除新旧进程重叠持有 Carbon 热键的窗口）。顺序不敏感，flush 在前保留 P1 语义清晰。
        self.languageService = LanguageService(beforeRelaunch: { [model, registration] in
            model.saveNow()
            registration.deactivateAll()
        })
        self.activation = activation
        self.registration = registration
        self.loginItem = loginItem
        self.dockIcon = dockIcon
        self.model = model

        // 配置为 minimize 但 AX 未授权时触发：弹一次性提示（不做任何破坏性动作，PRD D4）。
        minimizer.onPermissionDenied = { [weak self] in
            self?.warnAccessibilityDeniedOnce()
        }

        // cycleWindowsThenHide：某 App 失去前台时清空其窗口轮换游标（切走再切回从头开始，PRD R3）。
        frontmost.onAppResignedFrontmost = { [activation] bundleID in
            activation.resetWindowCycle(forBundleID: bundleID)
        }

        model.hotkeysDidChange = { [registration] profile in
            registration.activate(profile)
        }
        model.settingsDidChange = { [loginItem, dockIcon] settings in
            loginItem.setEnabled(settings.launchAtLogin)
            dockIcon.setDockIconVisible(settings.showDockIcon)
        }

        // 启动即应用当前状态：注册 active profile 热键，同步 Dock/登录项。
        // 单测宿主下跳过这些系统副作用（SMAppService 在 XCTest 宿主中会导致崩溃）。
        if !AppController.isRunningTests {
            registration.activate(model.activeProfile)
            dockIcon.setDockIconVisible(model.settings.showDockIcon)
            loginItem.setEnabled(model.settings.launchAtLogin)
            observeTermination()
        }
    }

    /// 退出前同步 flush 去抖保存，避免「改完即退」丢失最后一次配置变更。
    /// 覆盖全部正常退出路径（菜单 Quit、Window 聚焦时的标准 ⌘Q、注销/重启）；
    /// 强制退出/SIGKILL/崩溃无法覆盖。queue: nil → 回调在 willTerminate 的发帖线程（主线程）
    /// 同步执行，保证 saveNow() 在 exit 前完成。
    private func observeTermination() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [model] _ in
            MainActor.assumeIsolated {
                model.saveNow()
            }
        }
    }

    /// 一次性提示「最小化需 Accessibility 授权」。绝不在此自动改用别的破坏性动作（PRD D4）。
    /// 引导用户在「通用设置 › 选 Minimize」处显式授权，或直接打开系统设置。
    private func warnAccessibilityDeniedOnce() {
        guard !didWarnAccessibilityDenied else { return }
        didWarnAccessibilityDenied = true
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Minimize needs Accessibility access")
        alert.informativeText = String(localized: "Relay can’t minimize the window until you grant Accessibility access. Open System Settings › Privacy & Security › Accessibility and enable Relay, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
