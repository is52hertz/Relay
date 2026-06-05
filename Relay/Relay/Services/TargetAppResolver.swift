//
//  TargetAppResolver.swift
//  Relay
//
//  解析 TargetApp → 当前安装 URL / 运行实例 / 图标。bundleId 优先，回退 lastKnownPath。
//  图标按 path 缓存（运行时取，不入库，见 cross-app-activation 研究）。
//

import AppKit

@MainActor
final class TargetAppResolver {
    private let workspace = NSWorkspace.shared
    private var iconCache: [String: NSImage] = [:]

    /// 当前安装 URL：先按 bundleId 解析，回退到仍存在的 lastKnownPath。
    func resolvedURL(for app: TargetApp) -> URL? {
        if let url = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            return url
        }
        if let path = app.lastKnownPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func isInstalled(_ app: TargetApp) -> Bool {
        resolvedURL(for: app) != nil
    }

    func runningInstances(of app: TargetApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
    }

    /// App 图标；无法解析时返回 nil。
    func icon(for app: TargetApp) -> NSImage? {
        guard let url = resolvedURL(for: app) else { return nil }
        let path = url.path
        if let cached = iconCache[path] { return cached }
        let icon = workspace.icon(forFile: path)
        iconCache[path] = icon
        return icon
    }
}
