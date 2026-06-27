//
//  AppModel.swift
//  Relay
//
//  应用的内存唯一真相（SoT）。持有配置，暴露 Profile 增删改与 active 切换，变更后去抖保存。
//  active profile 变化时未来会联动热键重注册（PR3 的 hook 已预留）。
//

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var configuration: AppConfiguration

    private let store: PersistenceStore
    private var saveTask: Task<Void, Never>?

    /// active profile（或其热键）变化时通知外部重注册热键。由 AppController 注入；测试中保持 nil。
    @ObservationIgnored var hotkeysDidChange: ((Profile?) -> Void)?

    /// 设置变化时通知外部应用副作用（登录项 / Dock 策略）。由 AppController 注入；测试中保持 nil。
    @ObservationIgnored var settingsDidChange: ((AppSettings) -> Void)?

    init(store: PersistenceStore? = nil) {
        let resolvedStore = store ?? PersistenceStore()
        self.store = resolvedStore
        self.configuration = resolvedStore.load() ?? .makeDefault()
    }

    // MARK: - Active profile

    var activeProfile: Profile? {
        guard let id = configuration.activeProfileID else { return nil }
        return configuration.profiles.first { $0.id == id }
    }

    /// 供菜单/选择器双向绑定的激活选择。
    var activeProfileSelection: UUID? {
        get { configuration.activeProfileID }
        set { if let newValue { setActiveProfile(newValue) } }
    }

    func setActiveProfile(_ id: UUID) {
        guard configuration.profiles.contains(where: { $0.id == id }) else { return }
        configuration.activeProfileID = id
        scheduleSave()
        hotkeysDidChange?(activeProfile) // 注销旧组、注册新组热键（由 AppController 接线）。
    }

    // MARK: - Profile CRUD

    @discardableResult
    func addProfile(name: String) -> Profile {
        let profile = Profile(name: name)
        configuration.profiles.append(profile)
        if configuration.activeProfileID == nil {
            configuration.activeProfileID = profile.id
        }
        scheduleSave()
        return profile
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
        configuration.profiles[index].name = name
        scheduleSave()
    }

    func deleteProfile(_ id: UUID) {
        configuration.profiles.removeAll { $0.id == id }
        if configuration.activeProfileID == id {
            configuration.activeProfileID = configuration.profiles.first?.id
            hotkeysDidChange?(activeProfile)
        }
        scheduleSave()
    }

    // MARK: - Binding CRUD（视图负责把 onDelete/onMove 解析为下面的调用，保持本类无 SwiftUI 依赖）

    func addBinding(_ binding: HotkeyBinding, to profileID: UUID) {
        guard let index = profileIndex(profileID) else { return }
        configuration.profiles[index].bindings.append(binding)
        didMutateProfile(profileID)
    }

    func updateBinding(_ binding: HotkeyBinding, in profileID: UUID) {
        guard let pIndex = profileIndex(profileID),
              let bIndex = configuration.profiles[pIndex].bindings.firstIndex(where: { $0.id == binding.id })
        else { return }
        configuration.profiles[pIndex].bindings[bIndex] = binding
        didMutateProfile(profileID)
    }

    func removeBindings(_ ids: Set<UUID>, from profileID: UUID) {
        guard let index = profileIndex(profileID) else { return }
        configuration.profiles[index].bindings.removeAll { ids.contains($0.id) }
        didMutateProfile(profileID)
    }

    /// 整体替换某 profile 的绑定（视图用于排序后回写）。
    func setBindings(_ bindings: [HotkeyBinding], for profileID: UUID) {
        guard let index = profileIndex(profileID) else { return }
        configuration.profiles[index].bindings = bindings
        didMutateProfile(profileID)
    }

    private func profileIndex(_ id: UUID) -> Int? {
        configuration.profiles.firstIndex { $0.id == id }
    }

    private func didMutateProfile(_ id: UUID) {
        scheduleSave()
        if id == configuration.activeProfileID {
            hotkeysDidChange?(activeProfile)
        }
    }

    // MARK: - Activation configs（全局共享、跨 Profile）

    var activationConfigs: [ActivationConfig] {
        configuration.activationConfigs
    }

    func activationConfig(id: UUID) -> ActivationConfig? {
        configuration.activationConfigs.first { $0.id == id }
    }

    /// 全局默认配置；id 失效时回退到第一条（始终存在 ≥1 条，见删除规则）。
    var defaultConfig: ActivationConfig? {
        activationConfig(id: configuration.settings.defaultConfigID)
            ?? configuration.activationConfigs.first
    }

    @discardableResult
    func addActivationConfig(name: String) -> ActivationConfig {
        // 新建一份合理的默认（与 "Launch or Focus" 一致），用户随后可编辑。
        let config = ActivationConfig(
            name: name, notRunning: .launch, background: .focus, frontmost: .none
        )
        configuration.activationConfigs.append(config)
        scheduleSave()
        return config
    }

    func renameActivationConfig(_ id: UUID, to name: String) {
        guard let index = configIndex(id) else { return }
        configuration.activationConfigs[index].name = name
        scheduleSave()
    }

    /// 整条更新一份激活配置（编辑器写回）。
    func updateActivationConfig(_ config: ActivationConfig) {
        guard let index = configIndex(config.id) else { return }
        configuration.activationConfigs[index] = config
        scheduleSave()
    }

    /// 跨所有 Profile 收集引用某配置的绑定（用于删除前的依赖确认）。
    func dependents(ofConfig id: UUID) -> [HotkeyBinding] {
        configuration.profiles.flatMap { profile in
            profile.bindings.filter { $0.configID == id }
        }
    }

    /// 删除一份激活配置（见 PRD「Delete & integrity rules」）：
    /// - 始终保留 ≥1 条（最后一条不可删）。
    /// - 若删的是当前全局默认：先把默认移到剩余的第一条。
    /// - 所有引用该配置的绑定改引新的全局默认。
    func deleteActivationConfig(_ id: UUID) {
        guard configuration.activationConfigs.count > 1,
              configIndex(id) != nil else { return }

        // 先确定删除后的回退默认（若删的是默认，移到剩余第一条）。
        let fallbackID: UUID
        if configuration.settings.defaultConfigID == id {
            fallbackID = configuration.activationConfigs.first { $0.id != id }!.id
            configuration.settings.defaultConfigID = fallbackID
        } else {
            fallbackID = configuration.settings.defaultConfigID
        }

        // 把所有引用该配置的绑定改引回退默认。
        reassignBindings(fromConfig: id, toConfig: fallbackID)

        configuration.activationConfigs.removeAll { $0.id == id }
        scheduleSave()
        // 若有 active profile 的绑定被改引，热键动作可能变化——重注册无害（实时解析配置）。
        hotkeysDidChange?(activeProfile)
    }

    private func reassignBindings(fromConfig oldID: UUID, toConfig newID: UUID) {
        for pIndex in configuration.profiles.indices {
            for bIndex in configuration.profiles[pIndex].bindings.indices
            where configuration.profiles[pIndex].bindings[bIndex].configID == oldID {
                configuration.profiles[pIndex].bindings[bIndex].configID = newID
            }
        }
    }

    private func configIndex(_ id: UUID) -> Int? {
        configuration.activationConfigs.firstIndex { $0.id == id }
    }

    // MARK: - Settings

    var settings: AppSettings {
        get { configuration.settings }
        set {
            configuration.settings = newValue
            scheduleSave()
            settingsDidChange?(newValue)
        }
    }

    // MARK: - Bulk replace（导入/恢复/重置的唯一批量入口，保持「所有变更经 AppModel」不变量）

    /// 用一份新 config 整体替换当前配置（导入备份 / 恢复快照 / 重置默认）。
    /// 先净化悬空引用（手改/旧备份可能引用不存在的 id），再赋值并触发既有副作用 hook + 立即落盘：
    /// - activeProfileID 不指向现存 profile → 取第一个 profile（无 profile 则 nil）。
    /// - settings.defaultConfigID 不指向现存激活配置 → 取第一条（无配置则保持原值，防御性）。
    func replaceConfiguration(_ new: AppConfiguration) {
        var sanitized = new

        if let activeID = sanitized.activeProfileID,
           !sanitized.profiles.contains(where: { $0.id == activeID }) {
            sanitized.activeProfileID = sanitized.profiles.first?.id
        } else if sanitized.activeProfileID == nil {
            sanitized.activeProfileID = sanitized.profiles.first?.id
        }

        if !sanitized.activationConfigs.contains(where: { $0.id == sanitized.settings.defaultConfigID }),
           let firstConfigID = sanitized.activationConfigs.first?.id {
            sanitized.settings.defaultConfigID = firstConfigID
        }

        configuration = sanitized
        // 重注册 active profile 热键、应用登录项/Dock 副作用，并立即落盘（避免去抖窗口内丢失批量替换）。
        hotkeysDidChange?(activeProfile)
        settingsDidChange?(configuration.settings)
        saveNow()
    }

    // MARK: - Persistence (debounced)

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = configuration
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? store.save(snapshot)
        }
    }

    /// 立即同步保存（如 App 退出前）。
    func saveNow() {
        saveTask?.cancel()
        try? store.save(configuration)
    }
}
