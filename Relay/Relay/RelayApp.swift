//
//  RelayApp.swift
//  Relay
//

import SwiftUI

@main
struct RelayApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Relay", systemImage: "command") {
            MenuBarContent()
                .environment(controller.model)
        }

        Settings {
            SettingsRootView()
                .environment(controller.model)
                .environment(controller.resolver)
        }
    }
}
