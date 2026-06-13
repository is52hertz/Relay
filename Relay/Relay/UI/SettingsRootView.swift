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
        case personalization = "Personalization"
        var id: Self { self }

        /// 侧栏/标题用：必须是 LocalizedStringKey 才会本地化（rawValue 是 String，传给 Label 会被当 verbatim）。
        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .personalization: "Personalization"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .personalization: "paintbrush"
            }
        }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        // .constant(.doubleColumn)：侧栏始终可见，不允许折叠；
        // .toolbar(removing: .sidebarToggle)：去掉系统的侧栏折叠按钮。
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralSettingsView()
                        .navigationTitle(Pane.general.title)
                case .personalization:
                    PersonalizationSettingsView()
                        .navigationTitle(Pane.personalization.title)
                }
            }
            // 零尺寸的占位 toolbar item：强制 SwiftUI 给窗口安装 NSToolbar。
            // macOS 26 上若没有任何 toolbar item（标题不算），窗口不会创建 NSToolbar，
            // 退化为 32pt 不透明标题栏，侧栏玻璃面板从标题栏下方才开始；装上 NSToolbar
            // 后侧栏材质垫满整窗高度、红绿灯悬浮其上，标题 "General" 落在 detail 列
            // 工具栏前部——即 System Settings 风格。该 item 宽度为 0，不会渲染玻璃容器。
            .toolbar {
                ToolbarItem { Color.clear.frame(width: 0, height: 0) }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
