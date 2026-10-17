import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

struct ProjectWindowState: NSViewRepresentable {
    let model: EditorModel
    let isEdited: Bool
    let projectURL: URL?

    func makeNSView(context: Context) -> ProjectWindowView { ProjectWindowView() }
    func updateNSView(_ view: ProjectWindowView, context: Context) {
        view.model = model
        view.attach()
        if view.window?.isDocumentEdited != isEdited { view.window?.isDocumentEdited = isEdited }
        view.window?.representedURL = projectURL
    }
}

final class ProjectWindowView: NSView {
    var model: EditorModel?
    private weak var observedWindow: NSWindow?
    private let proxy = WindowCloseDelegateProxy()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detach() } else { attach() }
    }

    deinit { MainActor.assumeIsolated { detach() } }

    func attach() {
        guard let window, let model else { return }
        model.window = window
        if window.isDocumentEdited != model.isDirty { window.isDocumentEdited = model.isDirty }
        window.representedURL = model.projectURL
        guard observedWindow !== window else { return }
        detach()
        observedWindow = window
        model.window = window
        proxy.originalDelegate = window.delegate
        proxy.shouldAllowWindowClose = { [weak self] window in
            guard let self, let model = self.model else { return true }
            guard model.isDirty || model.isBusy || model.isPresentingProjectDialog else { return true }
            model.confirmDiscardingChanges { [weak self, weak window] proceed in
                if proceed, let window { self?.proxy.performDeferredWindowClose(for: window) }
            }
            return false
        }
        window.delegate = proxy
        ProjectTerminationCoordinator.shared.register(
            window: window,
            isDocumentEdited: { [weak model] in
                guard let model else { return false }
                return model.isDirty || model.isBusy || model.isPresentingProjectDialog
            },
            requestClose: { [weak model] completion in
                guard let model else { completion(true); return }
                model.confirmDiscardingChanges(completion: completion)
            }
        )
        ProjectWindowRegistry.shared.attach(window: window, model: model)
    }

    private func detach() {
        guard let observedWindow else { return }
        if observedWindow.delegate === proxy { observedWindow.delegate = proxy.originalDelegate }
        ProjectTerminationCoordinator.shared.unregister(window: observedWindow)
        ProjectWindowRegistry.shared.detach(window: observedWindow)
        model?.releaseProjectAccess()
        proxy.reset()
        self.observedWindow = nil
    }
}

@Observable
final class ProjectWindowRegistry {
    static let shared = ProjectWindowRegistry()
    var requestID = UUID()
    private var pending: [URL] = []
    private var entries: [Entry] = []
    private final class Entry {
        weak var window: NSWindow?
        weak var model: EditorModel?
        init(window: NSWindow, model: EditorModel) { self.window = window; self.model = model }
    }
    var needsWindow: Bool { !pending.isEmpty }

    func attach(window: NSWindow, model: EditorModel) {
        entries.removeAll { $0.window == nil }
        entries.append(Entry(window: window, model: model))
        guard !pending.isEmpty else { return }
        let url = pending.removeFirst()
        Task { @MainActor in
            model.requestOpenProject(at: url)
            if !self.pending.isEmpty { self.requestID = UUID() }
        }
    }
    func detach(window: NSWindow) { entries.removeAll { $0.window === window || $0.window == nil } }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.framedProject]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open([url])
    }

    func open(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "framed" {
            // Finder opens into a fresh window, preserving any work in other windows.
            pending.append(url)
        }
        if !pending.isEmpty { requestID = UUID() }
    }
}

final class FramedAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ProjectTerminationCoordinator.shared.applicationShouldTerminate(sender)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        ProjectWindowRegistry.shared.open(urls)
    }
}

struct ProjectCommands: Commands {
    @FocusedValue(\.projectModel) private var model
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model?.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model?.canUndo != true)
            Button("Redo") { model?.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model?.canRedo != true)
        }
        CommandGroup(after: .newItem) {
            Button("Open Project…") {
                if let model { model.openProject() }
                else { ProjectWindowRegistry.shared.chooseProject() }
            }
                .keyboardShortcut("o").disabled(model?.isBusy == true || model?.isPresentingProjectDialog == true)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Project") { model?.saveProject() }
                .keyboardShortcut("s").disabled(model == nil || model?.isBusy == true || model?.isPresentingProjectDialog == true)
            Button("Save Project As…") { model?.saveProject(asNewFile: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model == nil || model?.isBusy == true || model?.isPresentingProjectDialog == true)
            Divider()
            Button("Close Project") { model?.window?.performClose(nil) }
                .keyboardShortcut("w").disabled(model == nil)
        }
    }
}

