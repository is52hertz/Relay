//
//  DockIconController.swift
//  Relay
//
//  运行时切换 Dock 图标：.regular 显示、.accessory 隐藏（基线由 LSUIElement=YES 设为隐藏）。
//

import AppKit

@MainActor
final class DockIconController {
    func setDockIconVisible(_ visible: Bool) {
        // NSApplication.shared（非可选，惰性创建）——AppController 在 @State 初始化期运行时 NSApp 可能尚为 nil。
        NSApplication.shared.setActivationPolicy(visible ? .regular : .accessory)
        // 切到 .accessory 会让 App 失活、窗口被藏到后面；重新激活以保持窗口可见。
        NSApplication.shared.activate()
    }
}
