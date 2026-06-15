//
//  BackupEnvelope.swift
//  Relay
//
//  备份文件的自描述信封：把 AppConfiguration 连同元数据（信封格式版本、App 版本、导出时间、
//  schema 版本）一起序列化。纯数据值类型：nonisolated Codable，不引入 AppKit/SwiftUI。
//  schemaVersion 在导出时镜像 config 的 schema，是导入兼容性闸门（见 BackupService）。
//

import Foundation

nonisolated struct BackupEnvelope: Codable, Hashable, Sendable {
    /// 信封自身的格式版本（与 config 的 schemaVersion 分开演进）。当前从 1 起。
    var formatVersion: Int
    /// 导出时的 App 版本（CFBundleShortVersionString），仅作展示/诊断。
    var appVersion: String
    var exportedAt: Date
    /// 导出时 config 的 schema 版本；导入时与 App 当前支持版本比较，过新则拒绝。
    var schemaVersion: Int
    var configuration: AppConfiguration

    /// 当前信封格式版本。
    static let currentFormatVersion = 1
}

/// 一个滚动快照文件的轻量描述（供 Data 面板列表展示/恢复/在 Finder 显示）。
/// nonisolated 值类型，不引入 AppKit/SwiftUI。
nonisolated struct SnapshotInfo: Hashable, Sendable, Identifiable {
    var url: URL
    var createdAt: Date
    var sizeBytes: Int

    var id: URL { url }
}
