//
//  AboutSettingsView.swift
//  Relay
//
//  关于页：应用图标 + 名称 + 版本、简介、GitHub / 许可证 / 第三方致谢链接、版权行。
//  纯静态只读面板——不读写 AppModel，无持久化；版本号在运行时从 bundle 读取（不硬编码）。
//

import SwiftUI
import AppKit

struct AboutSettingsView: View {
    /// GitHub 仓库与许可证链接（verbatim，不本地化）。
    private static let repoURL = URL(string: "https://github.com/is52hertz/Relay")!
    private static let licenseURL = URL(string: "https://github.com/is52hertz/Relay/blob/main/LICENSE")!
    private static let keyboardShortcutsURL = URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!

    var body: some View {
        Form {
            headerSection
            introSection
            linksSection
            acknowledgementsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - 头部：图标 + 名称 + 版本

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                // 当前应用图标（暂用系统/默认图标；自定义 AppIcon 是另一个任务）。
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityLabel("Relay app icon")

                Text(verbatim: "Relay")
                    .font(.title2.weight(.semibold))

                // 版本在运行时从 bundle 读取，避免与 project 设置（MARKETING_VERSION / CURRENT_PROJECT_VERSION）脱节。
                Text(Self.versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 简介

    private var introSection: some View {
        Section {
            Text("A native macOS switcher for launching, focusing, and hiding apps with global hotkeys — organized into scene-based Profiles.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 链接：GitHub + 许可证

    private var linksSection: some View {
        Section {
            // Link 直接交给系统默认浏览器打开；无需 NSWorkspace、无内嵌 WebView、无自有网络请求。
            Link("View on GitHub", destination: Self.repoURL)

            LabeledContent("License") {
                Link(destination: Self.licenseURL) {
                    Text(verbatim: "GPL-3.0")
                }
            }
        }
    }

    // MARK: - 第三方致谢

    private var acknowledgementsSection: some View {
        Section {
            Link(destination: Self.keyboardShortcutsURL) {
                Text(verbatim: "KeyboardShortcuts (MIT)")
            }
        } header: {
            Text("Acknowledgements")
        } footer: {
            Text(verbatim: "© 2026 Teethe")
        }
    }

    // MARK: - 版本字符串

    /// 从 bundle 读取版本并格式化为 "Version 1.0 (1)"（短版本号 + 构建号）。
    /// 纯派生逻辑，便于单测；缺值时回退到 "—"，不崩溃。
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return Self.versionString(short: short, build: build)
    }

    /// 纯函数：拼装版本展示串（"Version %@ (%@)"）。供单测验证格式。
    static func versionString(short: String, build: String) -> String {
        String(localized: "Version \(short) (\(build))")
    }
}
