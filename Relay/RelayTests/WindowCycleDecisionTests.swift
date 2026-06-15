//
//  WindowCycleDecisionTests.swift
//  RelayTests
//
//  覆盖 cycleWindowsThenHide 的纯游标推进（WindowCycleDecision.advance）：
//  首按从焦点窗口下一个开始、逐个轮换、展示过最后一个后再 hide、单/零窗口直接 hide。
//  AX 窗口枚举与抬升是执行层副作用，此处只测可判定的游标逻辑（见 spec/swift/quality 测试约定）。
//

import Testing
@testable import Relay

struct WindowCycleDecisionTests {
    private typealias Step = WindowCycleDecision.Step

    /// 0 / 1 个窗口：无可轮换 → 立即 hide+清空（PRD R6，单窗口表现得和普通 hide 一致）。
    @Test func singleOrZeroWindowHides() {
        #expect(WindowCycleDecision.advance(windowCount: 0, cursor: -1).step == .hideAndReset)
        #expect(WindowCycleDecision.advance(windowCount: 1, cursor: 0).step == .hideAndReset)
    }

    /// 首按：游标从「焦点窗口下标」推进到下一个窗口（PRD Q3：首按可见地切到下一个，而非重聚焦当前）。
    @Test func firstPressAdvancesPastFocused() {
        // 3 窗口，焦点是 index 0 → 首按抬升 index 1。
        let r = WindowCycleDecision.advance(windowCount: 3, cursor: 0)
        #expect(r.step == .raise(index: 1))
        #expect(r.nextCursor == 1)
    }

    /// 焦点是最后一个窗口时，首按即越界 → 直接 hide+清空（已展示过最后一个）。
    @Test func firstPressOnLastWindowHides() {
        let r = WindowCycleDecision.advance(windowCount: 3, cursor: 2)
        #expect(r.step == .hideAndReset)
    }

    /// 无焦点窗口（cursor = -1）：首按从第 0 个开始抬升。
    @Test func noFocusStartsFromZero() {
        let r = WindowCycleDecision.advance(windowCount: 2, cursor: -1)
        #expect(r.step == .raise(index: 0))
        #expect(r.nextCursor == 0)
    }

    /// 完整一轮（3 窗口，从无焦点起）：raise 0 → raise 1 → raise 2 → hide。
    @Test func fullCycleThenHide() {
        var cursor = -1
        let count = 3

        var r = WindowCycleDecision.advance(windowCount: count, cursor: cursor)
        #expect(r.step == .raise(index: 0)); cursor = r.nextCursor

        r = WindowCycleDecision.advance(windowCount: count, cursor: cursor)
        #expect(r.step == .raise(index: 1)); cursor = r.nextCursor

        r = WindowCycleDecision.advance(windowCount: count, cursor: cursor)
        #expect(r.step == .raise(index: 2)); cursor = r.nextCursor

        r = WindowCycleDecision.advance(windowCount: count, cursor: cursor)
        #expect(r.step == .hideAndReset)
    }
}
