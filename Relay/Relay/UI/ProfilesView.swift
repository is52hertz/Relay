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
    @State private var renamingProfileID: UUID?
    @State private var renameText: String = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProfileID) {
                Section("Profiles") {
                    ForEach(model.configuration.profiles) { profile in
                        ProfileRow(
                            name: profile.name,
                            isActive: profile.id == model.configuration.activeProfileID
                        )
                        .tag(profile.id)
                        .contextMenu {
                            Button("Set as Active") { model.setActiveProfile(profile.id) }
                                .disabled(profile.id == model.configuration.activeProfileID)
                            Button("Rename…") { startRename(profile) }
                            Divider()
                            Button("Delete", role: .destructive) { delete(profile) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
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
        .alert("Rename Profile", isPresented: renameAlertPresented) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renamingProfileID = nil }
        }
    }

    private var selectedProfile: Profile? {
        let id = selectedProfileID ?? model.configuration.activeProfileID
        return model.configuration.profiles.first { $0.id == id }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingProfileID != nil },
            set: { if !$0 { renamingProfileID = nil } }
        )
    }

    private func addProfile() {
        let profile = model.addProfile(name: "New Profile")
        selectedProfileID = profile.id
    }

    private func delete(_ profile: Profile) {
        if selectedProfileID == profile.id { selectedProfileID = nil }
        model.deleteProfile(profile.id)
    }

    private func startRename(_ profile: Profile) {
        renameText = profile.name
        renamingProfileID = profile.id
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = renamingProfileID, !trimmed.isEmpty {
            model.renameProfile(id, to: trimmed)
        }
        renamingProfileID = nil
    }
}

private struct ProfileRow: View {
    let name: String
    let isActive: Bool

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if isActive {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Active profile")
            }
        }
    }
}
