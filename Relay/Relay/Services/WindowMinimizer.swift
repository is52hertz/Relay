//
//  WindowMinimizer.swift
//  Relay
//
//  唯一引入 Accessibility 的服务：把目标 App 的焦点/主窗口最小化。
//  AX 全部封装在此（@MainActor），模型/决策层保持 nonisolated 且无 AX。
//  权限延迟申请——绝不在启动时弹窗；仅用户在编辑器选「Minimize」时显式提示（见 PRD D5）。
//

import ApplicationServices
import AppKit
import Observation

@MainActor
@Observable
final class WindowMinimizer {
    /// AX 不可信、最小化未实际执行时回调（用于一次性提示，见 PRD D4）。
    /// 由 AppController 接线（执行层只「无操作 + 一次性提示」，绝不退化为其它破坏性动作）。
    @ObservationIgnored var onPermissionDenied: (() -> Void)?

    /// 当前是否已获 Accessibility 信任（只读，不弹窗）。
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// 显式申请 Accessibility 权限：弹系统提示并打开「系统设置 › 隐私与安全性 › 辅助功能」。
    /// 仅在用户主动选择「Minimize」时调用（PRD D5）。返回调用时是否已信任。
    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 最小化给定 pid 的焦点窗口（回退主窗口）。仅作用于「焦点/主窗口」而非全部窗口（PRD D3）。
    /// AX 不可信时：不做任何破坏性操作，触发一次性提示回调（PRD D4）。
    func minimizeFocusedWindow(ofPID pid: pid_t) {
        guard isTrusted else {
            onPermissionDenied?()
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = focusedOrMainWindow(of: appElement) else { return }
        let trueValue = kCFBooleanTrue as CFTypeRef
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, trueValue)
    }

    /// 取消最小化给定 pid 的焦点/主窗口（机会式，PRD D7）。仅在「已信任」时由 focus 路径调用：
    /// 绝不在此弹窗、不触发 onPermissionDenied——未信任时静默返回，保持 openApplication 原行为。
    /// 窗口解析与类型校验复用 minimize 的逻辑（focusedOrMainWindow）。
    func unminimizeFocusedWindow(ofPID pid: pid_t) {
        guard isTrusted else { return }
        let appElement = AXUIElementCreateApplication(pid)
        guard let window = focusedOrMainWindow(of: appElement) else { return }
        let falseValue = kCFBooleanFalse as CFTypeRef
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, falseValue)
    }

    /// 该 pid 的 App 是否存在「可见（未最小化）窗口」（PRD D8：前台 = 有可见窗口）。
    /// 仅在「已信任」时由 runtimeState 调用——绝不弹窗、不触发 onPermissionDenied（与 D7 一致）。
    /// 失败安全（fail-safe）：除非能确定「0 窗口」或「全部已最小化」，否则一律返回 true，
    /// 以保持当前 .frontmost 分类，永不在不确定时误降级到后台。
    ///   - copy kAXWindowsAttribute 失败 / 不是数组 → true（读取错误，保守）。
    ///   - 数组为空（确定 0 窗口）→ false（无可见窗口 → 后台）。
    ///   - 任一窗口的 kAXMinimizedAttribute 读到 == false → true（有可见窗口）。
    ///   - 单个窗口读 minimized 失败 → 视为「未能证明已最小化」，不据此降级（倾向 true）。
    ///   - 所有窗口均确认为已最小化 → false。
    func hasVisibleWindow(ofPID pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        // 读取错误 / 类型不符：无法确定 → 保守保留前台分类。
        guard result == .success, let value, CFGetTypeID(value) == CFArrayGetTypeID() else {
            return true
        }
        let windows = value as! [AXUIElement]
        // 确定 0 窗口：无可见窗口 → 后台。
        guard !windows.isEmpty else { return false }
        for window in windows {
            // 仅当能确定该窗口「已最小化」才认定其不可见；读失败/非 false 都倾向「可能可见」。
            if !isWindowMinimized(window) {
                return true
            }
        }
        // 全部窗口均确认已最小化 → 无可见窗口 → 后台。
        return false
    }

    /// 读单个窗口的 kAXMinimizedAttribute；仅当确凿读到 == true 才返回 true，否则 false（保守，不据此降级）。
    private func isWindowMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return false
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    /// 读 kAXFocusedWindowAttribute，失败回退 kAXMainWindowAttribute。
    private func focusedOrMainWindow(of appElement: AXUIElement) -> AXUIElement? {
        if let window = copyWindowAttribute(kAXFocusedWindowAttribute, from: appElement) {
            return window
        }
        return copyWindowAttribute(kAXMainWindowAttribute, from: appElement)
    }

    private func copyWindowAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        // AX 窗口属性返回 AXUIElement；用 CFGetTypeID 校验后再桥接。
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
