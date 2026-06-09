//
//  SettingsRootView.swift
//  Relay
//
//  设置主容器：System Settings 风格的双列侧栏（始终双列、无折叠按钮）。
//  目前仅 General 一个面板；后续 Language / Shortcuts 等面板直接扩 Pane 即可。
//

import SwiftUI

struct SettingsRootView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        var id: Self { self }
        var icon: String { "gearshape" }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        // .constant(.doubleColumn)：侧栏始终可见，不允许折叠；
        // .toolbar(removing: .sidebarToggle)：去掉系统的侧栏折叠按钮。
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsView()
                    .navigationTitle("General")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
