//
//  AppActivationDecision.swift
//  Relay
//
//  焦点引擎的纯决策：目标运行态 × 焦点行为 → 动作。无副作用、可单测。
//  与 PRD 的 FocusBehavior 行为矩阵一一对应。
//

import Foundation

nonisolated enum AppActivationDecision {

    /// 目标应用的运行态。`running` 涵盖「后台/已隐藏/无可见窗口」——无 Accessibility 无法细分，
    /// 三者执行动作一致（见 PRD P1-8），故合并。
    enum RuntimeState: Equatable, Sendable {
        case notInstalled
        case notRunning
        case running
        case frontmost
    }

    /// 决策输出。副作用由 AppActivationService 执行；`returnToPrevious` 在无 previous 时由执行层退化为 hide。
    enum Action: Equatable, Sendable {
        case none
        case markInvalid
        case launch
        case focus
        case hide
        case returnToPrevious
    }

    static func action(for state: RuntimeState, behavior: FocusBehavior) -> Action {
        switch state {
        case .notInstalled:
            return .markInvalid
        case .notRunning:
            // Focus Only 不负责启动。
            return behavior == .focusOnly ? .none : .launch
        case .running:
            return .focus
        case .frontmost:
            switch behavior {
            case .returnToPrevious: return .returnToPrevious
            case .toggleHide:       return .hide
            case .launchOrFocus:    return .none
            case .focusOnly:        return .none
            }
        }
    }
}
