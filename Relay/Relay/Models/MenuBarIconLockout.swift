//
//  MenuBarIconLockout.swift
//  Relay
//
//  菜单栏图标「锁定守卫」的纯逻辑（R5）：菜单栏 agent 一旦把状态项藏了又没有唤回的热键，
//  用户就被锁在外面。故隐藏（visible == false）只在已配置切换热键时才允许；显示永远允许。
//  抽成 nonisolated 纯函数以便单测（不依赖 AppKit/SwiftUI）。
//

import Foundation

nonisolated enum MenuBarIconLockout {
    /// 是否允许把 showMenuBarIcon 设为给定值。
    /// - 显示（visible == true）：永远允许。
    /// - 隐藏（visible == false）：仅当已设置切换热键（toggleHotkey != nil）时允许。
    static func canSet(visible: Bool, toggleHotkey: Hotkey?) -> Bool {
        visible || toggleHotkey != nil
    }
}
