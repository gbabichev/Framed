import AppKit

@main struct MultiSelectionChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MultiSelectionChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = EditorModel(frameLibrary: FrameLibrary(directory: root.appendingPathComponent("Frames")))
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: url)
        model.addDeviceSection(.iPhone)
        let phone = model.activeSection!.id
        model.load([url, url, url, url], asMockups: false)
        let ids = model.screenshots.map(\.id)
        model.addDeviceSection(.mac)
        let mac = model.activeSection!.id
        let before = model.fingerprint
        model.sidebarSelections = Set(ids.prefix(3).map(SidebarSelection.screenshot))
        precondition(model.sidebarSelections.count == 3 && model.fingerprint == before,
                     "Multi-selection must not edit the project")
        let oldSelection = model.sidebarSelections
        precondition(model.screenshotIDsToMove(startingAt: ids[1]) == Array(ids.prefix(3)))
        let provider = model.screenshotDragProvider(for: ids[1])
        precondition(model.handleSidebarDrop([provider], sectionID: mac))
        for _ in 0..<300 {
            if model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.count == 3 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.map(\.id) == Array(ids.prefix(3)),
                     "Batch drops must preserve visible screenshot order")
        precondition(model.sidebarGroups.first(where: { $0.id == phone })!.screenshots.map(\.id) == [ids[3]])
        precondition(model.sidebarSelections == oldSelection && model.activeSection?.id == mac)
        model.undo()
        precondition(model.fingerprint == before && model.sidebarSelections == oldSelection,
                     "One undo must restore all moved screenshots and their selection")
        model.redo()
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.count == 3)
        model.moveScreenshots(Set(ids.prefix(2)), toSection: mac, at: 3)
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.map(\.id) == [ids[2], ids[0], ids[1]],
                     "Reordering a selected block must account for its removed source indices")
        model.sidebarSelections = [.screenshot(ids[0]), .screenshot(ids[2])]
        precondition(model.screenshotIDsToMove(startingAt: ids[1]) == [ids[1]],
                     "Dragging an unselected row must only move that row")
        _ = model.screenshotDragProvider(for: ids[1])
        precondition(model.sidebarSelections == [.screenshot(ids[1])])
        model.selectDeviceSection(phone)
        precondition(model.sidebarSelections == [.device(phone)] && model.selectedScreenshot == nil,
                     "Default layout selection must exit screenshot multi-selection")
        model.sidebarSelections = [.screenshot(ids[0]), .screenshot(ids[1])]
        model.removeScreenshot(ids[0])
        precondition(model.sidebarSelections == [.screenshot(ids[1])], "Deleting one row must preserve other selected rows")
        model.undo()
        model.sidebarSelections = [.screenshot(ids[0]), .screenshot(ids[3])]
        let selectedBeforeRemoval = model.sidebarSelections
        let loadedBeforeRemoval = model.selectedScreenshotID
        let beforeRemoval = model.fingerprint
        model.removeScreenshotsFromContext(for: ids[0])
        precondition(!model.screenshots.contains { $0.id == ids[0] || $0.id == ids[3] },
                     "Context removal must delete the full selection across device sections")
        precondition(model.selectedScreenshotID == nil && model.sidebarSelections == [.device(phone)],
                     "An emptied section must fall back to its default layout")
        model.undo()
        precondition(model.fingerprint == beforeRemoval && model.sidebarSelections == selectedBeforeRemoval
                     && model.selectedScreenshotID == loadedBeforeRemoval,
                     "One undo must restore all deleted screenshots, layouts, memberships and selection")
        model.redo()
        precondition(model.screenshots.count == 2)
        model.undo()
        model.removeScreenshotsFromContext(for: ids[1])
        precondition(!model.screenshots.contains { $0.id == ids[1] }
                     && model.screenshots.contains { $0.id == ids[0] }
                     && model.screenshots.contains { $0.id == ids[3] }
                     && model.sidebarSelections == selectedBeforeRemoval,
                     "Context removal of an unselected row must leave the selected group intact")
        model.undo()
        model.sidebarSelections = Set(ids.map(SidebarSelection.screenshot))
        model.removeScreenshotsFromContext(for: ids[2])
        precondition(model.screenshots.isEmpty && model.selectedScreenshotID == nil
                     && model.deviceSections.count == 2,
                     "Removing every screenshot must keep the device sections and clear the loaded image")
        model.undo()
        precondition(model.screenshots.count == 4 && model.sidebarSelections.count == 4)
        print("PASS: clean multi-selection, grouped payloads, cross-device ordering, selection preservation, undo/redo, block reordering, unselected drags, default-layout selection, batch context removal and deletion undo/redo")
    }
}
