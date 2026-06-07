//
//  BindingsDetailView.swift
//  Relay
//
//  某个 Profile 的绑定编辑：增删 App、排序、行内录入与行为选择、空状态、active 标识。
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BindingsDetailView: View {
    let profile: Profile

    @Environment(AppModel.self) private var model
    @Environment(TargetAppResolver.self) private var resolver

    private var conflicts: Set<UUID> { HotkeyConflicts.duplicateBindingIDs(in: profile) }
    private var isActive: Bool { model.configuration.activeProfileID == profile.id }

    var body: some View {
        Group {
            if profile.bindings.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "square.grid.2x2")
                } description: {
                    Text("Add an app, then record a global shortcut for it.")
                } actions: {
                    Button("Add App…", action: addApp)
                }
            } else {
                List {
                    ForEach(profile.bindings) { binding in
                        BindingRow(
                            binding: binding,
                            isConflicting: conflicts.contains(binding.id),
                            profileID: profile.id
                        )
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { profile.bindings[$0].id })
                        model.removeBindings(ids, from: profile.id)
                    }
                    .onMove { source, destination in
                        var reordered = profile.bindings
                        reordered.move(fromOffsets: source, toOffset: destination)
                        model.setBindings(reordered, for: profile.id)
                    }
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationSubtitle(isActive ? "Active" : "Inactive")
        .toolbar {
            ToolbarItem {
                Button(action: addApp) {
                    Label("Add App", systemImage: "plus")
                }
                .help("Add an application to this profile")
            }
            ToolbarItem {
                Button {
                    model.setActiveProfile(profile.id)
                } label: {
                    Label("Set as Active", systemImage: isActive ? "bolt.fill" : "bolt")
                }
                .disabled(isActive)
                .help("Make this the active profile")
            }
        }
    }

    private func addApp() {
        guard let app = pickApplication() else { return }
        let binding = HotkeyBinding(app: app, behavior: model.settings.defaultBehavior)
        model.addBinding(binding, to: profile.id)
    }

    private func pickApplication() -> TargetApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose an application to add to this profile."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return resolver.makeTargetApp(from: url)
    }
}
