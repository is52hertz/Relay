//
//  RelayApp.swift
//  Relay
//

import SwiftUI

@main
struct RelayApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Relay", systemImage: "command") {
            MenuBarContent()
                .environment(model)
        }

        Settings {
            SettingsRootView()
                .environment(model)
        }
    }
}
