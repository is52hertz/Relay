//
//  RelayApp.swift
//  Relay
//

import SwiftUI
import AppKit

@main
struct RelayApp: App {
    @State private var controller = AppController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(controller.model)
        } label: {
            // 用自定义 label（常驻渲染）读取 openWindow 并响应启动协调器：
            // didFinishLaunching 在 body 首次求值、菜单栏 label 渲染之后翻转标志。
            LaunchTriggerLabel(launch: appDelegate.launch)
        }

        // 主窗口 = Profiles 管理（NavigationSplitView + Add Profile 工具栏）。
        // 必须用真正的 Window（不是 Settings 场景——后者不支持自定义 toolbar、
        // 且切换激活策略时窗口会异常）。agent 应用默认不在启动时弹窗。
        Window("Relay", id: RelayWindow.main) {
            ProfilesView()
                .environment(controller.model)
                .environment(controller.resolver)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)

        // 设置改用专门的可缩放 Window（System Settings 风格的侧栏）。
        // SwiftUI 的 Settings 场景对 NavigationSplitView 支持不稳（detail 列顶部
        // 幻影内距、侧栏抖动），且不易可靠缩放——故移到独立 Window，并经
        // CommandGroup(replacing: .appSettings) 重新接回 ⌘, 与应用菜单 "Settings…"。
        Window("Settings", id: RelayWindow.settings) {
            SettingsRootView()
                .environment(controller.model)
                .environment(controller.minimizer)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .commands {
            // 没有了 Settings 场景，自己提供标准的 "Settings…" 菜单项 + ⌘,。
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }
    }
}

enum RelayWindow {
    static let main = "main"
    static let settings = "settings"
}

/// 应用菜单的 "Settings…" 项：openWindow 必须在 View 环境取，故包成小视图。
private struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: RelayWindow.settings)
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// 菜单栏的常驻 label：监听 LaunchCoordinator，按启动来源程序化打开主窗口。
private struct LaunchTriggerLabel: View {
    @Environment(\.openWindow) private var openWindow
    let launch: LaunchCoordinator

    var body: some View {
        Image(systemName: "command")
            // onChange 覆盖「label 已渲染后标志翻转」的常规时序；
            // onAppear 覆盖「didFinishLaunching 在 label 首次渲染前就翻转标志」的竞态
            // （MenuBarExtra label 渲染时机较晚，onChange 只在变化时触发、会漏掉已为 true 的初值）。
            .onChange(of: launch.shouldShowMainWindow) { _, show in
                if show { showMainWindow() }
            }
            .onAppear {
                if launch.shouldShowMainWindow { showMainWindow() }
            }
    }

    private func showMainWindow() {
        openWindow(id: RelayWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        launch.shouldShowMainWindow = false
    }
}
