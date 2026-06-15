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

    /// 待确认删除的快照（驱动 confirmationDialog）。
    @State private var snapshotPendingDelete: SnapshotInfo?

    /// 当前鼠标悬停的快照行 id；用于「仅悬停时显露 Delete 按钮」的列表常见模式。
    @State private var hoveredSnapshotID: SnapshotInfo.ID?

    var body: some View {
        Form {
            backupSection
            restoreResetSection
            snapshotsSection
        }
        .formStyle(.grouped)
        // 监听器只在本面板可见时运行：进入即 startWatching（内含一次刷新 + 武装 vnode 源），
        // 离开即 stopWatching（取消源、关闭 fd），避免 Settings 窗口未开时整生命周期空转监听。
        .onAppear { backup.startWatching() }
        .onDisappear { backup.stopWatching() }
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: deleteDialogPresented,
            titleVisibility: .visible,
            presenting: snapshotPendingDelete
        ) { info in
            Button("Delete", role: .destructive) { deleteSnapshot(info) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes this safety-net snapshot. This can’t be undone.")
        }
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
            // 直接读 backup.snapshots（可观察）——目录监听器/in-app 操作改动它时 SwiftUI 自动重渲染。
            if backup.snapshots.isEmpty {
                Text("No snapshots yet. Relay creates one automatically before any reset or import.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(backup.snapshots) { info in
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
        let isHovered = hoveredSnapshotID == info.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(info.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text(byteCount(info.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { restoreSnapshot(info) }
            Button("Reveal in Finder") { revealInFinder(info) }
            // 与同排「Restore / Reveal in Finder」统一为文本按钮；role: .destructive 让系统给红色、
            // 保留「危险」语义（复用既有 Delete 本地化键，不新增字符串）。
            // 「仅悬停显露」常见列表模式：用 .opacity 而非条件 if，让按钮始终占位——隐藏/显示不重排该行，
            // Restore/Reveal 不会跳动；隐藏时再 .allowsHitTesting(false) 去掉不可见的可点击目标。
            Button("Delete", role: .destructive) {
                snapshotPendingDelete = info
            }
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        // 逐行各自跟踪悬停：进入设为本行 id；离开仅在「当前记录的就是本行」时清空，
        // 避免快速划过相邻行时 B 行的「离开」误清掉 A 行刚设的悬停态。
        .onHover { hovering in
            hoveredSnapshotID = hovering ? info.id : (hoveredSnapshotID == info.id ? nil : hoveredSnapshotID)
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
        // 防御：外部删除竞态——文件可能在列表渲染后、点击前已被删。明确报错并刷新列表，绝不崩溃。
        guard FileManager.default.fileExists(atPath: info.url.path) else {
            presentMissingSnapshot(title: String(localized: "Couldn’t restore snapshot"))
            return
        }
        let restored: AppConfiguration
        do {
            restored = try backup.readBackup(from: info.url)
        } catch {
            presentError(error, title: String(localized: "Couldn’t restore snapshot"))
            backup.refreshSnapshots()
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

    // MARK: - 动作：删除单份快照

    private func deleteSnapshot(_ info: SnapshotInfo) {
        do {
            // deleteSnapshot 对「文件已不存在」按成功处理；这里只需把别的 IO 错误报出来。
            try backup.deleteSnapshot(info)
        } catch {
            presentError(error, title: String(localized: "Couldn’t delete snapshot"))
            backup.refreshSnapshots()
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
        backup.refreshSnapshots()
    }

    // MARK: - Finder

    private func revealInFinder(_ info: SnapshotInfo) {
        // 防御：外部删除竞态——文件已不在时 activateFileViewerSelecting 会无声打开父目录，
        // 体验上像「什么都没发生」。改为明确报错并刷新列表。
        guard FileManager.default.fileExists(atPath: info.url.path) else {
            presentMissingSnapshot(title: String(localized: "Couldn’t reveal snapshot"))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([info.url])
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

    /// 快照文件已不存在（外部删除竞态）时的统一提示：明确告知 + 刷新列表去掉幽灵行。
    private func presentMissingSnapshot(title: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = String(localized: "This snapshot no longer exists. It may have been deleted outside Relay.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        backup.refreshSnapshots()
    }

    // MARK: - confirmationDialog 绑定

    /// 把 `snapshotPendingDelete` 是否有值映射为 Bool 绑定，驱动删除确认对话框。
    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { snapshotPendingDelete != nil },
            set: { if !$0 { snapshotPendingDelete = nil } }
        )
    }
}
