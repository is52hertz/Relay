//
//  MenuBarContent.swift
//  Relay
//
//  菜单栏内容：Profile 切换（active 带勾选）+ 打开主窗口 + 退出。
//

import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.configuration.profiles.isEmpty {
            Text("No Profiles")
        } else {
            ForEach(model.configuration.profiles) { profile in
                Button {
                    model.setActiveProfile(profile.id)
                } label: {
                    if profile.id == model.configuration.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        }

        Divider()

        Button("Open Relay…") {
            openWindow(id: RelayWindow.main)
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Relay") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
