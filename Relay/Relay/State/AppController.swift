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

    init() {
        let resolver = TargetAppResolver()
        let frontmost = FrontmostTracker()
        let activation = AppActivationService(resolver: resolver, frontmost: frontmost)
        let registration = HotkeyRegistrationService(activation: activation)
        let model = AppModel()

        self.resolver = resolver
        self.frontmost = frontmost
        self.activation = activation
        self.registration = registration
        self.model = model

        model.hotkeysDidChange = { [registration] profile in
            registration.activate(profile)
        }
        registration.activate(model.activeProfile) // 启动即注册当前 active profile
    }
}
