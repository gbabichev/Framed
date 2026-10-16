//
//  FramedApp.swift
//  Framed
//
//  Created by George Babichev on 10/16/26.
//

import SwiftUI

@main
struct FramedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1150, height: 800)
        .windowResizability(.contentMinSize)
    }
}
