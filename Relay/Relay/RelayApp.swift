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
        // 绑定 isInserted 到 showMenuBarIcon：隐藏即时移除状态项（@Observable 驱动）。
        // 写入经 AppModel.setMenuBarIconVisible（含锁定守卫，落盘 + settingsDidChange）。
        MenuBarExtra(isInserted: menuBarIconVisibleBinding) {
            MenuBarContent()
                .environment(controller.model)
        } label: {
            // 用自定义 label（常驻渲染）读取 openWindow 并响应启动协调器：
            // didFinishLaunching 在 body 首次求值、菜单栏 label 渲染之后翻转标志。
            // 同时传入 model：label 在 body 内读 settings.menuBarIconName，个性化页改图标时实时刷新。
            LaunchTriggerLabel(launch: appDelegate.launch, model: controller.model)
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
                .environment(controller.languageService)
                .environment(controller.backupService)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        // 注意：不要加 .windowStyle(.hiddenTitleBar)——它只会让标题栏透明并隐藏标题，
        // 不会让侧栏延伸到窗口顶部。「全高侧栏 + 悬浮红绿灯」由 SettingsRootView
        // 里强制安装 NSToolbar 实现（详见该文件注释）。
        .commands {
            // 没有了 Settings 场景，自己提供标准的 "Settings…" 菜单项 + ⌘,。
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }
    }

    /// MenuBarExtra(isInserted:) 的双向绑定：读 showMenuBarIcon，写经 AppModel（锁定守卫在此兜底）。
    private var menuBarIconVisibleBinding: Binding<Bool> {
        Binding(
            get: { controller.model.settings.showMenuBarIcon },
            set: { controller.model.setMenuBarIconVisible($0) }
        )
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

/// 菜单栏的常驻 label：渲染用户选择的图标，并监听 LaunchCoordinator 按启动来源程序化打开主窗口。
private struct LaunchTriggerLabel: View {
    @Environment(\.openWindow) private var openWindow
    let launch: LaunchCoordinator
    /// SoT：在 body 内读取 settings.menuBarIconName，@Observable 变更会重渲染该 label → 状态项实时换图标。
    let model: AppModel

    var body: some View {
        Image(systemName: resolvedIconName)
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

    /// 防御性兜底：存储名若无法解析为有效 SF Symbol，回退默认，状态项绝不空白。
    private var resolvedIconName: String {
        let name = model.settings.menuBarIconName
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
            ? name
            : AppSettings.defaultMenuBarIconName
    }

    private func showMainWindow() {
        openWindow(id: RelayWindow.main)
        NSApp.activate(ignoringOtherApps: true)
        launch.shouldShowMainWindow = false
    }
}
