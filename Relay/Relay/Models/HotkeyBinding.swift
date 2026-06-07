//
//  HotkeyBinding.swift
//  Relay
//
//  一条绑定：目标应用 + 可空快捷键 + 焦点行为。
//  命名为 HotkeyBinding 以避开 SwiftUI.Binding。同一 App 在不同 Profile 中是各自独立的绑定。
//

import Foundation

nonisolated struct HotkeyBinding: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var app: TargetApp
    var hotkey: Hotkey?
    var behavior: FocusBehavior

    init(
        id: UUID = UUID(),
        app: TargetApp,
        hotkey: Hotkey? = nil,
        behavior: FocusBehavior = .defaultBehavior
    ) {
        self.id = id
        self.app = app
        self.hotkey = hotkey
        self.behavior = behavior
    }
}
