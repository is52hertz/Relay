//
//  AppConfiguration.swift
//  Relay
//
//  持久化根文档（含 schemaVersion 便于未来迁移）。内存中的唯一真相由 AppModel 持有。
//

import Foundation

nonisolated struct AppConfiguration: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var profiles: [Profile]
    var activeProfileID: UUID?
    var settings: AppSettings

    static let currentSchemaVersion = 1

    init(
        schemaVersion: Int = AppConfiguration.currentSchemaVersion,
        profiles: [Profile] = [],
        activeProfileID: UUID? = nil,
        settings: AppSettings = AppSettings()
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.settings = settings
    }

    /// 首次启动的默认配置：一个空的 "Default" Profile 并设为激活。
    static func makeDefault() -> AppConfiguration {
        let profile = Profile(name: "Default")
        return AppConfiguration(profiles: [profile], activeProfileID: profile.id)
    }
}

nonisolated struct AppSettings: Codable, Hashable, Sendable {
    var showDockIcon: Bool
    var launchAtLogin: Bool
    var defaultBehavior: FocusBehavior

    init(
        showDockIcon: Bool = false,
        launchAtLogin: Bool = false,
        defaultBehavior: FocusBehavior = .defaultBehavior
    ) {
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
        self.defaultBehavior = defaultBehavior
    }
}
