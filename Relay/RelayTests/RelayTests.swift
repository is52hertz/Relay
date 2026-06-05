//
//  RelayTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

struct RelayTests {

    @Test func appConfigurationCodableRoundTrip() throws {
        let app = TargetApp(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            lastKnownPath: "/Applications/Safari.app"
        )
        let binding = HotkeyBinding(
            app: app,
            hotkey: Hotkey(carbonKeyCode: 18, carbonModifiers: 4096),
            behavior: .returnToPrevious
        )
        let profile = Profile(name: "Coding", bindings: [binding])
        let config = AppConfiguration(profiles: [profile], activeProfileID: profile.id)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        #expect(decoded == config)
        #expect(decoded.profiles.first?.bindings.first?.behavior == .returnToPrevious)
        #expect(decoded.activeProfileID == profile.id)
    }

    @Test func focusBehaviorDefaults() {
        #expect(FocusBehavior.defaultBehavior == .returnToPrevious)
        #expect(FocusBehavior.allCases.count == 4)
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
