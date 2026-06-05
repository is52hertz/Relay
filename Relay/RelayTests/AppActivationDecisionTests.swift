//
//  AppActivationDecisionTests.swift
//  RelayTests
//
//  覆盖 FocusBehavior 行为矩阵：4 运行态 × 4 行为 = 16 组合。
//

import Testing
@testable import Relay

struct AppActivationDecisionTests {
    private typealias Action = AppActivationDecision.Action

    @Test func notInstalledAlwaysMarksInvalid() {
        for behavior in FocusBehavior.allCases {
            #expect(AppActivationDecision.action(for: .notInstalled, behavior: behavior) == .markInvalid)
        }
    }

    @Test func notRunningLaunchesExceptFocusOnly() {
        for behavior in FocusBehavior.allCases {
            let expected: Action = behavior == .focusOnly ? .none : .launch
            #expect(AppActivationDecision.action(for: .notRunning, behavior: behavior) == expected)
        }
    }

    @Test func runningAlwaysFocuses() {
        for behavior in FocusBehavior.allCases {
            #expect(AppActivationDecision.action(for: .running, behavior: behavior) == .focus)
        }
    }

    @Test func frontmostFollowsBehavior() {
        #expect(AppActivationDecision.action(for: .frontmost, behavior: .returnToPrevious) == .returnToPrevious)
        #expect(AppActivationDecision.action(for: .frontmost, behavior: .toggleHide) == .hide)
        #expect(AppActivationDecision.action(for: .frontmost, behavior: .launchOrFocus) == .none)
        #expect(AppActivationDecision.action(for: .frontmost, behavior: .focusOnly) == .none)
    }
}
