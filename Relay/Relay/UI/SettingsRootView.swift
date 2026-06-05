//
//  SettingsRootView.swift
//  Relay
//
//  设置/管理主界面：NavigationSplitView，侧栏 Profile 列表，详情为该 Profile 的绑定。
//  PR1 为骨架——绑定行编辑、快捷键录入、行为选择在 PR3/PR4 加入。
//

import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedProfileID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProfileID) {
                Section("Profiles") {
                    ForEach(model.configuration.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                ToolbarItem {
                    Button {
                        let profile = model.addProfile(name: "New Profile")
                        selectedProfileID = profile.id
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selectedProfileID ?? model.configuration.activeProfileID,
               let profile = model.configuration.profiles.first(where: { $0.id == id }) {
                ProfileDetailView(profile: profile)
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "square.stack.3d.up",
                    description: Text("Select a profile, or create one.")
                )
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

private struct ProfileDetailView: View {
    let profile: Profile

    var body: some View {
        Group {
            if profile.bindings.isEmpty {
                ContentUnavailableView(
                    "No Shortcuts",
                    systemImage: "keyboard",
                    description: Text("App + hotkey binding UI arrives in a later step.")
                )
            } else {
                List(profile.bindings) { binding in
                    Text(binding.app.displayName)
                }
            }
        }
        .navigationTitle(profile.name)
    }
}
