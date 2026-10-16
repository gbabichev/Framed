// Native AppKit integration checks: these operate only on disposable test windows/projects.
import AppKit

@MainActor
final class LifecycleDelegate: NSObject, NSApplicationDelegate {
    var expectsTermination = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return ProjectTerminationCoordinator.shared.applicationShouldTerminate(sender)
    }
    func applicationWillTerminate(_ notification: Notification) {
        precondition(expectsTermination, "Unexpected quit")
        print("PASS: native dirty indicator; close Cancel, Save, failed Save, cancelled Save As, Don't Save; quit Cancel and multiwindow Don't Save")
        fflush(stdout)
    }
}

@main
struct ProjectLifecycleChecks {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = LifecycleDelegate()
        app.delegate = delegate
        Task { @MainActor in
            do { try await check(delegate: delegate) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        app.run()
        withExtendedLifetime(delegate) {}
    }

    @MainActor
    static func pause() async { try? await Task.sleep(for: .milliseconds(300)) }

    @MainActor
    static func button(_ title: String, in window: NSWindow) -> NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == title { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return window.contentView.flatMap(find)
    }

    @MainActor
    static func click(_ title: String, on parent: NSWindow) async {
        for _ in 0..<30 {
            if title == "Cancel", let panel = parent.attachedSheet as? NSSavePanel {
                panel.cancel(nil)
                await pause()
                return
            }
            if let sheet = parent.attachedSheet, let button = button(title, in: sheet) {
                button.performClick(nil)
                await pause()
                return
            }
            await pause()
        }
        if let sheet = parent.attachedSheet as? NSSavePanel, title == "Cancel" {
            sheet.cancel(nil)
            await pause()
            return
        }
        fatalError("Missing sheet button: \(title)")
    }

    @MainActor
    static func fixture() -> (EditorModel, NSWindow, ProjectWindowView) {
        let model = EditorModel()
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Framed disposable lifecycle check"
        let view = ProjectWindowView()
        view.model = model
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.attach()
        return (model, window, view)
    }

    @MainActor
    static func scheduleNative(after interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    @MainActor
    static func dismissQuitSheets(in windows: [NSWindow], remaining: Int, attempts: Int = 0) {
        guard remaining > 0 else { return }
        precondition(attempts < 30, "Quit did not prompt for all dirty windows")
        scheduleNative(after: 0.3) {
            if let parent = windows.first(where: { $0.attachedSheet != nil }),
               let sheet = parent.attachedSheet, let discard = button("Don’t Save", in: sheet) {
                discard.performClick(nil)
                dismissQuitSheets(in: windows.filter { $0 !== parent }, remaining: remaining - 1)
            } else {
                dismissQuitSheets(in: windows, remaining: remaining, attempts: attempts + 1)
            }
        }
    }

    @MainActor
    static func check(delegate: LifecycleDelegate) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FramedLifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, window, view) = fixture()
        precondition(!window.isDocumentEdited, "Fresh window is dirty")
        model.settings.deviceScale = 0.7; view.attach()
        precondition(window.isDocumentEdited, "Native dirty indicator not set")
        window.performClose(nil)
        await click("Cancel", on: window)
        precondition(window.isVisible && model.isDirty, "Close Cancel lost work")
        window.performClose(nil)
        await click("Save", on: window)
        await click("Cancel", on: window)
        precondition(window.isVisible && model.isDirty && model.projectURL == nil, "Cancelled Save As closed window")
        let url = directory.appendingPathComponent("Saved.framed")
        precondition(model.writeProject(to: url))
        model.settings.deviceScale = 0.8; view.attach()
        window.performClose(nil)
        await click("Save", on: window)
        precondition(!model.isDirty && !window.isVisible, "Save-and-close failed")
        let saved = try FramedProject.read(from: url)
        precondition(saved.settings.deviceScale == 0.8, "Close Save did not persist latest canvas")

        let (failing, failureWindow, failureView) = fixture()
        let missingDirectory = directory.appendingPathComponent("remove-me")
        try FileManager.default.createDirectory(at: missingDirectory, withIntermediateDirectories: true)
        precondition(failing.writeProject(to: missingDirectory.appendingPathComponent("WillFail.framed")))
        try FileManager.default.removeItem(at: missingDirectory)
        failing.jpeg = true; failureView.attach()
        failureWindow.performClose(nil)
        await click("Save", on: failureWindow)
        precondition(failureWindow.isVisible && failing.isDirty && failing.error != nil, "Failed Save closed dirty window")
        failureWindow.performClose(nil)
        await click("Don’t Save", on: failureWindow)
        precondition(!failureWindow.isVisible, "Don't Save did not close window")

        let (first, firstWindow, firstView) = fixture()
        first.jpeg = true; firstView.attach()
        scheduleNative(after: 0.5) {
            guard let sheet = firstWindow.attachedSheet, let cancel = button("Cancel", in: sheet) else {
                fatalError("Quit did not present Cancel")
            }
            cancel.performClick(nil)
        }
        NSApplication.shared.terminate(nil)
        await pause(); await pause()
        precondition(firstWindow.isVisible && first.isDirty && firstWindow.attachedSheet == nil, "Quit Cancel lost work")

        let (second, secondWindow, secondView) = fixture()
        second.jpeg = true; secondView.attach()
        delegate.expectsTermination = true
        dismissQuitSheets(in: [firstWindow, secondWindow], remaining: 2)
        NSApplication.shared.terminate(nil)
    }
}
