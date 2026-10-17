//
//  FramedApp.swift
//  Framed
//
//  Created by George Babichev on 10/16/26.
//

import SwiftUI

@main
struct FramedApp: App {
    @NSApplicationDelegateAdaptor(FramedAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .defaultSize(width: 1150, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            ProjectCommands()
            AboutCommands()
        }
        .onChange(of: ProjectWindowRegistry.shared.requestID) { _, _ in
            if ProjectWindowRegistry.shared.needsWindow { openWindow(id: "main") }
        }
    }
}
