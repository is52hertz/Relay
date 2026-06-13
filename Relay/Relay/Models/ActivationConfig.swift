//
//  ActivationConfig.swift
//  Relay
//
//  激活配置（取代旧的 4 个固定 FocusBehavior 预设）：按目标 App 的三个运行态
//  （未启动 / 后台 / 前台）分别配置要执行的动作。全局共享、可增删改名，绑定按 id 引用。
//  纯数据值类型：nonisolated Codable，不引入 AppKit/SwiftUI（见 spec/swift/concurrency）。
//

import Foundation

// MARK: - 各运行态的可选动作（按状态分别约束，编辑器只列该状态合法项）

/// 「未启动」可选动作（本期可编辑·有功能）。
nonisolated enum NotRunningAction: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case launch              // 启动并聚焦
    case launchWithoutFocus  // 启动但不聚焦
    case none                // 不做事

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .launch: String(localized: "Launch & Focus")
        case .launchWithoutFocus: String(localized: "Launch in Background")
        case .none: String(localized: "Do Nothing")
        }
    }
}

/// 「后台」可选动作。三者全部接入引擎：focus = unhide+activate；
/// showWithoutFocus = unhide 不激活；minimize = AX 最小化焦点窗口（延迟授权）。
nonisolated enum BackgroundAction: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case focus            // 聚焦
    case showWithoutFocus // 显示不聚焦
    case minimize         // 最小化（经 Accessibility，延迟授权）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .showWithoutFocus: String(localized: "Show Without Focus")
        case .minimize: String(localized: "Minimize")
        }
    }

    /// 三者均已接入引擎。
    var isImplemented: Bool { true }
}

/// 「前台」可选动作（全部接入引擎；minimize 经 Accessibility，延迟授权）。
nonisolated enum FrontmostAction: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case returnToPrevious // 切回上一个
    case hide             // 隐藏
    case quit             // 退出
    case none             // 不做事
    case minimize         // 最小化（经 Accessibility，延迟授权）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .returnToPrevious: String(localized: "Return to Previous")
        case .hide: String(localized: "Hide")
        case .quit: String(localized: "Quit")
        case .none: String(localized: "Do Nothing")
        case .minimize: String(localized: "Minimize")
        }
    }

    /// 全部已接入引擎。
    var isImplemented: Bool { true }
}

// MARK: - 配置本体

nonisolated struct ActivationConfig: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var notRunning: NotRunningAction
    var background: BackgroundAction
    var frontmost: FrontmostAction

    init(
        id: UUID = UUID(),
        name: String,
        notRunning: NotRunningAction,
        background: BackgroundAction = .focus,
        frontmost: FrontmostAction
    ) {
        self.id = id
        self.name = name
        self.notRunning = notRunning
        self.background = background
        self.frontmost = frontmost
    }

    /// 内置默认配置的本地化展示名：name 仍为四个已知种子名之一时返回本地化文案；
    /// 用户改过名 / 自建配置 → 原样返回 name（用户数据不翻译）。
    var localizedName: String {
        switch name {
        case "Return to Previous": String(localized: "Return to Previous")
        case "Launch or Focus": String(localized: "Launch or Focus")
        case "Toggle Hide": String(localized: "Toggle Hide")
        case "Focus Only": String(localized: "Focus Only")
        default: name
        }
    }
}

nonisolated extension ActivationConfig {
    /// 首次启动的 4 个默认配置：与旧 FocusBehavior 预设 1:1 复刻（未启动/前台矩阵不变）。
    /// 这些行是普通可编辑/可删除的种子（PRD：默认不受保护）。
    static func makeDefaults() -> [ActivationConfig] {
        [
            ActivationConfig(name: "Return to Previous",
                             notRunning: .launch, background: .focus, frontmost: .returnToPrevious),
            ActivationConfig(name: "Launch or Focus",
                             notRunning: .launch, background: .focus, frontmost: .none),
            ActivationConfig(name: "Toggle Hide",
                             notRunning: .launch, background: .focus, frontmost: .hide),
            ActivationConfig(name: "Focus Only",
                             notRunning: .none, background: .focus, frontmost: .none),
        ]
    }
}
