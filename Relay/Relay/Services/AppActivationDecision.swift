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
    /// `minimize` 需 Accessibility（AX 不可信时由执行层「无操作 + 一次性提示」降级，见 PRD D4）；
    /// 决策层保持纯（不查信任态），仅产出动作。
    /// `cycleWindowsOrHide` 同样需 Accessibility：执行层维护每 App 的窗口轮换游标，逐次抬升下一个窗口，
    /// 全部展示过后再 hide；AX 不可信时退化为 hide + 一次性提示（与 minimize 同套提示，PRD D4/R5）。
    enum Action: Equatable, Sendable {
        case none
        case markInvalid
        case launch
        case launchWithoutFocus
        case focus
        case hide
        case quit
        case returnToPrevious
        case minimize
        case showWithoutFocus
        case cycleWindowsOrHide
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
            switch config.background {
            case .focus:            return .focus
            case .showWithoutFocus: return .showWithoutFocus
            case .minimize:         return .minimize
            }
        case .frontmost:
            switch config.frontmost {
            case .returnToPrevious:    return .returnToPrevious
            case .hide:                return .hide
            case .quit:                return .quit
            case .none:                return .none
            case .minimize:            return .minimize
            case .cycleWindowsThenHide: return .cycleWindowsOrHide
            }
        }
    }
}
