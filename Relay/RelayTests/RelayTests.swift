//
//  RelayTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

struct RelayTests {

    @Test func appConfigurationCodableRoundTrip() throws {
        let activationConfig = ActivationConfig(
            name: "Return to Previous", notRunning: .launch, frontmost: .returnToPrevious
        )
        let app = TargetApp(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            lastKnownPath: "/Applications/Safari.app"
        )
        let binding = HotkeyBinding(
            app: app,
            hotkey: Hotkey(carbonKeyCode: 18, carbonModifiers: 4096),
            configID: activationConfig.id
        )
        let profile = Profile(name: "Coding", bindings: [binding])
        var settings = AppSettings()
        settings.defaultConfigID = activationConfig.id
        let config = AppConfiguration(
            profiles: [profile],
            activeProfileID: profile.id,
            activationConfigs: [activationConfig],
            settings: settings
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        #expect(decoded == config)
        #expect(decoded.profiles.first?.bindings.first?.configID == activationConfig.id)
        #expect(decoded.activeProfileID == profile.id)
    }

    @Test func makeDefaultSeedsConfigsAndDefaultID() {
        let config = AppConfiguration.makeDefault()
        #expect(config.activationConfigs.count == 4)
        // 默认 id 指向种子中的第一条（Return to Previous）。
        #expect(config.settings.defaultConfigID == config.activationConfigs.first?.id)
        #expect(config.activationConfigs.first?.name == "Return to Previous")
    }

    @Test func appSettingsDecodesLegacyJSONMissingMenuBarIcon() throws {
        // 旧版本（schemaVersion 2）写出的 settings 没有 menuBarIconName 键。合成 Decodable 会因缺键
        // 整体抛错 → PersistenceStore.load() 返回 nil → makeDefault() 清空用户数据。自定义 init(from:)
        // 必须容错：缺键回退默认 "command"，且不抛错。此测试锁住该数据安全保证。
        let legacyJSON = """
        {
          "showDockIcon": true,
          "launchAtLogin": true,
          "defaultConfigID": "\(UUID().uuidString)"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        #expect(decoded.menuBarIconName == AppSettings.defaultMenuBarIconName)
        #expect(decoded.showDockIcon == true)
        #expect(decoded.launchAtLogin == true)
    }

    @Test @MainActor func persistenceStoreSaveLoadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-test-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("config.json")
        let store = PersistenceStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.load() == nil) // 尚未写入

        var config = AppConfiguration.makeDefault()
        config.settings.launchAtLogin = true
        try store.save(config)

        let loaded = store.load()
        #expect(loaded == config)
        #expect(loaded?.settings.launchAtLogin == true)
    }
}