private struct ProjectModelKey: FocusedValueKey { typealias Value = EditorModel }
extension FocusedValues {
    var projectModel: EditorModel? {
        get { self[ProjectModelKey.self] }
        set { self[ProjectModelKey.self] = newValue }
    }
}

@MainActor
final class ProjectTerminationCoordinator {
    static let shared = ProjectTerminationCoordinator()

    private final class Entry {
        weak var window: NSWindow?
        var isDocumentEdited: () -> Bool
        var requestClose: (@escaping @MainActor (Bool) -> Void) -> Void

        init(
            window: NSWindow,
            isDocumentEdited: @escaping () -> Bool,
            requestClose: @escaping (@escaping @MainActor (Bool) -> Void) -> Void
        ) {
            self.window = window
            self.isDocumentEdited = isDocumentEdited
            self.requestClose = requestClose
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var pendingApplication: NSApplication?
    private var isResolvingTermination = false

    private init() {}

    func register(
        window: NSWindow,
        isDocumentEdited: @escaping () -> Bool,
        requestClose: @escaping (@escaping @MainActor (Bool) -> Void) -> Void
    ) {
        entries[ObjectIdentifier(window)] = Entry(
            window: window,
            isDocumentEdited: isDocumentEdited,
            requestClose: requestClose
        )
    }

    func unregister(window: NSWindow) {
        entries.removeValue(forKey: ObjectIdentifier(window))
    }

    var hasDirtyDocumentWindow: Bool {
        !currentDirtyEntries().isEmpty
    }

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        let dirtyEntries = currentDirtyEntries()
        guard !dirtyEntries.isEmpty else { return .terminateNow }
        guard !isResolvingTermination else { return .terminateLater }

        isResolvingTermination = true
        pendingApplication = application
        resolveTermination(for: dirtyEntries, index: 0)
        return .terminateLater
    }

    private func currentDirtyEntries() -> [Entry] {
        entries = entries.filter { _, entry in
            entry.window != nil
        }

        return entries.values.filter { entry in
            guard let window = entry.window else { return false }
            return (window.isVisible || window.isMiniaturized) && entry.isDocumentEdited()
        }
    }

    private func resolveTermination(for entries: [Entry], index: Int) {
        guard index < entries.count else {
            finishTermination(shouldTerminate: true)
            return
        }

        let entry = entries[index]
        guard let window = entry.window, entry.isDocumentEdited() else {
            resolveTermination(for: entries, index: index + 1)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)

        entry.requestClose { [weak self] shouldContinue in
            guard let self else { return }

            if shouldContinue {
                resolveTermination(for: entries, index: index + 1)
            } else {
                finishTermination(shouldTerminate: false)
            }
        }
    }

    private func finishTermination(shouldTerminate: Bool) {
        let application = pendingApplication ?? NSApplication.shared
        pendingApplication = nil
        isResolvingTermination = false
        application.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}

private final class WindowCloseDelegateProxy: NSObject, NSWindowDelegate {
    nonisolated(unsafe) var originalDelegate: (NSObjectProtocol & NSWindowDelegate)?
    var shouldAllowWindowClose: ((NSWindow) -> Bool)?
    private var shouldBypassNextClose = false

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if originalDelegate?.responds(to: aSelector) == true {
            return originalDelegate
        }

        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if shouldBypassNextClose {
            shouldBypassNextClose = false
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        guard shouldAllowWindowClose?(sender) ?? true else {
            return false
        }

        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    func performDeferredWindowClose(for window: NSWindow) {
        shouldBypassNextClose = true
        DispatchQueue.main.async {
            window.performClose(nil)
            if window.isVisible {
                window.close()
            }
        }
    }

    func reset() {
        originalDelegate = nil
        shouldAllowWindowClose = nil
        shouldBypassNextClose = false
    }
}
