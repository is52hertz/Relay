//
//  Profile.swift
//  Relay
//
//  快捷键组 / 场景配置：一组有序的绑定。切换 Profile 时注销旧组、注册新组（PR3）。
//

import Foundation

nonisolated struct Profile: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var bindings: [HotkeyBinding]

    init(id: UUID = UUID(), name: String, bindings: [HotkeyBinding] = []) {
        self.id = id
        self.name = name
        self.bindings = bindings
    }
}
