//
//  PersonalizationSettingsView.swift
//  Relay
//
//  个性化设置：界面语言选择（跟随系统 / 简体 / 繁體 / English）。
//  切换为新语言时弹确认 → 经 LanguageService 写入 AppleLanguages 并重启生效。
//

import SwiftUI

struct PersonalizationSettingsView: View {
    @Environment(LanguageService.self) private var language

    /// 选择器回显的当前选择；onAppear 同步为 LanguageService.current。
    @State private var selection: AppLanguage = .system
    /// 待确认切换的目标语言（非 nil 时弹重启确认）。
    @State private var pending: AppLanguage?

    var body: some View {
        Form {
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
        .formStyle(.grouped)
        .onAppear { selection = language.current }
        .confirmationDialog(
            "Restart Relay to change language?",
            isPresented: dialogPresented,
            titleVisibility: .visible,
            presenting: pending
        ) { target in
            Button("Restart Now") { language.apply(target) }
            // 取消：回退选择器到当前生效语言。
            Button("Cancel", role: .cancel) { selection = language.current }
        } message: { _ in
            Text("Relay needs to restart to switch languages. Your settings are saved.")
        }
    }

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

    private var dialogPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }
}
