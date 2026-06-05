//
//  Hotkey+KeyboardShortcuts.swift
//  Relay
//
//  我方 Hotkey（carbon 码，库无关）与 KeyboardShortcuts.Shortcut 的桥接。
//  持久化只用我方 Hotkey；本扩展仅在运行时注册/展示时使用。
//

import KeyboardShortcuts

extension Hotkey {
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(carbonKeyCode: shortcut.carbonKeyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    var keyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
    }

    /// 人类可读，如 "⇧⌘A"。
    var displayString: String {
        keyboardShortcut.description
    }
}
