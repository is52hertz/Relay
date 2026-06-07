//
//  Hotkey.swift
//  Relay
//
//  一个快捷键组合。持久化格式独立于第三方库——只存 Carbon 码。
//  与 KeyboardShortcuts.Shortcut 的互转放在引入依赖后的桥接文件中（PR3）。
//

import Foundation

nonisolated struct Hotkey: Codable, Hashable, Sendable {
    var carbonKeyCode: Int
    var carbonModifiers: Int

    init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }
}
