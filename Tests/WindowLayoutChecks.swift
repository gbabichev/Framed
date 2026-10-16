// Standalone native-window smoke test. Compile with the app's sources except FramedApp.swift.
// Exercises the real ContentView at the size reported in the startup crash and through resizing.
import AppKit
import SwiftUI

@main
struct WindowLayoutChecks: App {
    var body: some Scene {
        WindowGroup("Framed Layout Check") {
            ContentView()
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                        fputs("FAIL: no visible window\n", stderr)
                        exit(1)
                    }
                    let sizes: [NSSize] = [
                        .init(width: 900, height: 640),
                        .init(width: 1150, height: 800),
                        .init(width: 900, height: 692),
                        .init(width: 1400, height: 950)
                    ]
                    for _ in 0..<3 {
                        for size in sizes {
                            fputs("Resize to \(size); window minimum \(window.contentMinSize)\n", stderr)
                            window.setContentSize(size)
                            window.contentView?.layoutSubtreeIfNeeded()
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                    }
                    print("PASS: native window startup and 12 resize passes, including the reported crash size")
                    NSApplication.shared.terminate(nil)
                }
        }
        .defaultSize(width: 900, height: 692)
        .windowResizability(.contentMinSize)
    }
}
