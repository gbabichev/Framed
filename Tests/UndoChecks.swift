import AppKit

@main struct UndoChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UndoChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        precondition(!model.canUndo && !model.canRedo && !model.isDirty)
        model.isMovingDesktopWindow = true
        precondition(!model.canUndo && !model.isDirty, "Window move tool must not edit the project")
        model.beginEditing("Move Window")
        for index in 1...10 {
            model.settings.desktop.windowX = Double(index) / 10
            model.settings.desktop.windowY = Double(index) / 10
        }
        model.endEditing()
        model.undo()
        precondition(model.settings.desktop.windowX == 0.5 && model.settings.desktop.windowY == 0.5
                     && !model.isDirty && !model.canUndo,
                     "A window drag must undo both coordinates in one step")
        precondition(model.isMovingDesktopWindow, "Undo must preserve the active editing tool")
        model.isMovingDesktopWindow = false
        model.settings.deviceX = 0.3
        precondition(model.canUndo && model.isDirty)
        model.undo()
        precondition(!model.canUndo && model.canRedo && !model.isDirty && model.settings.deviceX == 0.5)
        model.redo()
        precondition(model.settings.deviceX == 0.3 && model.isDirty)
        model.undo()
        model.beginEditing("Move Device")
        for index in 1...100 { model.settings.deviceX = Double(index) / 100; model.settings.deviceY = Double(index) / 100 }
        model.endEditing()
        precondition(model.settings.deviceX == 1)
        model.undo()
        precondition(model.settings.deviceX == 0.5 && model.settings.deviceY == 0.5 && !model.canUndo,
                     "A drag must undo both coordinates in one step")
        precondition(model.canRedo)
        model.settings.deviceScale = 0.75
        precondition(!model.canRedo, "An edit after undo must discard redo")
        model.undo()
        for index in 1...25 { model.settings.deviceX = Double(index) / 100 }
        var undoCount = 0
        while model.canUndo { model.undo(); undoCount += 1 }
        precondition(undoCount == 20 && abs(model.settings.deviceX - 0.05) < 0.0001, "History must retain exactly 20 edits")
        while model.canRedo { model.redo() }
        let context = CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        let screenshot = root.appendingPathComponent("Screenshot.png")
        try ProjectImage(ImportedImage(id: UUID(), name: "Shot", image: context.makeImage()!)).png.write(to: screenshot)
        model.load([screenshot, screenshot], asMockups: false)
        let ids = model.screenshots.map(\.id)
        precondition(ids.count == 2)
        model.undo(); precondition(model.screenshots.isEmpty)
        model.redo(); precondition(model.screenshots.map(\.id) == ids)
        let saved = root.appendingPathComponent("Project.framed")
        precondition(model.writeProject(to: saved))
        model.selectedScreenshotID = ids[0]
        precondition(!model.isDirty)
        model.settings.headline.firstLine = "Hello"
        model.settings.headline.firstLine = "Hello world"
        model.undo()
        precondition(model.settings.headline.firstLine == "Your headline" && !model.isDirty, "Typing should coalesce and return to the saved state")
        model.redo(); precondition(model.settings.headline.firstLine == "Hello world")
        model.duplicateScreenshot(ids[0])
        let duplicate = model.selectedScreenshotID!
        model.undo(); precondition(model.screenshots.count == 2 && model.selectedScreenshotID == ids[0])
        model.redo(); precondition(model.screenshots.count == 3 && model.selectedScreenshotID == duplicate)
        let order = model.screenshots.map(\.id)
        model.moveScreenshots(from: IndexSet(integer: 0), to: 3)
        model.undo(); precondition(model.screenshots.map(\.id) == order)
        model.redo(); precondition(model.screenshots.last?.id == ids[0])
        model.removeScreenshot(duplicate)
        model.undo(); precondition(model.screenshots.contains { $0.id == duplicate })
        model.redo(); precondition(!model.screenshots.contains { $0.id == duplicate })
        model.selectedScreenshotID = ids[0]
        model.settings.deviceX = 0.2
        model.copyStyle(from: ids[0])
        let beforeAll = model.fingerprint
        model.applyStyleToAll(from: ids[0])
        model.undo(); precondition(model.fingerprint == beforeAll, "Apply all must be one undo step")
        context.clear(CGRect(x: 10, y: 10, width: 80, height: 180))
        let frame = try library.store(ImportedImage(id: UUID(), name: "Frame", image: context.makeImage()!))
        let beforeFrame = model.fingerprint
        precondition(model.useLibraryFrame(frame))
        let applied = model.fingerprint
        model.copyStyle(from: ids[0])
        model.undo(); precondition(model.fingerprint == beforeFrame && model.selectedMockup == nil)
        model.pasteStyle(to: ids[0])
        precondition(model.selectedMockup != nil && model.opening != nil, "Copied style lost its frame when frame application was undone")
        model.undo(); precondition(model.fingerprint == beforeFrame)
        model.redo(); precondition(model.fingerprint == applied && model.opening != nil)
        // Save establishes a dirty-state boundary without throwing away undo/redo.
        precondition(model.writeProject(to: saved))
        model.settings.deviceY = 0.7
        model.undo(); precondition(!model.isDirty)
        model.undo(); precondition(model.isDirty)
        model.redo(); precondition(!model.isDirty)
        model.isBusy = true; let busyBaseline = model.fingerprint
        model.undo(); precondition(!model.canUndo && model.fingerprint == busyBaseline)
        model.isBusy = false
        let project = try FramedProject.read(from: saved)
        try model.restoreProject(project, at: saved)
        precondition(!model.canUndo && !model.canRedo && !model.isDirty, "Opening a project must reset history")
        _ = try library.store(ImportedImage(id: UUID(), name: "Frame", image: context.makeImage()!))
        precondition(!model.canUndo && !model.isDirty, "Global library edits must not enter project history")
        model.releaseProjectAccess()
        print("PASS: 20-step cap, grouped drag/import/frame/style edits, typing coalescing, undo/redo branching, screenshot identity/order, saved-state tracking, busy guards, open reset, and library isolation")
    }
}
