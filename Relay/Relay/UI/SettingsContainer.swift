//
//  SettingsContainer.swift
//  Relay
//
//  Settings 场景容器：原生分页（Profiles 管理 + General 通用）。
//

import SwiftUI

struct SettingsContainer: View {
    var body: some View {
        TabView {
            SettingsRootView()
                .tabItem { Label("Profiles", systemImage: "list.bullet") }
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
    }
}
