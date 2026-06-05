//
//  MenuBarContent.swift
//  Relay
//
//  菜单栏内容：Profile 切换（原生 inline Picker，自带勾选）+ 打开设置 + 退出。
//

import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        if model.configuration.profiles.isEmpty {
            Text("No Profiles")
        } else {
            Picker("Profile", selection: $model.activeProfileSelection) {
                ForEach(model.configuration.profiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.inline)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Relay") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
