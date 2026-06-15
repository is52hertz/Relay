//
//  BackupService.swift
//  Relay
//
//  备份/恢复/快照的纯 Foundation 服务：编解码 BackupEnvelope、原子写备份、读备份为 AppConfiguration、
//  以及在破坏性操作前写「滚动快照」并轮换保留最新 N 份。保持 AppKit-free 以便单测；
//  NSSavePanel/NSOpenPanel 留在 DataSettingsView（UI 层）。由 AppController 注入（无单例）。
//

import Foundation
import Observation

/// 备份相关的可定位错误（UI 据此给出明确文案）。
nonisolated enum BackupError: Error, LocalizedError {
    /// 信封的 schemaVersion 比 App 当前支持的还新——由更高版本 Relay 导出，拒绝导入。
    case newerSchema(found: Int, supported: Int)
    /// 文件无法解析为有效备份信封（损坏 / 非备份文件）。
    case unreadable
    /// 安全快照写入失败（破坏性操作前的兜底未能建立）。
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .newerSchema:
            return String(localized: "This backup was created by a newer version of Relay and can’t be imported. Update Relay and try again.")
        case .unreadable:
            return String(localized: "This file isn’t a valid Relay backup, or it’s damaged.")
        case .snapshotFailed:
            return String(localized: "Relay couldn’t create a safety snapshot before this change.")
        }
    }
}

// 注：标为 @Observable 仅为满足 SwiftUI `@Environment(BackupService.self)` 注入约束
// （与 LanguageService / WindowMinimizer 一致）。本服务无可观察视图状态——所有存储依赖都是
// 不可变 let 且与渲染无关，标注 @ObservationIgnored 避免任何无谓的视图刷新（见 concurrency spec）。
@MainActor
@Observable
final class BackupService {
    /// 快照根目录（容器/Backups/）。可注入以便测试不触碰真实容器。
    @ObservationIgnored private let backupsDirectory: URL
    /// 滚动快照保留份数；超出按时间戳从旧到新删除。
    @ObservationIgnored private let maxSnapshots: Int

    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder: JSONDecoder

    /// 快照文件名里的可排序时间戳（yyyyMMdd-HHmmss），便于字典序即时间序排序与轮换。
    @ObservationIgnored private let stampFormatter: DateFormatter

    /// - Parameters:
    ///   - backupsDirectory: 快照目录；默认 = PersistenceStore 容器下的 Backups/（与 config.json 同根）。
    ///   - maxSnapshots: 保留份数，默认 10。
    init(backupsDirectory: URL? = nil, maxSnapshots: Int = 10) {
        self.backupsDirectory = backupsDirectory
            ?? PersistenceStore.containerDirectory().appendingPathComponent("Backups", isDirectory: true)
        self.maxSnapshots = maxSnapshots

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        self.stampFormatter = formatter
    }

    /// 暴露给 UI 的快照目录（用于 NSWorkspace 在 Finder 中显示等）。
    var snapshotsURL: URL { backupsDirectory }

    // MARK: - 信封编解码

    /// 用当前 config + 元数据构造信封。exportedAt 取当下，appVersion 取 bundle 短版本号。
    func makeEnvelope(from configuration: AppConfiguration) -> BackupEnvelope {
        BackupEnvelope(
            formatVersion: BackupEnvelope.currentFormatVersion,
            appVersion: Self.appVersion,
            exportedAt: Date(),
            schemaVersion: configuration.schemaVersion,
            configuration: configuration
        )
    }

    /// 编码信封为「漂亮」JSON Data。
    func encodeEnvelope(for configuration: AppConfiguration) throws -> Data {
        try encoder.encode(makeEnvelope(from: configuration))
    }

    /// 解码信封并做 schema 兼容性校验：
    /// - schemaVersion 大于 App 当前支持 → 抛 newerSchema（更高版本 Relay 导出）。
    /// - 等于/低于 → 返回 configuration（缺键由 AppSettings.decodeIfPresent 容错）。
    /// - 无法解析 → 抛 unreadable。
    func decodeConfiguration(from data: Data) throws -> AppConfiguration {
        let envelope: BackupEnvelope
        do {
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
        let supported = AppConfiguration.currentSchemaVersion
        guard envelope.schemaVersion <= supported else {
            throw BackupError.newerSchema(found: envelope.schemaVersion, supported: supported)
        }
        return envelope.configuration
    }

    // MARK: - 备份文件读写（用户选定位置）

    /// 原子写入信封到用户选定的 url（导出/备份）。
    func writeBackup(_ configuration: AppConfiguration, to url: URL) throws {
        let data = try encodeEnvelope(for: configuration)
        try data.write(to: url, options: [.atomic])
    }

    /// 读取并解码为 AppConfiguration（导入/恢复）。解析失败抛 unreadable。
    func readBackup(from url: URL) throws -> AppConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.unreadable
        }
        return try decodeConfiguration(from: data)
    }

    // MARK: - 滚动快照

    /// 在破坏性操作（reset/import/restore）前写一份当前 config 的带时间戳信封到 Backups/，再轮换保留最新 N 份。
    /// 写入失败抛 snapshotFailed，交由调用方决定是否继续（绝不静默无网兜底）。
    func snapshot(_ configuration: AppConfiguration) throws {
        do {
            try FileManager.default.createDirectory(
                at: backupsDirectory, withIntermediateDirectories: true
            )
            let name = "snapshot-\(stampFormatter.string(from: Date())).relaybackup"
            let url = backupsDirectory.appendingPathComponent(name, isDirectory: false)
            let data = try encodeEnvelope(for: configuration)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw BackupError.snapshotFailed
        }
        rotateSnapshots()
    }

    /// 枚举 Backups/，返回 [SnapshotInfo]（带创建时间与字节数），按时间从新到旧排序。
    func listSnapshots() -> [SnapshotInfo] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "relaybackup" }
            .map { url -> SnapshotInfo in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return SnapshotInfo(
                    url: url,
                    createdAt: values?.contentModificationDate ?? .distantPast,
                    sizeBytes: values?.fileSize ?? 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 轮换：超出 maxSnapshots 时按时间从旧到新删除多余份（保留最新 N）。
    private func rotateSnapshots() {
        let snapshots = listSnapshots() // 新→旧
        guard snapshots.count > maxSnapshots else { return }
        let stale = snapshots[maxSnapshots...]
        for info in stale {
            try? FileManager.default.removeItem(at: info.url)
        }
    }

    // MARK: - Helpers

    /// App 短版本号（CFBundleShortVersionString），缺失时回退占位。
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
