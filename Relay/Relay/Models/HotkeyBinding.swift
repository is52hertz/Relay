//
//  HotkeyBinding.swift
//  Relay
//
//  一条绑定：目标应用 + 可空快捷键 + 引用的激活配置 id。
//  命名为 HotkeyBinding 以避开 SwiftUI.Binding。同一 App 在不同 Profile 中是各自独立的绑定。
//  configID 指向全局 AppConfiguration.activationConfigs 中的一条 ActivationConfig。
//

import Foundation

nonisolated struct HotkeyBinding: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var app: TargetApp
    var hotkey: Hotkey?
    var configID: UUID

    init(
        id: UUID = UUID(),
        app: TargetApp,
        hotkey: Hotkey? = nil,
        configID: UUID
    ) {
        self.id = id
        self.app = app
        self.hotkey = hotkey
        self.configID = configID
    }
}
