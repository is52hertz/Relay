//
//  FocusBehavior.swift
//  Relay
//
//  焦点行为（ActivationRule）：按下绑定的快捷键时，依据目标应用的当前状态
//  决定执行的动作。这是 Relay 的产品概念，与 NSApplication.ActivationPolicy 无关。
//

import Foundation

nonisolated enum FocusBehavior: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// 默认：未运行→启动；后台→聚焦并记录上一个 App；已在前台→切回上一个 App。
    case returnToPrevious
    /// 未运行→启动；后台→聚焦；已在前台→不做事。
    case launchOrFocus
    /// 未运行→启动；后台→聚焦；已在前台→隐藏目标。
    case toggleHide
    /// 仅聚焦已运行的应用；未运行→不启动。
    case focusOnly

    var id: String { rawValue }

    /// 全局默认行为（见 PRD P0-5）。
    static let defaultBehavior: FocusBehavior = .returnToPrevious

    var displayName: String {
        switch self {
        case .returnToPrevious: "Return to Previous"
        case .launchOrFocus: "Launch or Focus"
        case .toggleHide: "Toggle Hide"
        case .focusOnly: "Focus Only"
        }
    }

    var summary: String {
        switch self {
        case .returnToPrevious: "Frontmost → switch back to the previous app."
        case .launchOrFocus: "Frontmost → do nothing."
        case .toggleHide: "Frontmost → hide the target."
        case .focusOnly: "Only focuses a running app; never launches."
        }
    }
}
