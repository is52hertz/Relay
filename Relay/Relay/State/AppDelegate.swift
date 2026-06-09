//
//  AppDelegate.swift
//  Relay
//
//  启动来源感知：登录项拉起 → 保持隐藏（仅菜单栏）；显式启动 / 用户再点图标 → 开主窗口。
//  经 LaunchCoordinator 桥接到 SwiftUI 的 openWindow（delegate 持有协调器，非单例）。
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 由 delegate 持有并注入，非单例。
    let launch = LaunchCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSApplicationDelegate 的遵循是 nonisolated；这些回调实际在主线程派发，
        // 故用 assumeIsolated 访问 MainActor 隔离的 launch（与 FrontmostTracker 同模式）。
        let asLogInItem = launchedAsLogInItem
        MainActor.assumeIsolated {
            // 登录项拉起 → 保持隐藏；显式启动 → 开主窗口。
            if !asLogInItem { launch.shouldShowMainWindow = true }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            // agent 已在跑时用户再点图标 → 开窗。
            launch.shouldShowMainWindow = true
        }
        return true
    }

    /// 是否由 SMAppService 登录项拉起：读启动 Apple Event（applicationDidFinishLaunching 时机可靠）。
    /// kAEOpenApplication / keyAEPropData / keyAELaunchedAsLogInItem 均为公开文档化的 Carbon/AppKit 常量。
    private var launchedAsLogInItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
