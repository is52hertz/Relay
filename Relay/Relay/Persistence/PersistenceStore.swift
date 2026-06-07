//
//  PersistenceStore.swift
//  Relay
//
//  把 AppConfiguration 读写到 Application Support 下的 JSON。原子写。
//  v1 在主线程同步 IO（配置极小，见 PRD P1-12）。
//

import Foundation

@MainActor
final class PersistenceStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? PersistenceStore.defaultFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("cn.Teethe.Relay", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// 读取；文件不存在或解析失败时返回 nil（调用方回退到默认配置）。
    func load() -> AppConfiguration? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(AppConfiguration.self, from: data)
    }

    /// 原子写入；自动创建目录。
    func save(_ configuration: AppConfiguration) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: [.atomic])
    }
}
