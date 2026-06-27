//
//  MenuBarIconVisibilityTests.swift
//  RelayTests
//
//  覆盖 schema-4 新增的菜单栏图标可见性 + 全局切换热键：
//  - schema-3 旧 JSON 向后兼容解码（缺键 → showMenuBarIcon true / menuBarToggleHotkey nil，不丢数据）。
//  - 编码→解码 round-trip 保留新字段。
//  - 锁定守卫纯逻辑（无热键不能隐藏）。
//  - AppCommand → KeyboardShortcuts.Name 标识符稳定且互不相同。
//

import Testing
import Foundation
@testable import Relay

struct MenuBarIconVisibilityTests {

    // MARK: - schema-4 向后兼容解码

    @Test func appSettingsDecodesSchema3JSONMissingMenuBarVisibilityKeys() throws {
        // schema 3 写出的 settings 没有 showMenuBarIcon / menuBarToggleHotkey。
        // 自定义 init(from:) 必须容错：缺键回退到「图标可见、无切换热键」，老用户不丢图标、不抛错。
        let legacyJSON = """
        {
          "showDockIcon": false,
          "launchAtLogin": false,
          "defaultConfigID": "\(UUID().uuidString)",
          "menuBarIconName": "command"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        #expect(decoded.showMenuBarIcon == true)
        #expect(decoded.menuBarToggleHotkey == nil)
    }

    @Test func appSettingsRoundTripPreservesMenuBarVisibilityFields() throws {
        var settings = AppSettings()
        settings.showMenuBarIcon = false
        settings.menuBarToggleHotkey = Hotkey(carbonKeyCode: 17, carbonModifiers: 4352)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.showMenuBarIcon == false)
        #expect(decoded.menuBarToggleHotkey == settings.menuBarToggleHotkey)
    }

    @Test func currentSchemaVersionIsFour() {
        #expect(AppConfiguration.currentSchemaVersion == 4)
    }

    // MARK: - 锁定守卫（R5，纯逻辑）

    @Test func cannotHideWithoutToggleHotkey() {
        // 隐藏（visible == false）且无热键 → 不允许（防锁死）。
        #expect(MenuBarIconLockout.canSet(visible: false, toggleHotkey: nil) == false)
    }

    @Test func canHideWhenToggleHotkeySet() {
        let hotkey = Hotkey(carbonKeyCode: 17, carbonModifiers: 4352)
        #expect(MenuBarIconLockout.canSet(visible: false, toggleHotkey: hotkey) == true)
    }

    @Test func canAlwaysShow() {
        #expect(MenuBarIconLockout.canSet(visible: true, toggleHotkey: nil) == true)
        #expect(MenuBarIconLockout.canSet(visible: true, toggleHotkey: Hotkey(carbonKeyCode: 0, carbonModifiers: 0)) == true)
    }

    // MARK: - AppCommand → Name 标识符

    @Test func appCommandShortcutNameIdentifiersAreStableAndDistinct() {
        // 标识符稳定（不能随意改，会让已存在的注册失配）且各命令互不相同。
        #expect(AppCommand.toggleMenuBarIcon.shortcutNameIdentifier == "appCommand.toggleMenuBarIcon")
        let identifiers = AppCommand.allCases.map(\.shortcutNameIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    // MARK: - AppModel 行为（锁定守卫 + 清热键自动唤回）

    @MainActor
    private func makeModel() -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-menubar-test-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceStore(fileURL: dir.appendingPathComponent("config.json"))
        return AppModel(store: store)
    }

    @Test @MainActor func setMenuBarIconVisibleHonorsLockout() {
        let model = makeModel()
        // 无热键时请求隐藏被忽略（守卫兜底）。
        model.setMenuBarIconVisible(false)
        #expect(model.settings.showMenuBarIcon == true)

        // 设了热键后可隐藏。
        model.setMenuBarToggleHotkey(Hotkey(carbonKeyCode: 17, carbonModifiers: 4352))
        model.setMenuBarIconVisible(false)
        #expect(model.settings.showMenuBarIcon == false)
    }

    @Test @MainActor func clearingToggleHotkeyWhileHiddenRestoresIcon() {
        let model = makeModel()
        model.setMenuBarToggleHotkey(Hotkey(carbonKeyCode: 17, carbonModifiers: 4352))
        model.setMenuBarIconVisible(false)
        #expect(model.settings.showMenuBarIcon == false)

        // 清除热键时图标是隐藏的 → 自动唤回图标，避免锁死。
        model.setMenuBarToggleHotkey(nil)
        #expect(model.settings.menuBarToggleHotkey == nil)
        #expect(model.settings.showMenuBarIcon == true)
    }

    // MARK: - 批量替换重申锁定不变量（导入绕过逐次守卫）

    @Test @MainActor func replaceConfigurationForcesIconVisibleWhenStranded() {
        let model = makeModel()
        // 手改 schema-4 备份：图标隐藏且无切换热键 → 导入后应被强制唤回，防锁死。
        var settings = AppSettings()
        settings.showMenuBarIcon = false
        settings.menuBarToggleHotkey = nil
        let incoming = AppConfiguration(
            profiles: [Profile(name: "A")],
            activeProfileID: nil,
            activationConfigs: ActivationConfig.makeDefaults(),
            settings: settings
        )

        model.replaceConfiguration(incoming)

        #expect(model.configuration.settings.showMenuBarIcon == true)
    }

    @Test @MainActor func replaceConfigurationPreservesValidHiddenIcon() {
        let model = makeModel()
        // 隐藏 + 已设热键是合法状态 → 不应被强制唤回。
        let hotkey = Hotkey(carbonKeyCode: 17, carbonModifiers: 4352)
        var settings = AppSettings()
        settings.showMenuBarIcon = false
        settings.menuBarToggleHotkey = hotkey
        let incoming = AppConfiguration(
            profiles: [Profile(name: "A")],
            activeProfileID: nil,
            activationConfigs: ActivationConfig.makeDefaults(),
            settings: settings
        )

        model.replaceConfiguration(incoming)

        #expect(model.configuration.settings.showMenuBarIcon == false)
        #expect(model.configuration.settings.menuBarToggleHotkey == hotkey)
    }
}
