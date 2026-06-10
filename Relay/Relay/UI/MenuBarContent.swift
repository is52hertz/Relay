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

        // ⌘, 只有在 Relay 某个窗口为 key 时才会触发；从菜单栏 agent 直接开设置需要本项。
        // 此处不绑 ⌘,（⌘, 归 CommandGroup）。
        Button("Settings…") {
            openWindow(id: RelayWindow.settings)
            NSApplication.shared.activate()
        }

        Divider()

        Button("Quit Relay") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
