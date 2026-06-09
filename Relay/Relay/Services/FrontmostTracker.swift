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

    /// 抑制激活记录：用于「显示不聚焦」的合成 A→C→A 跳变，避免把 previous 污染成被显示的目标 App
    /// （见 PR#7 Codex 反馈）。抑制期内 didActivate 通知一律忽略。
    var isSuppressed = false

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
        guard !isSuppressed else { return }
        guard let app else { return }
        // 排除 Relay 自身：激活自己不应污染 previous。
        if let selfBundleID, app.bundleIdentifier == selfBundleID { return }
        guard app != current else { return }
        previous = current
        current = app
    }

    /// 当前 (current, previous) 快照——供调用方在合成激活序列后恢复。
    func activationSnapshot() -> (current: NSRunningApplication?, previous: NSRunningApplication?) {
        (current, previous)
    }

    /// 恢复到快照的 (current, previous)（不依赖通知时序，作为抑制之外的兜底）。
    func restore(_ snapshot: (current: NSRunningApplication?, previous: NSRunningApplication?)) {
        current = snapshot.current
        previous = snapshot.previous
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
