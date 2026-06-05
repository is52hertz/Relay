//
//  AppController.swift
//  Relay
//
//  组合根：持有 AppModel(SoT) 与各服务，并把「active profile 变化 → 重注册热键」接起来。
//  让 AppModel 保持无 AppKit/第三方依赖、可单测；副作用集中在此。
//

import Foundation

@MainActor
final class AppController {
    let model: AppModel
    let resolver: TargetAppResolver

    private let frontmost: FrontmostTracker
    private let activation: AppActivationService
    private let registration: HotkeyRegistrationService
    private let loginItem: LoginItemService
    private let dockIcon: DockIconController

    init() {
        let resolver = TargetAppResolver()
        let frontmost = FrontmostTracker()
        let activation = AppActivationService(resolver: resolver, frontmost: frontmost)
        let registration = HotkeyRegistrationService(activation: activation)
        let loginItem = LoginItemService()
        let dockIcon = DockIconController()
        let model = AppModel()

        self.resolver = resolver
        self.frontmost = frontmost
        self.activation = activation
        self.registration = registration
        self.loginItem = loginItem
        self.dockIcon = dockIcon
        self.model = model

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
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
