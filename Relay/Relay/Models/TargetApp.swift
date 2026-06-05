//
//  TargetApp.swift
//  Relay
//
//  目标应用引用。bundleIdentifier 为主键用于解析，lastKnownPath 仅作回退/展示。
//  图标与运行态不入库——运行时由 NSWorkspace 重新取（见 cross-app-activation 研究）。
//

import Foundation

nonisolated struct TargetApp: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var lastKnownPath: String?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        lastKnownPath: String? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.lastKnownPath = lastKnownPath
    }
}
