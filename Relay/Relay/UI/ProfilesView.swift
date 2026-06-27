//
//  ProfilesView.swift
//  Relay
//
//  主窗口的 Profiles 管理界面：NavigationSplitView。侧栏 = Profile 列表（增/改名/删/设为 active），
//  详情 = 该 Profile 的绑定编辑（BindingsDetailView）。
//  带 "Add Profile" 工具栏，必须住在 Window 里（Settings 场景会丢自定义 toolbar）。
//

import SwiftUI

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedProfileID: UUID?
    // 行内改名状态：正在改名的 profile、编辑文本、以及进入改名的时间戳（用于二次 Return 计时消歧）。
    @State private var renamingProfileID: UUID?
    @State private var renameText: String = ""
    @State private var renameStartedAt: Date = .distantPast
    // 行内 TextField 的焦点；改名时设为 true 以聚焦输入框。
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        // .constant(.doubleColumn)：侧栏始终可见，不允许折叠；
        // 配合下方 .toolbar(removing: .sidebarToggle) 去掉系统折叠按钮，
        // 避免折叠时工具栏按钮跳到红绿灯旁、玻璃胶囊浮现的突兀重排。
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(selection: $selectedProfileID) {
                Section("Profiles") {
                    ForEach(model.configuration.profiles) { profile in
                        ProfileRow(
                            name: profile.name,
                            isActive: profile.id == model.configuration.activeProfileID,
                            isSelected: profile.id == selectedProfileID,
                            isRenaming: profile.id == renamingProfileID,
                            renameText: $renameText,
                            renameFieldFocused: $renameFieldFocused,
                            onSubmitRename: { commitRename(profile) },
                            onCancelRename: cancelRename
                        )
                        .tag(profile.id)
                        .contextMenu {
                            // .keyboardShortcut 仅用于在菜单项右侧显示对应字形提示，
                            // 与下方真正的按键处理器（.onDeleteCommand / .onKeyPress(.return) / ⌘Return 隐藏按钮）一致：
                            Button("Set as Active") { model.setActiveProfile(profile.id) }
                                .disabled(profile.id == model.configuration.activeProfileID)
                                .keyboardShortcut(.return, modifiers: .command) // ⌘↩
                            // 纯回车：.keyboardShortcut 默认带 .command，需显式传 modifiers: [] 才显示 ↩。
                            Button("Rename…") { startRename(profile) }
                                .keyboardShortcut(.return, modifiers: []) // ↩
                            Divider()
                            // .delete 即退格/删除键，显示 ⌫。
                            Button("Delete", role: .destructive) { delete(profile) }
                                .keyboardShortcut(.delete, modifiers: []) // ⌫
                        }
                    }
                }
            }
            // Delete/Backspace（List 聚焦且有选中行时触发）→ 即时删除，与 context menu Delete 一致。
            .onDeleteCommand(perform: deleteSelected)
            // ⌘Return → 直接把选中 Profile 设为 active，不进改名。
            // 用一个隐藏的快捷键按钮承载，避免在 List 行上叠加全局事件监听。
            .background {
                Button("", action: setSelectedActive)
                    .keyboardShortcut(.return, modifiers: .command)
                    .hidden()
            }
            // Return（无修饰）→ 立即进入行内改名。
            .onKeyPress(.return) {
                if let id = selectedProfileID,
                   renamingProfileID == nil,
                   let profile = model.configuration.profiles.first(where: { $0.id == id }) {
                    startRename(profile)
                    return .handled
                }
                return .ignored
            }
            // 失焦取消：点击别处使输入框失焦时退出改名态。延后到下一轮 runloop 再判断，
            // 让 Return 提交路径（onSubmit 会先把 renamingProfileID 置 nil）优先生效，避免提交被误判为取消。
            .onChange(of: renameFieldFocused) { _, focused in
                guard !focused, renamingProfileID != nil else { return }
                let editing = renamingProfileID
                DispatchQueue.main.async {
                    if renamingProfileID == editing { cancelRename() }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                // flexible spacer 顶在前面，把 Add Profile 推到侧栏工具栏区的右端
                // （侧栏右上角），而非默认贴着红绿灯的左端。
                // ToolbarSpacer 是 macOS 26+ API；旧系统（部署目标 15）降级为默认位置——仅外观差异，
                // 功能不变。toolbar content builder 支持 if #available（不同于 SceneBuilder）。
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.flexible)
                }
                ToolbarItem {
                    Button(action: addProfile) {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .help("Create a new profile")
                }
            }
        } detail: {
            if let profile = selectedProfile {
                BindingsDetailView(profile: profile)
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "square.stack.3d.up",
                    description: Text("Select a profile, or create one.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var selectedProfile: Profile? {
        let id = selectedProfileID ?? model.configuration.activeProfileID
        return model.configuration.profiles.first { $0.id == id }
    }

    private func addProfile() {
        let profile = model.addProfile(name: String(localized: "New Profile"))
        selectedProfileID = profile.id
    }

    private func delete(_ profile: Profile) {
        if selectedProfileID == profile.id { selectedProfileID = nil }
        model.deleteProfile(profile.id)
    }

    // 删除当前选中的 Profile（供 .onDeleteCommand 调用）。
    private func deleteSelected() {
        guard let id = selectedProfileID,
              let profile = model.configuration.profiles.first(where: { $0.id == id }) else { return }
        delete(profile)
    }

    // ⌘Return：把当前选中 Profile 设为 active。
    private func setSelectedActive() {
        guard let id = selectedProfileID else { return }
        model.setActiveProfile(id)
    }

    // 进入行内改名：记录初始名称与开始时间，并请求聚焦输入框。
    private func startRename(_ profile: Profile) {
        renameText = profile.name
        renameStartedAt = Date()
        renamingProfileID = profile.id
        renameFieldFocused = true
    }

    // 提交行内改名，并做二次 Return 计时消歧：
    // 进入改名后 300ms 内的 onSubmit 视为"两次 Return"手势 → 取消改名并设为 active；
    // 否则正常提交改名（trim 后非空才写入）。
    private func commitRename(_ profile: Profile) {
        guard renamingProfileID == profile.id else { return }
        if Date().timeIntervalSince(renameStartedAt) < 0.3 {
            // 二次 Return：取消本次改名，改为激活该 Profile。
            renamingProfileID = nil
            model.setActiveProfile(profile.id)
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            model.renameProfile(profile.id, to: trimmed)
        }
        renamingProfileID = nil
    }

    // 取消行内改名（Esc 或失焦时调用）：不写入，直接退出改名态。
    private func cancelRename() {
        renamingProfileID = nil
    }
}

private struct ProfileRow: View {
    let name: String
    let isActive: Bool
    // 该行是否被选中，用于让 active 闪电在选中蓝底上变白。
    let isSelected: Bool
    // 该行是否处于行内改名态。
    let isRenaming: Bool
    @Binding var renameText: String
    var renameFieldFocused: FocusState<Bool>.Binding
    let onSubmitRename: () -> Void
    let onCancelRename: () -> Void

    var body: some View {
        HStack {
            if isRenaming {
                // Finder 式行内改名：聚焦输入框、Return 提交、Esc/失焦取消。
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused(renameFieldFocused)
                    .onSubmit(onSubmitRename)
                    // Esc 取消本次改名。
                    .onExitCommand(perform: onCancelRename)
            } else {
                Text(name)
            }
            Spacer()
            if isActive {
                // 闪电统一放大（选中/未选中同尺寸）；颜色随选中态：选中蓝底时白色、否则 tint 蓝。
                // 用 AnyShapeStyle 抹平 Color.white 与 .tint 的类型差异。
                Image(systemName: "bolt.fill")
                    .font(.body)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .accessibilityLabel("Active profile")
            }
        }
    }
}
