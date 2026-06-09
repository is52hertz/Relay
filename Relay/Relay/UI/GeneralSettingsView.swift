//
//  GeneralSettingsView.swift
//  Relay
//
//  通用设置：登录启动、Dock 图标、新建绑定的默认激活配置，以及全局「激活配置表」编辑。
//  配置表（增删改名 + 每状态动作）写回 AppModel；后台列与前台「最小化」为占位禁用（见 PRD）。
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var selection: Set<UUID> = []
    /// 待删除且有依赖的配置（触发两步确认对话框）；nil 时不弹窗。
    @State private var pendingDelete: ActivationConfig?

    var body: some View {
        Form {
            Section {
                Toggle("Launch Relay at login", isOn: boolBinding(\.launchAtLogin))
                Toggle("Show icon in Dock", isOn: boolBinding(\.showDockIcon))
            }
            Section("New Shortcuts") {
                LabeledContent("Default behavior") {
                    ActivationConfigPicker(selection: defaultConfigBinding)
                        .labelsHidden()
                        .fixedSize()
                }
                .help("Applied to each newly added app.")
            }
            Section("Activation Behaviors") {
                configTable
                footerBar
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { config in
            Button("Delete & Reassign", role: .destructive) {
                model.deleteActivationConfig(config.id)
                selection.remove(config.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { config in
            Text(deleteWarning(for: config))
        }
    }

    // MARK: - 配置表

    private var configTable: some View {
        Table(model.activationConfigs, selection: $selection) {
            TableColumn("Name") { config in
                TextField("Name", text: nameBinding(config))
                    .labelsHidden()
            }
            TableColumn("Not Running") { config in
                Picker("", selection: notRunningBinding(config)) {
                    ForEach(NotRunningAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            TableColumn("Background") { config in
                // 占位：选项可见但禁用，引擎本期一律按 Focus 执行（PRD D5）。
                Picker("", selection: backgroundBinding(config)) {
                    ForEach(BackgroundAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(true)
            }
            TableColumn("Frontmost") { config in
                Picker("", selection: frontmostBinding(config)) {
                    ForEach(FrontmostAction.allCases) { action in
                        // 占位：最小化项禁用（需 Accessibility，下一任务）——禁用以阻止被选中，
                        // 否则选中后决策层会静默退化为 .none（不符合占位语义）。
                        Text(action.displayName).tag(action)
                            .foregroundStyle(action.isImplemented ? .primary : .secondary)
                            .disabled(!action.isImplemented)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .frame(minHeight: 160)
    }

    // MARK: - ＋ / － 页脚

    private var footerBar: some View {
        HStack(spacing: 0) {
            Button {
                let new = model.addActivationConfig(name: "New Behavior")
                selection = [new.id]
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Add a behavior")

            Button {
                requestDeleteSelected()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(!canDeleteSelection)
            .help("Delete the selected behavior")

            Spacer()
        }
    }

    // MARK: - 删除流程

    /// 选中项可删：恰好选中一条、且总数 > 1（始终保留 ≥1 条）。
    private var canDeleteSelection: Bool {
        guard model.activationConfigs.count > 1, let id = selection.first, selection.count == 1
        else { return false }
        return model.activationConfig(id: id) != nil
    }

    /// 点 － 时：有依赖 → 弹两步确认；无依赖 → 直接删。
    private func requestDeleteSelected() {
        guard let id = selection.first, let config = model.activationConfig(id: id) else { return }
        if model.dependents(ofConfig: id).isEmpty {
            model.deleteActivationConfig(id)
            selection.remove(id)
        } else {
            pendingDelete = config
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    /// 第二步：列出依赖（跨 Profile 的 `Profile › App`），并说明将回退到全局默认。
    private func deleteWarning(for config: ActivationConfig) -> String {
        let lines = dependentLabels(ofConfig: config.id)
        let header = "These shortcuts use this behavior and will fall back to the default behavior:"
        return header + "\n\n" + lines.joined(separator: "\n")
    }

    private func dependentLabels(ofConfig id: UUID) -> [String] {
        model.configuration.profiles.flatMap { profile in
            profile.bindings
                .filter { $0.configID == id }
                .map { "\(profile.name) › \($0.app.displayName)" }
        }
    }

    // MARK: - Bindings

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                var settings = model.settings
                settings[keyPath: keyPath] = $0
                model.settings = settings
            }
        )
    }

    private var defaultConfigBinding: Binding<UUID> {
        Binding(
            get: { model.settings.defaultConfigID },
            set: {
                var settings = model.settings
                settings.defaultConfigID = $0
                model.settings = settings
            }
        )
    }

    private func nameBinding(_ config: ActivationConfig) -> Binding<String> {
        Binding(
            get: { config.name },
            set: { model.renameActivationConfig(config.id, to: $0) }
        )
    }

    private func notRunningBinding(_ config: ActivationConfig) -> Binding<NotRunningAction> {
        Binding(
            get: { config.notRunning },
            set: { var c = config; c.notRunning = $0; model.updateActivationConfig(c) }
        )
    }

    private func backgroundBinding(_ config: ActivationConfig) -> Binding<BackgroundAction> {
        Binding(
            get: { config.background },
            set: { var c = config; c.background = $0; model.updateActivationConfig(c) }
        )
    }

    private func frontmostBinding(_ config: ActivationConfig) -> Binding<FrontmostAction> {
        Binding(
            get: { config.frontmost },
            set: { var c = config; c.frontmost = $0; model.updateActivationConfig(c) }
        )
    }
}
