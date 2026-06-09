//
//  BindingRow.swift
//  Relay
//
//  绑定行：App 图标 + 名称(+失效标记) + 冲突标记 + 快捷键录入器 + 焦点行为选择。
//  双向编辑通过自建 Binding 回写 AppModel（保持 model 封装）。录入器写我方 Hotkey，
//  实际全局注册由 AppModel.hotkeysDidChange → HotkeyRegistrationService 完成。
//

import SwiftUI

struct BindingRow: View {
    let binding: HotkeyBinding
    let isConflicting: Bool
    let profileID: UUID

    @Environment(AppModel.self) private var model
    @Environment(TargetAppResolver.self) private var resolver
    @State private var showConflictInfo = false

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.app.displayName)
                if !resolver.isInstalled(binding.app) {
                    Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 12)

            if isConflicting {
                Button {
                    showConflictInfo.toggle()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .onHover { hovering in if hovering { showConflictInfo = true } }
                .popover(isPresented: $showConflictInfo) { conflictInfoCard }
                .accessibilityLabel("Duplicate shortcut")
            }

            ShortcutRecorder(hotkey: hotkeyBinding)
                .frame(width: 150)

            ActivationConfigPicker(selection: configBinding)
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(binding.app.displayName)
        .contextMenu {
            Button("Remove", role: .destructive) {
                model.removeBindings([binding.id], from: profileID)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = resolver.icon(for: binding.app) {
            Image(nsImage: image).resizable().frame(width: 28, height: 28)
        } else {
            Image(systemName: "app.dashed")
                .resizable().frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
        }
    }

    private var conflictInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Duplicate shortcut", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("A key combination can only be used by one app per profile. The binding listed first is registered automatically; later duplicates stay inactive.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var configBinding: Binding<UUID> {
        Binding(
            get: { binding.configID },
            set: {
                var updated = binding
                updated.configID = $0
                model.updateBinding(updated, in: profileID)
            }
        )
    }

    private var hotkeyBinding: Binding<Hotkey?> {
        Binding(
            get: { binding.hotkey },
            set: {
                var updated = binding
                updated.hotkey = $0
                model.updateBinding(updated, in: profileID)
            }
        )
    }
}
