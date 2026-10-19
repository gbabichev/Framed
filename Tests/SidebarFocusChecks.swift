import AppKit

private final class Rows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 4 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { "Row \(row)" }
}

@main struct SidebarFocusChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = content
        let rows = Rows()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("screenshots")))
        table.dataSource = rows
        table.allowsMultipleSelection = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        scroll.documentView = table
        content.addSubview(scroll)
        table.reloadData()
        table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        let bridge = SidebarFocusRecoveryView(frame: scroll.frame)
        content.addSubview(bridge, positioned: .below, relativeTo: scroll)
        let headline = NSTextField(frame: NSRect(x: 320, y: 400, width: 200, height: 24))
        content.addSubview(headline)
        precondition(window.makeFirstResponder(headline))
        precondition(bridge.restoreListFocus(at: NSPoint(x: 80, y: 200)))
        precondition(window.firstResponder === table, "A sidebar click must make the native table first responder")
        precondition(table.selectedRowIndexes == IndexSet([0, 2]), "Focus recovery must preserve multi-selection")
        precondition(bridge.restoreListFocus(at: NSPoint(x: 80, y: 200)), "Already-focused sidebar must remain stable")
        precondition(window.makeFirstResponder(headline))
        let inspectorResponder = window.firstResponder
        precondition(!bridge.restoreListFocus(at: NSPoint(x: 380, y: 410)))
        precondition(window.firstResponder === inspectorResponder, "Inspector clicks must keep their keyboard focus")
        precondition(bridge.hitTest(NSPoint(x: 30, y: 30)) == nil, "The bridge must never intercept clicks or drags")
        scroll.isHidden = true
        precondition(!bridge.restoreListFocus(at: NSPoint(x: 80, y: 200)), "Hidden lists must not receive focus")
        bridge.stopMonitoring()
        print("PASS: native sidebar responder recovery, preserved multi-selection, inspector isolation, hidden-list guard and non-intercepting hit testing")
    }
}
