//
//  AppActivationDecisionTests.swift
//  RelayTests
//
//  覆盖 RuntimeState × ActivationConfig 的纯决策映射，含 launchWithoutFocus / quit，
//  以及现已接入的后台三态（focus / showWithoutFocus / minimize）与前台 minimize。
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

    @Test func runningMapsPerBackgroundConfig() {
        // 后台三态均已接入：决策层按配置直出对应动作（信任态/降级是执行层关注点）。
        #expect(AppActivationDecision.action(
            for: .running, config: config(notRunning: .launch, background: .focus, frontmost: .none)) == .focus)
        #expect(AppActivationDecision.action(
            for: .running, config: config(notRunning: .launch, background: .showWithoutFocus, frontmost: .none)) == .showWithoutFocus)
        #expect(AppActivationDecision.action(
            for: .running, config: config(notRunning: .launch, background: .minimize, frontmost: .none)) == .minimize)
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
        // minimize 现已接入：决策层产出 .minimize（执行层处理 AX 信任/降级）。
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .minimize)) == .minimize)
        // cycleWindowsThenHide：决策层只路由到 .cycleWindowsOrHide，游标/AX 由执行层处理。
        #expect(AppActivationDecision.action(
            for: .frontmost, config: config(notRunning: .launch, frontmost: .cycleWindowsThenHide)) == .cycleWindowsOrHide)
    }

    @Test func allActionsAreImplemented() {
        for a in NotRunningAction.allCases { #expect(a.id == a.rawValue) }
        #expect(BackgroundAction.allCases.allSatisfy { $0.isImplemented })
        #expect(FrontmostAction.allCases.allSatisfy { $0.isImplemented })
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
