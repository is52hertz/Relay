//
//  FrontmostTracker.swift
//  Relay
//
//  Return to Previous 的「模型 A」：监听 didActivateApplicationNotification，
//  维护全局 (current, previous)，排除 Relay 自身。等价于 ⌘Tab MRU 的深度 2；
//  纯事件驱动、低频、O(1)、零空闲开销（见 cross-app-activation 研究 / PRD P1-7）。
//

import AppKit

@MainActor
final class FrontmostTracker {
    private(set) var current: NSRunningApplication?
    private(set) var previous: NSRunningApplication?

    /// 上一个非自身的前台 App（供 Return to Previous）。
    var previousApp: NSRunningApplication? { previous }

    private let selfBundleID: String?
    private var observer: NSObjectProtocol?

    init(selfBundleID: String? = Bundle.main.bundleIdentifier) {
        self.selfBundleID = selfBundleID
        self.current = NSWorkspace.shared.frontmostApplication
        start()
    }

    private func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handleActivation(app)
            }
        }
    }

    private func handleActivation(_ app: NSRunningApplication?) {
        guard let app else { return }
        // 排除 Relay 自身：激活自己不应污染 previous。
        if let selfBundleID, app.bundleIdentifier == selfBundleID { return }
        guard app != current else { return }
        previous = current
        current = app
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
