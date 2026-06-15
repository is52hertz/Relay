//
//  WindowCycleDecision.swift
//  Relay
//
//  cycleWindowsThenHide 的纯游标推进逻辑：在「窗口数 × 当前游标」上决定下一步——
//  抬升某个窗口 / 隐藏并清空状态。无 AX、无副作用、可单测（AX 的窗口枚举与抬升在执行层）。
//

import Foundation

nonisolated enum WindowCycleDecision {

    /// 一次按键的结果。`raise(index:)` = 抬升快照中该下标的窗口；`hideAndReset` = 隐藏目标并清空该 App 轮换状态。
    enum Step: Equatable, Sendable {
        case hideAndReset
        case raise(index: Int)
    }

    /// 推进游标。
    /// - Parameters:
    ///   - windowCount: 本次按键时当前窗口数（执行层实时枚举）。
    ///   - cursor: 该 App 上一轮停留的游标（首次进入轮换时传焦点窗口下标，无焦点传 -1；见 PRD Q3）。
    /// - Returns: `nextCursor` 为推进后的新游标（仅 `.raise` 时有效，供执行层回写状态）。
    ///
    /// 规则（PRD R2/R6）：
    /// - ≤1 个窗口 → 没什么可轮换 → `hideAndReset`（单窗口表现得和普通 hide 一致）。
    /// - 否则把游标 +1：若越界（已展示过最后一个窗口）→ `hideAndReset`；否则抬升新游标处窗口。
    static func advance(windowCount: Int, cursor: Int) -> (step: Step, nextCursor: Int) {
        guard windowCount > 1 else { return (.hideAndReset, cursor) }
        let next = cursor + 1
        if next >= windowCount {
            return (.hideAndReset, next)
        }
        return (.raise(index: next), next)
    }
}
