//
//  AboutVersionStringTests.swift
//  RelayTests
//
//  关于页版本串纯函数：验证短版本号 + 构建号被代入（构建号以括号包裹）。
//  不断言 "Version" 前缀字面量——它已本地化，测试进程语言随系统而变（可能是中文），
//  故只校验代入结果，与当前 UI 语言无关。
//

import Testing
import Foundation
@testable import Relay

@MainActor
struct AboutVersionStringTests {

    @Test func substitutesShortAndBracketedBuild() {
        let s = AboutSettingsView.versionString(short: "1.0", build: "1")
        #expect(s.contains("1.0"))
        // 构建号带括号（半角或中文全角）——确认它是被格式串包裹后代入的。
        #expect(s.contains("(1)") || s.contains("（1）"))
    }

    @Test func handlesMultiComponentVersions() {
        let s = AboutSettingsView.versionString(short: "2.3.1", build: "42")
        #expect(s.contains("2.3.1"))
        #expect(s.contains("(42)") || s.contains("（42）"))
    }
}
