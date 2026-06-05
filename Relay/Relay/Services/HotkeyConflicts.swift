//
//  HotkeyConflicts.swift
//  Relay
//
//  组内快捷键冲突检测（纯函数、可单测）。这是 P1-11 中「可靠」的那一半；
//  「系统/他应用占用」无法程序化枚举（库不暴露注册失败），见 research/keyboardshortcuts.md。
//

import Foundation

nonisolated enum HotkeyConflicts {
    /// 同一 Hotkey 被 ≥2 个 binding 使用时，返回这些 binding 的 id。
    static func duplicateBindingIDs(in profile: Profile) -> Set<UUID> {
        var idsByHotkey: [Hotkey: [UUID]] = [:]
        for binding in profile.bindings {
            guard let hotkey = binding.hotkey else { continue }
            idsByHotkey[hotkey, default: []].append(binding.id)
        }
        return idsByHotkey.values
            .filter { $0.count > 1 }
            .reduce(into: Set<UUID>()) { $0.formUnion($1) }
    }
}
