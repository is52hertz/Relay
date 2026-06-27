//
//  BackupService.swift
//  Relay
//
//  备份/恢复/快照的纯 Foundation 服务：编解码 BackupEnvelope、原子写备份、读备份为 AppConfiguration、
//  以及在破坏性操作前写「滚动快照」并轮换保留最新 N 份。保持 AppKit-free 以便单测；
//  NSSavePanel/NSOpenPanel 留在 DataSettingsView（UI 层）。由 AppController 注入（无单例）。
//

import Dispatch
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

// 注：标为 @Observable 同时满足两点：① SwiftUI `@Environment(BackupService.self)` 注入约束
// （与 LanguageService / WindowMinimizer 一致）；② `snapshots` 是真正的可观察视图状态——目录监听器
// 或 in-app 操作刷新它时，SwiftUI 自动重渲染。其余不可变 let 依赖与渲染无关，标注 @ObservationIgnored
// 避免无谓的视图刷新（见 concurrency spec）。
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

    /// 当前快照列表（新→旧）。**可观察**：UI 直接读它，目录监听器/in-app 操作刷新后 SwiftUI 自动重渲染。
    /// 故意不标 @ObservationIgnored——它就是本服务唯一的视图状态。
    private(set) var snapshots: [SnapshotInfo] = []

    /// Backups/ 目录的 vnode 文件系统监听源（监听外部增删改名 → 刷新 snapshots）。
    @ObservationIgnored private var directorySource: DispatchSourceFileSystemObject?

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

        // 故意**不**在 init 武装监听器：监听器只在 Data 面板可见时运行（startWatching/stopWatching
        // 由视图的 onAppear/onDisappear 驱动），避免 Settings 窗口未打开时也整生命周期空转一个 vnode 源。
        // 这里只刷新一次列表，使无视图的使用方（单测、AppController 注入）拿到的 snapshots 即时有效。
        refreshSnapshots()
    }

    deinit {
        // 安全网：正常路径由 .onDisappear → stopWatching() 取消；万一视图从未消失，
        // 这里兜底取消源（DispatchSource 在 cancel handler 里关闭 fd）。
        directorySource?.cancel()
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
        refreshSnapshots()
    }

    /// 删除一份指定快照文件（per-row 删除）。文件已不存在（外部删除竞态）也按成功处理——
    /// 目标即「该文件不在了」。删完刷新一次让 UI 立即、确定地更新（监听器也会触发，二者不冲突）。
    func deleteSnapshot(_ info: SnapshotInfo) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: info.url.path) {
            try fm.removeItem(at: info.url)
        }
        refreshSnapshots()
    }

    /// 重新扫描 Backups/ 刷新可观察的 `snapshots`（init、每次 snapshot/rotate/delete、以及监听器事件都调它）。
    func refreshSnapshots() {
        snapshots = listSnapshots()
    }

    /// 枚举 Backups/，返回 [SnapshotInfo]（带创建时间与字节数），按时间从新到旧排序。
    /// 纯函数式只读扫描，不改可观察状态——`refreshSnapshots()` 才写回 `snapshots`。
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

    // MARK: - 目录监听（外部增删改名 → 实时刷新列表）

    /// 开始监听 Backups/ 目录——由 Data 面板的 `.onAppear` 调用。
    ///
    /// - 先确保 Backups/ 存在（监听器需要一个已存在目录的 fd 才能 open(O_EVTONLY)），
    ///   再 `refreshSnapshots()`（打开面板即看到一份新鲜列表），最后武装一个全新的 vnode 源。
    /// - **幂等**：若已在监听，先 `cancel()` 旧源（其 cancel handler 关闭 fd）再武装新的，
    ///   保证任何时刻最多只有一个已武装的源、不泄漏 fd。
    func startWatching() {
        // 重复调用先停掉旧源——保证「最多一个已武装源」且无 fd 泄漏。
        stopWatching()

        // 监听器需要一个已存在目录的 fd；故先确保 Backups/ 存在。创建失败不致命——
        // 下方 open 会失败而跳过武装，refreshSnapshots() 仍安全返回空列表。
        try? FileManager.default.createDirectory(
            at: backupsDirectory, withIntermediateDirectories: true
        )
        // 打开面板即刷新一次，让列表立刻反映磁盘现状（不必等首个 vnode 事件）。
        refreshSnapshots()
        arm()
    }

    /// 停止监听——由 Data 面板的 `.onDisappear` 调用。
    /// **幂等**：未在监听时为 no-op；在监听时 `cancel()`（其 cancel handler `close()` fd）并清引用。
    func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }

    /// 用 DispatchSource vnode 源监听 Backups/ 目录：在 Finder 里删/改/重命名快照后，
    /// 应用内列表实时反映（仅在监听激活期间，即 Data 面板可见时）。
    ///
    /// 设计：
    /// - 以 O_EVTONLY 打开目录 fd（只为接收事件，不占用文件）。
    /// - 事件掩码 [.write, .delete, .rename, .extend] 覆盖目录内增/删/改名（.write）、目录自身被删
    ///   （.delete）、目录被改名/移动（.rename）。
    /// - 回调投递到 **主队列**：本服务 @MainActor，snapshots 的读写与 SwiftUI 重渲染都须在主线程。
    /// - 目录自身被删/改名（.delete/.rename）→ 取消当前源，重建目录并重新武装（re-arm），
    ///   保证监听激活期间监听器始终指向一个有效 fd；同时刷新列表（目录没了即空表，绝不崩溃）。
    private func arm() {
        let fd = open(backupsDirectory.path, O_EVTONLY)
        // 目录不存在/打不开时不武装；后续某次 snapshot()/操作仍会经 refreshSnapshots() 更新 UI。
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // 目录被删/改名：当前 fd 失效，重建目录并重新武装一个新源（仍在监听期内）。
                self.directorySource?.cancel()
                self.directorySource = nil
                try? FileManager.default.createDirectory(
                    at: self.backupsDirectory, withIntermediateDirectories: true
                )
                self.refreshSnapshots()
                self.arm()
            } else {
                // 目录内有增删改名 → 重新扫描刷新可观察列表。
                self.refreshSnapshots()
            }
        }
        // cancel 时关闭 fd（stopWatching、re-arm、deinit 都经此路径，避免泄漏）。
        source.setCancelHandler {
            close(fd)
        }
        directorySource = source
        source.resume()
    }

    // MARK: - Helpers

    /// App 短版本号（CFBundleShortVersionString），缺失时回退占位。
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
