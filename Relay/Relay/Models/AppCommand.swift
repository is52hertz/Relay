//
//  AppCommand.swift
//  Relay
//
//  「全局应用命令」枚举：不同于「仅当前 Profile 的 app-target 绑定」，这些是常驻的应用控制命令，
//  各自映射到一个稳定的 KeyboardShortcuts.Name，由 HotkeyRegistrationService 常驻注册（不随 Profile 切换注销）。
//  目前仅 toggleMenuBarIcon；建模为枚举以便未来新增命令复用同一条注册路径。
//

import Foundation

nonisolated enum AppCommand: String, CaseIterable, Sendable {
    /// 切换菜单栏图标可见性（F-B：F-A 的安全出口）。
    case toggleMenuBarIcon

    /// 稳定且互不相同的 KeyboardShortcuts.Name 标识符。
    /// 用带前缀的 rawValue，避免与「Profile 绑定」用的 binding.id.uuidString 命名空间冲突。
    var shortcutNameIdentifier: String {
        "appCommand.\(rawValue)"
    }
}
