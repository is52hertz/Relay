//
//  PersonalizationSettingsView.swift
//  Relay
//
//  个性化设置：
//  - 菜单栏图标：预设 SF Symbol 色块行（点选即生效），或在自定义框输入任意符号名（带有效性校验）。
//  - 界面语言：跟随系统 / 简体 / 繁體 / English；切换时弹确认 → 经 LanguageService 重启生效。
//

import SwiftUI
import AppKit

struct PersonalizationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LanguageService.self) private var language

    /// 选择器回显的当前选择；onAppear 同步为 LanguageService.current。
    @State private var selection: AppLanguage = .system
    /// 待确认切换的目标语言（非 nil 时弹重启确认）。
    @State private var pending: AppLanguage?

    /// 自定义 SF Symbol 输入框内容（留空显示占位符；输入有效名后点 Apply 写入设置）。
    @State private var customInput: String = ""
    /// 上次自定义输入是否无效（无效时提示且不写入设置）。
    @State private var customInvalid: Bool = false

    var body: some View {
        Form {
            languageSection
            menuBarIconSection
            menuBarVisibilitySection
        }
        .formStyle(.grouped)
        .onAppear {
            selection = language.current
        }
        .confirmationDialog(
            "Restart Relay to change language?",
            isPresented: dialogPresented,
            titleVisibility: .visible,
            presenting: pending
        ) { target in
            Button("Restart Now") { language.apply(target) }
            // 取消：选择器回退由 dialogPresented setter 统一处理（覆盖 Esc / 点外部 / Cancel）。
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("Relay needs to restart to switch languages. Your settings are saved.")
        }
    }

    // MARK: - 菜单栏图标

    @ViewBuilder
    private var menuBarIconSection: some View {
        Section {
            LabeledContent("Current") {
                Image(systemName: model.settings.menuBarIconName)
                    .imageScale(.large)
                    .accessibilityLabel("Current menu bar icon")
            }
            HStack(spacing: 10) {
                ForEach(AppSettings.menuBarIconPresets, id: \.self) { name in
                    swatch(name)
                }
            }
        } header: {
            Text("Menu Bar Icon")
        } footer: {
            Text("Pick a preset, or enter any SF Symbol below. Changes apply immediately.")
        }

        Section {
            HStack(spacing: 8) {
                // 无边框、占位符提示——分组表单原生输入样式；不预填值，一眼是输入框。
                TextField("SF Symbol name", text: $customInput, prompt: Text(verbatim: "star.fill"))
                    .labelsHidden()
                    .onSubmit(applyCustomSymbol)
                // 实时预览：仅在有输入时出现于行尾（当前生效图标由色块选中环 / 预设区体现）。
                if !trimmedCustom.isEmpty {
                    Image(systemName: customPreviewName)
                        .imageScale(.large)
                        .foregroundStyle(customInvalid ? .secondary : .primary)
                        .accessibilityHidden(true)
                }
                Button("Apply", action: applyCustomSymbol)
                    .disabled(trimmedCustom.isEmpty)
            }
            if customInvalid {
                Label("Not a valid SF Symbol name.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } header: {
            Text("Custom SF Symbol")
        } footer: {
            Text("Type any SF Symbol name (for example star.fill). Invalid names are ignored, so the icon never goes blank.")
        }
    }

    /// 预设的单个图标色块（选中态：高亮底 + 强调色描边 + VoiceOver isSelected）。
    private func swatch(_ name: String) -> some View {
        let isSelected = model.settings.menuBarIconName == name
        return Button {
            iconBinding.wrappedValue = name
        } label: {
            Image(systemName: name)
                .imageScale(.large)
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 菜单栏图标可见性 + 全局切换热键（F-A / F-B）

    @ViewBuilder
    private var menuBarVisibilitySection: some View {
        Section {
            // 显示/隐藏开关。锁定守卫（R5）：未设切换热键时禁用「隐藏」，避免把自己锁在菜单栏外。
            Toggle("Show menu bar icon", isOn: showIconBinding)
                .disabled(!canHideIcon && model.settings.showMenuBarIcon)

            LabeledContent("Toggle hotkey") {
                ShortcutRecorder(hotkey: toggleHotkeyBinding)
                    .fixedSize()
            }
        } header: {
            Text("Menu Bar Icon Visibility")
        } footer: {
            // 未设热键时解释为何不能隐藏（锁定守卫引导）。
            if !canHideIcon {
                Text("Set a toggle hotkey before you can hide the icon. The hotkey always brings it back, even when the icon is hidden, so you’re never locked out.")
            } else {
                Text("Press the toggle hotkey to show or hide the menu bar icon at any time. It works in any profile and isn’t cleared when you switch profiles.")
            }
        }
    }

    /// 是否已配置切换热键（决定能否隐藏图标）。
    private var canHideIcon: Bool {
        model.settings.menuBarToggleHotkey != nil
    }

    /// 显示/隐藏开关绑定：写经 AppModel.setMenuBarIconVisible（含锁定守卫）。
    private var showIconBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showMenuBarIcon },
            set: { model.setMenuBarIconVisible($0) }
        )
    }

    /// 切换热键绑定：写经 AppModel.setMenuBarToggleHotkey（清除热键且图标隐藏时会自动唤回图标）。
    private var toggleHotkeyBinding: Binding<Hotkey?> {
        Binding(
            get: { model.settings.menuBarToggleHotkey },
            set: { model.setMenuBarToggleHotkey($0) }
        )
    }

    // MARK: - 语言

    private var languageSection: some View {
        Section {
            Picker("Language", selection: languageBinding) {
                ForEach(AppLanguage.allCases) { option in
                    // displayName 已是最终展示串（自名 / 已本地化），用变量初始化器即可（不二次本地化）。
                    Text(option.displayName).tag(option)
                }
            }
        } footer: {
            Text("Relay restarts to apply a new language.")
        }
    }

    // MARK: - 菜单栏图标 bindings / helpers

    /// 写回 model.settings（经 AppModel setter 去抖落盘 + settingsDidChange）。
    private var iconBinding: Binding<String> {
        Binding(
            get: { model.settings.menuBarIconName },
            set: { newValue in
                var settings = model.settings
                settings.menuBarIconName = newValue
                model.settings = settings
                // 选了预设后让自定义框回显，保持一致。
                customInput = newValue
                customInvalid = false
            }
        )
    }

    private var trimmedCustom: String {
        customInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 预览用：当前输入有效→预览输入图标；否则回退到当前生效图标。
    private var customPreviewName: String {
        isValidSymbol(trimmedCustom) ? trimmedCustom : model.settings.menuBarIconName
    }

    /// 应用自定义符号：有效则写入设置，无效则提示且不改设置（菜单栏不空白）。
    private func applyCustomSymbol() {
        let name = trimmedCustom
        guard !name.isEmpty else { return }
        if isValidSymbol(name) {
            customInvalid = false
            iconBinding.wrappedValue = name
        } else {
            customInvalid = true
        }
    }

    /// SF Symbol 有效性校验（AppKit，仅视图层使用；模型层不引 AppKit）。
    private func isValidSymbol(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    // MARK: - 语言 bindings

    /// 选新语言 → 记 pending 弹确认；选回当前语言 → 不弹。
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                pending = newValue == language.current ? nil : newValue
            }
        )
    }

    /// 关闭分支（Esc / 点外部 / Cancel 都经此）统一回退：清 pending 并把选择器回显到当前生效语言。
    private var dialogPresented: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { presented in
                if !presented {
                    pending = nil
                    selection = language.current
                }
            }
        )
    }
}
