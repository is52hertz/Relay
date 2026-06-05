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

    // MARK: - Settings

    var settings: AppSettings {
        get { configuration.settings }
        set {
            configuration.settings = newValue
            scheduleSave()
        }
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
