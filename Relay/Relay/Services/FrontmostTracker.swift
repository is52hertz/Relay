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

    /// 某个 App 失去前台时回调（携带其 bundleIdentifier）。供 cycleWindowsThenHide 在「切走」时
    /// 清空该 App 的窗口轮换游标（PRD R3：切走再切回 → 从头开始）。由 AppController 接线、注入；
    /// FrontmostTracker 不持有轮换状态，只广播「谁失去了前台」这一事件，保持职责单一、无单例。
    @MainActor var onAppResignedFrontmost: ((String) -> Void)?

    /// 抑制激活记录：用于「显示不聚焦」的合成 A→C→A 跳变，避免把 previous 污染成被显示的目标 App。
    /// 引用计数 + 快照：支持重叠的多次跳变嵌套——抑制持续到所有跳变结束，归零时恢复「任一跳变之前」
    /// 的真实 (current, previous)，不依赖 didActivate 通知时序。（见 PR#7 Codex 两轮反馈）
    private var suppressionDepth = 0
    private var suppressionSnapshot: (current: NSRunningApplication?, previous: NSRunningApplication?)?

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
        guard suppressionDepth == 0 else { return }
        guard let app else { return }
        // 排除 Relay 自身：激活自己不应污染 previous。
        if let selfBundleID, app.bundleIdentifier == selfBundleID { return }
        guard app != current else { return }
        // 通知「即将失去前台」的旧 current（用于清空其窗口轮换游标）；新激活的 App 自身不触发。
        if let resigning = current?.bundleIdentifier, resigning != app.bundleIdentifier {
            onAppResignedFrontmost?(resigning)
        }
        previous = current
        current = app
    }

    /// 进入一次合成激活序列：首次进入（计数 0→1）时快照 (current, previous)，并增加抑制计数。
    /// 重叠的多次跳变只在最外层快照，保证恢复到「任一跳变之前」的真实状态。
    func beginSuppression() {
        if suppressionDepth == 0 {
            suppressionSnapshot = (current, previous)
        }
        suppressionDepth += 1
    }

    /// 退出一次合成激活序列：抑制计数减一；归零时恢复最外层快照、丢弃期间的合成激活。
    func endSuppression() {
        guard suppressionDepth > 0 else { return }
        suppressionDepth -= 1
        if suppressionDepth == 0, let snapshot = suppressionSnapshot {
            current = snapshot.current
            previous = snapshot.previous
            suppressionSnapshot = nil
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
