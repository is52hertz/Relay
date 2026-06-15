//
//  DataSettingsView.swift
//  Relay
//
//  数据管理面板：导出（备份）/ 导入（恢复）/ 重置默认，以及破坏性操作前自动写的「滚动快照」列表。
//  NSSavePanel/NSOpenPanel/NSAlert 与 NSWorkspace 都集中在本视图（UI 层）；编解码/快照轮换在 BackupService。
//  所有破坏性替换都走「先快照 → 再 model.replaceConfiguration」同一路径，确保始终有撤销兜底（PRD R4）。
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BackupService.self) private var backup

    /// 快照列表（每次出现/操作后刷新；避免每帧扫盘）。
    @State private var snapshots: [SnapshotInfo] = []

    var body: some View {
        Form {
            backupSection
            restoreResetSection
            snapshotsSection
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadSnapshots)
    }

    // MARK: - Backup（导出）

    private var backupSection: some View {
        Section {
            LabeledContent("Backup") {
                Button("Export…", action: exportBackup)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Save a portable copy of your profiles, shortcuts, behaviors, and settings to a file.")
        }
    }

    // MARK: - Restore / Reset

    private var restoreResetSection: some View {
        Section {
            LabeledContent("Restore") {
                Button("Import…", action: importBackup)
            }
            LabeledContent("Reset") {
                Button("Reset to Defaults…", role: .destructive, action: resetToDefaults)
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Importing or resetting replaces your current data. Relay takes a snapshot first so you can undo.")
        }
    }

    // MARK: - Automatic Snapshots

    private var snapshotsSection: some View {
        Section {
            if snapshots.isEmpty {
                Text("No snapshots yet. Relay creates one automatically before any reset or import.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(snapshots) { info in
                    snapshotRow(info)
                }
            }
        } header: {
            Text("Automatic Snapshots")
        } footer: {
            Text("Relay keeps the 10 most recent snapshots, taken before each reset or import.")
        }
    }

    private func snapshotRow(_ info: SnapshotInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text(byteCount(info.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { restoreSnapshot(info) }
            Button("Reveal in Finder") { revealInFinder(info.url) }
        }
    }

    // MARK: - 动作：导出

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose where to save your Relay backup.")
        panel.nameFieldStringValue = defaultBackupFilename()
        // 用动态 UTType（filenameExtension）避免在 Info.plist/pbxproj 注册自定义 UTI；
        // 同时允许 .json 以防系统把扩展名当通用 JSON。
        panel.allowedContentTypes = backupContentTypes()
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try backup.writeBackup(model.configuration, to: url)
        } catch {
            presentError(error, title: String(localized: "Couldn’t export backup"))
        }
    }

    // MARK: - 动作：导入

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose a Relay backup file to import.")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = backupContentTypes()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imported: AppConfiguration
        do {
            imported = try backup.readBackup(from: url)
        } catch {
            // 损坏 / 过新 schema → 明确报错，当前数据不动（PRD R2）。
            presentError(error, title: String(localized: "Couldn’t import backup"))
            return
        }

        confirmDestructive(
            title: String(localized: "Replace your current data?"),
            message: String(localized: "Importing this backup replaces all your current profiles, shortcuts, behaviors, and settings. A snapshot is taken first."),
            confirmTitle: String(localized: "Import & Replace")
        ) {
            applyReplacement(imported)
        }
    }

    // MARK: - 动作：重置

    private func resetToDefaults() {
        confirmDestructive(
            title: String(localized: "Reset Relay to defaults?"),
            message: String(localized: "This replaces all your current profiles, shortcuts, behaviors, and settings with the defaults. A snapshot is taken first."),
            confirmTitle: String(localized: "Reset")
        ) {
            applyReplacement(.makeDefault())
        }
    }

    // MARK: - 动作：从快照恢复

    private func restoreSnapshot(_ info: SnapshotInfo) {
        let restored: AppConfiguration
        do {
            restored = try backup.readBackup(from: info.url)
        } catch {
            presentError(error, title: String(localized: "Couldn’t restore snapshot"))
            return
        }
        confirmDestructive(
            title: String(localized: "Restore this snapshot?"),
            message: String(localized: "Restoring replaces all your current data with this snapshot. A new snapshot of your current data is taken first."),
            confirmTitle: String(localized: "Restore")
        ) {
            applyReplacement(restored)
        }
    }

    // MARK: - 共享替换路径：先安全快照（失败让用户决定），再整体替换

    /// 所有破坏性替换（import/reset/restore）的统一收尾：先 snapshot(当前 config)，再 replaceConfiguration。
    /// 快照失败 → 弹「无网兜底，是否仍继续」让用户决定（PRD R4：绝不静默销毁）。
    private func applyReplacement(_ new: AppConfiguration) {
        do {
            try backup.snapshot(model.configuration)
        } catch {
            // 安全快照失败：不静默继续也不静默中止，交给用户选择。
            let proceed = confirmSnapshotFailure(error)
            guard proceed else { return }
        }
        model.replaceConfiguration(new)
        reloadSnapshots()
    }

    // MARK: - 列表刷新 / Finder

    private func reloadSnapshots() {
        snapshots = backup.listSnapshots()
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 文件名 / UTType helpers

    private func defaultBackupFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Relay-Backup-\(formatter.string(from: Date())).relaybackup"
    }

    /// 动态 UTType（不注册自定义 UTI）：自定义扩展名 + 通用 JSON。
    private func backupContentTypes() -> [UTType] {
        var types: [UTType] = []
        if let relay = UTType(filenameExtension: "relaybackup") {
            types.append(relay)
        }
        types.append(.json)
        return types
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - 弹窗 helpers（NSAlert，集中在 UI 层）

    /// 破坏性确认（红色「确认」+ 取消）。确认才执行 action。
    private func confirmDestructive(
        title: String, message: String, confirmTitle: String, action: () -> Void
    ) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            action()
        }
    }

    /// 安全快照失败：让用户决定是否仍继续（无撤销网）。返回 true = 继续。
    private func confirmSnapshotFailure(_ error: Error) -> Bool {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t create a safety snapshot")
        alert.informativeText = String(localized: "Relay couldn’t save a snapshot of your current data before this change. If you continue, you won’t be able to undo it. Continue anyway?")
        let proceed = alert.addButton(withTitle: String(localized: "Continue Anyway"))
        proceed.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ error: Error, title: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
