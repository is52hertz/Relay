//
//  AppConfiguration.swift
//  Relay
//
//  持久化根文档（含 schemaVersion 便于未来迁移）。内存中的唯一真相由 AppModel 持有。
//  activationConfigs 为全局共享（跨 Profile）的激活配置表，绑定/默认按 id 引用其中一条。
//

import Foundation

nonisolated struct AppConfiguration: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var profiles: [Profile]
    var activeProfileID: UUID?
    var activationConfigs: [ActivationConfig]
    var settings: AppSettings

    static let currentSchemaVersion = 2

    init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        profiles: [Profile] = [],
        activeProfileID: UUID? = nil,
        activationConfigs: [ActivationConfig] = [],
        settings: AppSettings = AppSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.activationConfigs = activationConfigs
        self.settings = settings
    }

    /// 首次启动的默认配置：一个空的 "Default" Profile（设为激活）+ 4 个种子激活配置，
    /// 默认配置取第一条（Return to Previous）。App 未发布，无需迁移（见 PRD D1）。
    static func makeDefault() -> AppConfiguration {
        let profile = Profile(name: "Default")
        let configs = ActivationConfig.makeDefaults()
        var settings = AppSettings()
        settings.defaultConfigID = configs[0].id
        return AppConfiguration(
            profiles: [profile],
            activeProfileID: profile.id,
            activationConfigs: configs,
            settings: settings
        )
    }
}

nonisolated struct AppSettings: Codable, Hashable, Sendable {
    var showDockIcon: Bool
    var launchAtLogin: Bool
    /// 新增绑定时默认引用的激活配置 id（指向 AppConfiguration.activationConfigs）。
    var defaultConfigID: UUID

    init(
        showDockIcon: Bool = false,
        launchAtLogin: Bool = false,
        defaultConfigID: UUID = UUID()
    ) {
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
        self.defaultConfigID = defaultConfigID
    }
}
