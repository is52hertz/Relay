//
//  HotkeyConflictsTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

struct HotkeyConflictsTests {

    private let configID = UUID()

    private func app(_ name: String) -> TargetApp {
        TargetApp(bundleIdentifier: "com.test.\(name)", displayName: name)
    }

    private func binding(_ name: String, hotkey: Hotkey?) -> HotkeyBinding {
        HotkeyBinding(app: app(name), hotkey: hotkey, configID: configID)
    }

    @Test func noConflictsWhenAllDistinct() {
        let profile = Profile(name: "P", bindings: [
            binding("a", hotkey: Hotkey(carbonKeyCode: 18, carbonModifiers: 4096)),
            binding("b", hotkey: Hotkey(carbonKeyCode: 19, carbonModifiers: 4096)),
            binding("c", hotkey: nil),
        ])
        #expect(HotkeyConflicts.duplicateBindingIDs(in: profile).isEmpty)
    }

    @Test func detectsDuplicatesAndIgnoresEmptyHotkeys() {
        let dup = Hotkey(carbonKeyCode: 18, carbonModifiers: 4096)
        let b1 = binding("a", hotkey: dup)
        let b2 = binding("b", hotkey: dup)
        let b3 = binding("c", hotkey: Hotkey(carbonKeyCode: 20, carbonModifiers: 4096))
        let b4 = binding("d", hotkey: nil)
        let profile = Profile(name: "P", bindings: [b1, b2, b3, b4])

        let conflicts = HotkeyConflicts.duplicateBindingIDs(in: profile)
        #expect(conflicts == Set([b1.id, b2.id]))
    }
}
