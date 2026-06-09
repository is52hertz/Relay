//
//  AppActivationDecisionTests.swift
//  RelayTests
//
//  覆盖 RuntimeState × ActivationConfig 的纯决策映射，含新增的 launchWithoutFocus / quit，
//  以及后台占位（一律 focus）与前台 minimize 占位（退化为 none）。
//

import Foundation
import Testing
@testable import Relay

struct AppActivationDecisionTests {
    private typealias Action = AppActivationDecision.Action

    /// 构造一份指定三段动作的配置。
    private func config(
        notRunning: NotRunningAction,
        background: BackgroundAction = .focus,
        frontmost: FrontmostAction
    ) -> ActivationConfig {
        ActivationConfig(name: "T", notRunning: notRunning, background: background, frontmost: frontmost)
    }

    @Test func notInstalledAlwaysMarksInvalid() {
        let c = config(notRunning: .launch, frontmost: .returnToPrevious)
        #expect(AppActivationDecision.action(for: .notInstalled, config: c) == .markInvalid)
    }

    @Test func notRunningMapsPerConfig() {
        #expect(AppActivationDecision.action(
            for: .notRunning, config: config(notRunning: .launch, frontmost: .none)) == .launch)
        #expect(AppActivationDecision.action(
            for: .notRunning, config: config(notRunning: .launchWithoutFocus, frontmost: .none)) == .launchWithoutFocus)
        #expect(AppActivationDecision.action(
            for: .notRunning, config: config(notRunning: .none, frontmost: .none)) == .none)
    }

    @Test func runningAlwaysFocuses_backgroundIsPlaceholder() {
        // 后台占位：无论 background 配置为何，引擎一律 focus。
        for bg in BackgroundAction.allCases {
            let c = config(notRunning: .launch, background: bg, frontmost: .none)
            #expect(AppActivationDecision.action(for: .running, config: c) == .focus)
        }
    }

    @Test func frontmostMapsPerConfig() {
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .returnToPrevious)) == .returnToPrevious)
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .hide)) == .hide)
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .quit)) == .quit)
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .none)) == .none)
        // minimize 占位：退化为 none。
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .minimize)) == .none)
    }

    /// 4 个种子默认配置必须 1:1 复刻旧 FocusBehavior 矩阵（未启动 / 前台）。
    @Test func seededDefaultsReproduceLegacyMatrix() {
        let defaults = ActivationConfig.makeDefaults()
        func byName(_ name: String) -> ActivationConfig { defaults.first { $0.name == name }! }

        let returnToPrev = byName("Return to Previous")
        #expect(AppActivationDecision.action(for: .notRunning, config: returnToPrev) == .launch)
        #expect(AppActivationDecision.action(for: .running, config: returnToPrev) == .focus)
        #expect(AppActivationDecision.action(for: .frontmost, config: returnToPrev) == .returnToPrevious)

        let launchOrFocus = byName("Launch or Focus")
        #expect(AppActivationDecision.action(for: .notRunning, config: launchOrFocus) == .launch)
        #expect(AppActivationDecision.action(for: .running, config: launchOrFocus) == .focus)
        #expect(AppActivationDecision.action(for: .frontmost, config: launchOrFocus) == .none)

        let toggleHide = byName("Toggle Hide")
        #expect(AppActivationDecision.action(for: .notRunning, config: toggleHide) == .launch)
        #expect(AppActivationDecision.action(for: .running, config: toggleHide) == .focus)
        #expect(AppActivationDecision.action(for: .frontmost, config: toggleHide) == .hide)

        let focusOnly = byName("Focus Only")
        #expect(AppActivationDecision.action(for: .notRunning, config: focusOnly) == .none)
        #expect(AppActivationDecision.action(for: .running, config: focusOnly) == .focus)
        #expect(AppActivationDecision.action(for: .frontmost, config: focusOnly) == .none)
    }
}
