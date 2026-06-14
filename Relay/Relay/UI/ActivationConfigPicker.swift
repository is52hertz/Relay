//
//  ActivationConfigPicker.swift
//  Relay
//
//  按名称从全局激活配置表中选一份配置的下拉选择器。
//  供 BindingRow（每条绑定）与 GeneralSettingsView（全局默认）共用，避免重复。
//  随 model.activationConfigs 增删/改名实时刷新（@Environment(AppModel) 观察）。
//

import SwiftUI

struct ActivationConfigPicker: View {
    @Environment(AppModel.self) private var model
    let selection: Binding<UUID>

    var body: some View {
        Picker("Behavior", selection: selection) {
            ForEach(model.activationConfigs) { config in
                Text(config.localizedName).tag(config.id)
            }
        }
    }
}
