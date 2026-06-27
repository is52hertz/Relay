//
//  HotkeyRegistrationService.swift
//  Relay
//
//  只为「当前 active profile」注册全局热键；切换 profile 时注销旧组、注册新组。
//  每个 binding 用动态 KeyboardShortcuts.Name(binding.id)；SoT 仍是我方 model。
//  组内重复的 Hotkey 只注册第一个（其余由 HotkeyConflicts 在 UI 标示）。
//
//  另有一条「全局应用命令」注册路径（AppCommand）：常驻、与 Profile 无关，
//  deactivateAll() 不会清除它（详见各自方法注释）。这是对「只注册当前 Profile」规则的
//  有意补充——应用控制命令属于另一类注册，仍走 KeyboardShortcuts（无 CGEventTap）。
//

import Foundation
import KeyboardShortcuts

/// AppCommand → KeyboardShortcuts.Name 的桥接（Name 属库类型，故放在 import 库的服务层，
/// 让 AppCommand 自身保持库无关）。同一命令始终得到同一个稳定 Name。
extension AppCommand {
    var shortcutName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(shortcutNameIdentifier)
    }
}

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

    /// 全局应用命令的触发动作（由 AppController 注入）。常驻，独立于 Profile 绑定。
    /// handler 只装一次（库 handler 不可反注册），运行时读取这里的最新闭包。
    private var appCommandActions: [AppCommand: () -> Void] = [:]
    /// 已安装过 onKeyDown 的应用命令 Name 集合（与 handlersInstalled 同理，仅作用于 AppCommand）。
    private var appCommandHandlersInstalled: Set<AppCommand> = []

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
        // 只注销「Profile 绑定」用的 Name；全局应用命令（AppCommand）的 Name 不在 activeNames 里，
        // 故切换 Profile 时不会被清掉——切换菜单栏图标的热键始终常驻可用（F-B 的核心要求）。
        for name in activeNames {
            KeyboardShortcuts.setShortcut(nil, for: name)
            KeyboardShortcuts.disable(name)
        }
        activeNames.removeAll()
        bindingsByName.removeAll()
    }

    /// 释放「全部」全局热键——Profile 绑定 **和** 常驻应用命令（AppCommand）。专用于 relaunch / terminate 前。
    /// 与 deactivateAll() 的区别：deactivateAll() 只服务「切 Profile」，必须保留常驻命令（切换菜单栏图标的热键常驻可用）；
    /// 而 `open -n` 拉起新实例、终止旧实例期间，新旧进程短暂重叠，旧进程若仍持有任一 Carbon 热键，
    /// 新进程注册同组合可能失败且 KeyboardShortcuts 吞掉失败不重试（切语言后该热键失效；菜单图标隐藏时还会把用户锁在外面）。
    /// 故此处比 deactivateAll() 多清应用命令——遍历 AppCommand.allCases 释放每个命令的快捷键。
    func releaseAllForRelaunch() {
        deactivateAll()
        for command in AppCommand.allCases {
            let name = command.shortcutName
            KeyboardShortcuts.setShortcut(nil, for: name)
            KeyboardShortcuts.disable(name)
        }
    }

    // MARK: - 全局应用命令（常驻，与 Profile 无关）

    /// 注入某个应用命令被触发时执行的动作（如「翻转菜单栏图标可见性」）。由 AppController 在组合根接线。
    func setAppCommandAction(_ command: AppCommand, action: @escaping () -> Void) {
        appCommandActions[command] = action
    }

    /// 设置/清除某个应用命令的全局热键。hotkey 为 nil 时注销（setShortcut(nil) + disable）。
    /// handler 只装一次；deactivateAll() 不触碰它，故 Profile 切换不影响。
    func setAppCommandShortcut(_ command: AppCommand, to hotkey: Hotkey?) {
        let name = command.shortcutName
        installAppCommandHandlerIfNeeded(command)
        if let hotkey {
            KeyboardShortcuts.setShortcut(hotkey.keyboardShortcut, for: name)
            KeyboardShortcuts.enable(name)
        } else {
            KeyboardShortcuts.setShortcut(nil, for: name)
            KeyboardShortcuts.disable(name)
        }
        // 注意（冲突风险，见 PRD「Conflict risk」）：若某 Profile 绑定用了与本命令相同的物理组合，
        // Carbon RegisterEventHotKey 行为未定义/先注册者胜。MVP 不做自动消解，仅此说明。
    }

    private func installAppCommandHandlerIfNeeded(_ command: AppCommand) {
        guard appCommandHandlersInstalled.insert(command).inserted else { return }
        let name = command.shortcutName
        KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.appCommandActions[command]?()
            }
        }
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
