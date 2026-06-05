//
//  RelayApp.swift
//  Relay
//

import SwiftUI

@main
struct RelayApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Relay", systemImage: "command") {
            MenuBarContent()
                .environment(controller.model)
        }

        // 管理界面用真正的 Window（不是 Settings 场景——后者不支持自定义 toolbar、
        // 且切换激活策略时窗口会异常）。agent 应用默认不在启动时弹窗。
        Window("Relay", id: RelayWindow.main) {
            SettingsContainer()
                .environment(controller.model)
                .environment(controller.resolver)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }
}

enum RelayWindow {
    static let main = "main"
}
