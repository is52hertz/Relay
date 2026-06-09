//
//  AppActivationDecision.swift
//  Relay
//
//  焦点引擎的纯决策：目标运行态 × 激活配置 → 动作。无副作用、可单测。
//  按 ActivationConfig 的三段（未启动/后台/前台）映射到原子动作。
//

import Foundation

nonisolated enum AppActivationDecision {

    /// 目标应用的运行态。`running`（后台）涵盖「后台/已隐藏/无可见窗口」——无 Accessibility 无法细分，
    /// 三者执行动作一致（见 PRD），故合并。
    enum RuntimeState: Equatable, Sendable {
        case notInstalled
        case notRunning
        case running
        case frontmost
    }

    /// 决策输出（原子动作）。副作用由 AppActivationService 执行；
    /// `returnToPrevious` 在无 previous 时由执行层退化为 hide。
    /// `minimize` / `showWithoutFocus` 本期为占位：决策层不产出它们（后台一律 focus、前台 minimize 占位禁用）。
    enum Action: Equatable, Sendable {
        case none
        case markInvalid
        case launch
        case launchWithoutFocus
        case focus
        case hide
        case quit
        case returnToPrevious
        // 占位（本期不产出）：
        case minimize
        case showWithoutFocus
    }

    static func action(for state: RuntimeState, config: ActivationConfig) -> Action {
        switch state {
        case .notInstalled:
            return .markInvalid
        case .notRunning:
            switch config.notRunning {
            case .launch:             return .launch
            case .launchWithoutFocus: return .launchWithoutFocus
            case .none:               return .none
            }
        case .running:
            // 后台本期为占位：无论配置为何，引擎一律按聚焦执行（见 PRD D5）。
            return .focus
        case .frontmost:
            switch config.frontmost {
            case .returnToPrevious: return .returnToPrevious
            case .hide:             return .hide
            case .quit:             return .quit
            case .none:             return .none
            // 占位：最小化未接入，退化为不做事（UI 已禁用该选项，不应被选中）。
            case .minimize:         return .none
            }
        }
    }
}
