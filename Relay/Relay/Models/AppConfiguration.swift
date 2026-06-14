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

    static let currentSchemaVersion = 3

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
    /// 菜单栏状态项图标的 SF Symbol 名。纯字符串持久化（库无关）。缺失/无效时回退到 `defaultMenuBarIconName`。
    var menuBarIconName: String

    /// 菜单栏图标默认值（也是渲染兜底：无效名一律回退到它，状态项绝不空白）。
    static let defaultMenuBarIconName = "command"

    /// 个性化页的预设 SF Symbol（用户也可在自定义框输入任意符号名）。
    static let menuBarIconPresets: [String] = [
        "command", "bolt", "bolt.fill", "righttriangle.split.diagonal",
    ]

    init(
        showDockIcon: Bool = false,
        launchAtLogin: Bool = false,
        defaultConfigID: UUID = UUID(),
        menuBarIconName: String = AppSettings.defaultMenuBarIconName
    ) {
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
        self.defaultConfigID = defaultConfigID
        self.menuBarIconName = menuBarIconName
    }

    // 自定义解码：旧 config.json 没有 menuBarIconName 键。合成的 Decodable 会因缺键整体抛错，
    // 进而 PersistenceStore.load() 返回 nil → makeDefault() 清空用户数据。故新键用 decodeIfPresent 容错。
    // （encode(to:) 仍由编译器合成，按全部存储属性写出。）
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        defaultConfigID = try c.decode(UUID.self, forKey: .defaultConfigID)
        menuBarIconName = try c.decodeIfPresent(String.self, forKey: .menuBarIconName)
            ?? AppSettings.defaultMenuBarIconName
    }
}
