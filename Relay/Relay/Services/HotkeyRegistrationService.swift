//
//  HotkeyRegistrationService.swift
//  Relay
//
//  只为「当前 active profile」注册全局热键；切换 profile 时注销旧组、注册新组。
//  每个 binding 用动态 KeyboardShortcuts.Name(binding.id)；SoT 仍是我方 model。
//  组内重复的 Hotkey 只注册第一个（其余由 HotkeyConflicts 在 UI 标示）。
//

import Foundation
import KeyboardShortcuts

@MainActor
final class HotkeyRegistrationService {
    private let activation: AppActivationService
    /// 触发时按 binding.configID 解析最新的激活配置（由 AppController 注入，读 model 的全局配置表）。
    /// 配置编辑不触发 hotkeysDidChange，故在触发时实时解析以拿到最新配置。
    private let configResolver: (UUID) -> ActivationConfig?

    private var activeNames: [KeyboardShortcuts.Name] = []
    private var bindingsByName: [KeyboardShortcuts.Name: HotkeyBinding] = [:]
    /// 已安装过 onKeyDown 的 Name（库的 handler 无显式反注册，故每个 Name 只装一次，
    /// 通过 setShortcut(nil)/disable 控制是否触发；handler 内读 bindingsByName 取最新动作）。
    private var handlersInstalled: Set<KeyboardShortcuts.Name> = []

    init(activation: AppActivationService, configResolver: @escaping (UUID) -> ActivationConfig?) {
        self.activation = activation
        self.configResolver = configResolver
    }

    func activate(_ profile: Profile?) {
        deactivateAll()
        guard let profile else { return }
        var usedHotkeys: Set<Hotkey> = []
        for binding in profile.bindings {
            guard let hotkey = binding.hotkey else { continue }
            guard usedHotkeys.insert(hotkey).inserted else { continue } // 跳过组内重复
            let name = KeyboardShortcuts.Name(binding.id.uuidString)
            bindingsByName[name] = binding
            activeNames.append(name)
            KeyboardShortcuts.setShortcut(hotkey.keyboardShortcut, for: name)
            KeyboardShortcuts.enable(name)
            installHandlerIfNeeded(for: name)
        }
    }

    func deactivateAll() {
        for name in activeNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
            KeyboardShortcuts.disable(name)
        }
        activeNames.removeAll()
        bindingsByName.removeAll()
    }

    private func installHandlerIfNeeded(for name: KeyboardShortcuts.Name) {
        guard handlersInstalled.insert(name).inserted else { return }
        KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let binding = self.bindingsByName[name],
                      let config = self.configResolver(binding.configID) else { return }
                self.activation.handle(binding, config: config)
            }
        }
    }
}
