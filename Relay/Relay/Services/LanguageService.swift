//
//  LanguageService.swift
//  Relay
//
//  界面语言切换：把用户选择写入 AppleLanguages（per-app 覆盖）并重启 App 生效。
//  与 LoginItemService 思路一致——真相是 OS 侧状态（AppleLanguages），不进 Codable JSON。
//  本地化机制本身用 Xcode 推荐的 String Catalog（Localizable.xcstrings），此处只管「选哪种语言」。
//

import AppKit
import Observation

/// 用户可选的界面语言。`.system` = 不覆盖、跟随系统；其余覆盖为指定语言。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese
    case traditionalChinese

    var id: String { rawValue }

    /// 写入 AppleLanguages 的语言代码；`.system` 无代码（移除覆盖）。
    var localeCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        }
    }

    /// 选择器显示名：语言名用本族自名（autonym，不翻译）；「跟随系统」一项本地化。
    var displayName: String {
        switch self {
        case .system: String(localized: "Use System Language")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        }
    }
}

@MainActor
@Observable
final class LanguageService {
    /// 我方专属偏好键：记录用户在选择器里的选择，作为选择器回显的唯一真相。
    /// 不直接读 AppleLanguages 判断——它在全局域恒有系统值，无法区分「显式选英文」与「跟随系统」。
    private let preferenceKey = "RelayPreferredLanguage"
    /// 系统 per-app 语言覆盖键（写入 App 自身偏好域即覆盖本 App 启动语言）。
    private let appleLanguagesKey = "AppleLanguages"

    /// 重启前同步 flush 配置落盘的钩子（组合根注入 model.saveNow，同 hotkeysDidChange 的惯例）。
    /// 不直接持有 AppModel——只经闭包，保持本服务不依赖其具体类型。
    @ObservationIgnored private let flushBeforeRelaunch: @MainActor () -> Void

    init(flushBeforeRelaunch: @escaping @MainActor () -> Void = {}) {
        self.flushBeforeRelaunch = flushBeforeRelaunch
    }

    /// 当前选择：读我方偏好键；无值或不识别 → `.system`。
    var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
              let language = AppLanguage(rawValue: raw) else { return .system }
        return language
    }

    /// 应用选择并重启 App 生效。`.system` 移除 per-app 覆盖、回退系统语言。
    func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: preferenceKey)
        if let code = language.localeCode {
            defaults.set([code], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        // 必须在拉起新实例前落盘，否则新实例可能读到旧 AppleLanguages。
        defaults.synchronize()
        relaunch()
    }

    /// 拉起一个全新实例再终止当前实例：新实例启动时读到更新后的 AppleLanguages。
    /// 必须在 `open -n` 之前同步 flush 配置：否则新实例可能在旧实例 `willTerminate` flush 前
    /// 就读盘拿到旧 JSON（编辑仍在 400ms 去抖窗口内），新实例后续一保存即覆盖刚 flush 的编辑 → 丢数据。
    private func relaunch() {
        flushBeforeRelaunch()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
