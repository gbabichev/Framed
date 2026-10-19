import AppKit
import SwiftUI

/// Keep the native List's selection highlight and keyboard focus in sync after
/// clicks handled by SwiftUI row gestures, header buttons, and drop targets.
struct SidebarFocusRecovery: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarFocusRecoveryView { SidebarFocusRecoveryView() }
    func updateNSView(_ view: SidebarFocusRecoveryView, context: Context) { }
    static func dismantleNSView(_ view: SidebarFocusRecoveryView, coordinator: ()) { view.stopMonitoring() }
}

final class SidebarFocusRecoveryView: NSView {
    private var mouseMonitor: Any?

    // This is a background observer, never a click-catching overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            let point = event.locationInWindow
            // Let native selection, modifier keys, and SwiftUI button actions run
            // first. Only then repair the responder, without selecting any rows.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      window.isKeyWindow, window.attachedSheet == nil else { return }
                self.restoreListFocus(at: point)
            }
            return event
        }
    }

    @discardableResult
    func restoreListFocus(at windowPoint: NSPoint) -> Bool {
        guard let window, window.attachedSheet == nil,
              bounds.contains(convert(windowPoint, from: nil)), let content = window.contentView,
              let table = Self.list(at: windowPoint, in: content) else { return false }
        if window.firstResponder === table { return true }
        return window.makeFirstResponder(table)
    }

    private static func list(at point: NSPoint, in view: NSView) -> NSTableView? {
        guard !view.isHiddenOrHasHiddenAncestor else { return nil }
        if let table = view as? NSTableView, table.acceptsFirstResponder,
           let scroll = table.enclosingScrollView,
           scroll.bounds.contains(scroll.convert(point, from: nil)) {
            return table
        }
        for child in view.subviews {
            if let table = list(at: point, in: child) { return table }
        }
        return nil
    }

    func stopMonitoring() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    deinit { MainActor.assumeIsolated { stopMonitoring() } }
}
