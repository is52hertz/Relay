//
//  ShortcutRecorder.swift
//  Relay
//
//  自绘快捷键录入控件。点击后用「本地」NSEvent keyDown 监听捕获组合（仅 App 在前台时，
//  不需 Accessibility/Input Monitoring），用 KeyboardShortcuts.Shortcut(event:) 解析，
//  写回我方 Hotkey。不依赖库的 Name 存储/自动注册——注册由 HotkeyRegistrationService 统一做。
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.toggle(_:)))
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        context.coordinator.button = button
        context.coordinator.refreshTitle()
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.isRecording {
            context.coordinator.refreshTitle()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ShortcutRecorder
        weak var button: NSButton?
        private(set) var isRecording = false
        private var monitor: Any?

        init(_ parent: ShortcutRecorder) {
            self.parent = parent
        }

        @objc func toggle(_ sender: NSButton) {
            isRecording ? stop() : start()
        }

        private func start() {
            isRecording = true
            button?.title = "Type shortcut…"
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    return self.handle(event) ? nil : event
                }
            }
        }

        private func stop() {
            isRecording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            refreshTitle()
        }

        /// 返回是否消费该事件。
        private func handle(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 53: // Esc → 取消
                stop()
                return true
            case 51, 117: // Delete / Forward-Delete → 清空
                parent.hotkey = nil
                stop()
                return true
            default:
                guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return false }
                parent.hotkey = Hotkey(shortcut)
                stop()
                return true
            }
        }

        func refreshTitle() {
            button?.title = parent.hotkey?.displayString ?? "Record Shortcut"
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
