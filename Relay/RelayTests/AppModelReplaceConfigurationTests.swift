//
//  AppModelReplaceConfigurationTests.swift
//  RelayTests
//
//  AppModel.replaceConfiguration 的净化保证：悬空的 activeProfileID / settings.defaultConfigID
//  在替换后落到有效 id（手改/旧备份可能引用不存在的 id），并触发副作用 hook。
//

import Testing
import Foundation
@testable import Relay

@MainActor
struct AppModelReplaceConfigurationTests {

    /// 用临时目录的 store 构造 model，避免触碰真实容器。
    private func makeModel() -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-replace-test-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceStore(fileURL: dir.appendingPathComponent("config.json"))
        return AppModel(store: store)
    }

    @Test func danglingActiveProfileIDFallsBackToFirstProfile() {
        let model = makeModel()
        let p1 = Profile(name: "A")
        let p2 = Profile(name: "B")
        let configs = ActivationConfig.makeDefaults()
        var settings = AppSettings()
        settings.defaultConfigID = configs[0].id

        // activeProfileID 指向不存在的 profile。
        let incoming = AppConfiguration(
            profiles: [p1, p2],
            activeProfileID: UUID(),
            activationConfigs: configs,
            settings: settings
        )

        model.replaceConfiguration(incoming)

        #expect(model.configuration.activeProfileID == p1.id)
    }

    @Test func nilActiveProfileIDWithProfilesGetsFirst() {
        let model = makeModel()
        let p1 = Profile(name: "Only")
        let configs = ActivationConfig.makeDefaults()
        var settings = AppSettings()
        settings.defaultConfigID = configs[0].id

        let incoming = AppConfiguration(
            profiles: [p1],
            activeProfileID: nil,
            activationConfigs: configs,
            settings: settings
        )

        model.replaceConfiguration(incoming)

        #expect(model.configuration.activeProfileID == p1.id)
    }

    @Test func danglingDefaultConfigIDFallsBackToFirstConfig() {
        let model = makeModel()
        let profile = Profile(name: "A")
        let configs = ActivationConfig.makeDefaults()
        var settings = AppSettings()
        // defaultConfigID 指向不存在的激活配置。
        settings.defaultConfigID = UUID()

        let incoming = AppConfiguration(
            profiles: [profile],
            activeProfileID: profile.id,
            activationConfigs: configs,
            settings: settings
        )

        model.replaceConfiguration(incoming)

        #expect(model.configuration.settings.defaultConfigID == configs.first?.id)
    }

    @Test func validReferencesArePreserved() {
        let model = makeModel()
        let p1 = Profile(name: "A")
        let p2 = Profile(name: "B")
        let configs = ActivationConfig.makeDefaults()
        var settings = AppSettings()
        settings.defaultConfigID = configs[1].id

        let incoming = AppConfiguration(
            profiles: [p1, p2],
            activeProfileID: p2.id,
            activationConfigs: configs,
            settings: settings
        )

        model.replaceConfiguration(incoming)

        // 有效引用不应被改写。
        #expect(model.configuration.activeProfileID == p2.id)
        #expect(model.configuration.settings.defaultConfigID == configs[1].id)
    }

    @Test func firesHooksOnReplace() {
        let model = makeModel()
        var hotkeysFired = false
        var settingsFired = false
        model.hotkeysDidChange = { _ in hotkeysFired = true }
        model.settingsDidChange = { _ in settingsFired = true }

        model.replaceConfiguration(.makeDefault())

        #expect(hotkeysFired)
        #expect(settingsFired)
    }
}
