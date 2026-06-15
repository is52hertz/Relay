//
//  BackupServiceTests.swift
//  RelayTests
//
//  BackupService：信封编解码往返、schema 兼容性闸门、滚动快照轮换保留最新 N。
//  全程 AppKit-free，用临时目录注入快照目录，绝不触碰真实容器。
//

import Testing
import Foundation
@testable import Relay

@MainActor
struct BackupServiceTests {

    /// 每个用例独立的临时快照目录，结束清理。
    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-backup-test-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func envelopeRoundTripPreservesConfiguration() throws {
        let service = BackupService(backupsDirectory: makeTempDir())
        let original = AppConfiguration.makeDefault()

        let data = try service.encodeEnvelope(for: original)
        let decoded = try service.decodeConfiguration(from: data)

        #expect(decoded == original)
    }

    @Test func decodeRejectsNewerSchema() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = BackupService(backupsDirectory: dir)

        // 构造一个 schemaVersion 比当前支持还高的信封。
        var config = AppConfiguration.makeDefault()
        config.schemaVersion = AppConfiguration.currentSchemaVersion + 1
        let data = try service.encodeEnvelope(for: config)

        #expect(throws: BackupError.self) {
            _ = try service.decodeConfiguration(from: data)
        }
    }

    @Test func decodeAcceptsEqualAndOlderSchema() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = BackupService(backupsDirectory: dir)

        // 等于当前版本。
        let equal = AppConfiguration.makeDefault()
        let equalData = try service.encodeEnvelope(for: equal)
        #expect(try service.decodeConfiguration(from: equalData) == equal)

        // 低于当前版本（older）。
        var older = AppConfiguration.makeDefault()
        older.schemaVersion = max(1, AppConfiguration.currentSchemaVersion - 1)
        let olderData = try service.encodeEnvelope(for: older)
        let decodedOlder = try service.decodeConfiguration(from: olderData)
        #expect(decodedOlder.profiles == older.profiles)
    }

    @Test func decodeThrowsUnreadableForGarbage() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = BackupService(backupsDirectory: dir)
        let garbage = Data("not a backup".utf8)

        #expect(throws: BackupError.self) {
            _ = try service.decodeConfiguration(from: garbage)
        }
    }

    @Test func writeBackupRoundTripsThroughReadBackup() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = BackupService(backupsDirectory: dir)

        let original = AppConfiguration.makeDefault()
        let fileURL = dir.appendingPathComponent("export.relaybackup")
        try service.writeBackup(original, to: fileURL)

        let restored = try service.readBackup(from: fileURL)
        #expect(restored == original)
    }

    @Test func snapshotRotationKeepsNewestN() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keepN = 3
        let service = BackupService(backupsDirectory: dir, maxSnapshots: keepN)

        // 预铺 keepN + 2 份「旧」快照（递增修改时间），其后由 snapshot() 触发轮换。
        // 轮换按修改时间从旧到新裁剪，故须给每份一个确定且不同的时间戳（文件名秒级精度不足以区分同秒写入）。
        let stale = keepN + 2
        for i in 0..<stale {
            let url = dir.appendingPathComponent("snapshot-old-\(i).relaybackup")
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1000 + Double(i))],
                ofItemAtPath: url.path
            )
        }
        #expect(service.listSnapshots().count == stale)

        // 写一份新快照（修改时间 = 当下，必为最新）→ 触发轮换，应裁剪到 keepN。
        try service.snapshot(AppConfiguration.makeDefault())

        let remaining = service.listSnapshots()
        #expect(remaining.count == keepN)
        // 保留的应为按修改时间最新的 N 份。
        let allUrlsByDate = (try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ))
        // 最旧的两份「snapshot-old-0 / -1」应已被删除。
        let names = Set(remaining.map { $0.url.lastPathComponent })
        #expect(!names.contains("snapshot-old-0.relaybackup"))
        #expect(!names.contains("snapshot-old-1.relaybackup"))
        _ = allUrlsByDate
    }

    @Test func listSnapshotsSortsNewestFirst() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let service = BackupService(backupsDirectory: dir, maxSnapshots: 100)

        // 直接铺三个带不同修改时间的 .relaybackup 文件。
        let dates: [TimeInterval] = [3000, 1000, 2000]
        for (i, t) in dates.enumerated() {
            let url = dir.appendingPathComponent("snapshot-\(i).relaybackup")
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: t)], ofItemAtPath: url.path
            )
        }

        let list = service.listSnapshots()
        #expect(list.count == 3)
        let times = list.map { $0.createdAt.timeIntervalSince1970 }
        #expect(times == [3000, 2000, 1000]) // 新→旧
    }
}
