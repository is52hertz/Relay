//
//  HotkeyConflictsTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

struct HotkeyConflictsTests {

    private func app(_ name: String) -> TargetApp {
        TargetApp(bundleIdentifier: "com.test.\(name)", displayName: name)
    }

    @Test func noConflictsWhenAllDistinct() {
        let profile = Profile(name: "P", bindings: [
            HotkeyBinding(app: app("a"), hotkey: Hotkey(carbonKeyCode: 18, carbonModifiers: 4096)),
            HotkeyBinding(app: app("b"), hotkey: Hotkey(carbonKeyCode: 19, carbonModifiers: 4096)),
            HotkeyBinding(app: app("c"), hotkey: nil),
        ])
        #expect(HotkeyConflicts.duplicateBindingIDs(in: profile).isEmpty)
    }

    @Test func detectsDuplicatesAndIgnoresEmptyHotkeys() {
        let dup = Hotkey(carbonKeyCode: 18, carbonModifiers: 4096)
        let b1 = HotkeyBinding(app: app("a"), hotkey: dup)
        let b2 = HotkeyBinding(app: app("b"), hotkey: dup)
        let b3 = HotkeyBinding(app: app("c"), hotkey: Hotkey(carbonKeyCode: 20, carbonModifiers: 4096))
        let b4 = HotkeyBinding(app: app("d"), hotkey: nil)
        let profile = Profile(name: "P", bindings: [b1, b2, b3, b4])

        let conflicts = HotkeyConflicts.duplicateBindingIDs(in: profile)
        #expect(conflicts == Set([b1.id, b2.id]))
    }
}
