//
//  GeneralSettingsView.swift
//  Relay
//
//  通用设置：登录启动、Dock 图标、新建绑定的默认焦点行为。
//  写回 AppModel.settings（其 setter 触发 settingsDidChange → 应用登录项/Dock 策略）。
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Launch Relay at login", isOn: boolBinding(\.launchAtLogin))
                Toggle("Show icon in Dock", isOn: boolBinding(\.showDockIcon))
            }
            Section("New Shortcuts") {
                Picker("Default behavior", selection: behaviorBinding) {
                    ForEach(FocusBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .help("Applied to each newly added app.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

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

    private var behaviorBinding: Binding<FocusBehavior> {
        Binding(
            get: { model.settings.defaultBehavior },
            set: {
                var settings = model.settings
                settings.defaultBehavior = $0
                model.settings = settings
            }
        )
    }
}
