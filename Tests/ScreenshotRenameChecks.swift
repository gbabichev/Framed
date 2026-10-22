import AppKit

@main struct ScreenshotRenameChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotRenameChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes = try CompositionRenderer.encode(context.makeImage()!, jpeg: false)
        let source = root.appendingPathComponent("Original screenshot.png")
        try bytes.write(to: source)
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        model.load([source, source], asMockups: false)
        let original = model.screenshots[0]
        let other = model.screenshots[1]
        let layout = ProjectSettings(model.layout(for: original.id).settings)
        model.sidebarSelections = [.screenshot(original.id), .screenshot(other.id)]
        let selection = model.sidebarSelections
        let loaded = model.selectedScreenshotID
        let project = root.appendingPathComponent("Renames.framed")
        precondition(model.writeProject(to: project))
        let saved = model.fingerprint
        model.renameScreenshot(original.id, to: "  Features Overview  ")
        let renamed = model.screenshots[0]
        precondition(renamed.name == "Features Overview" && renamed.id == original.id && renamed != original)
        precondition(renamed.image === original.image && renamed.sourceData == original.sourceData
                     && renamed.sourceFilename == original.sourceFilename)
        precondition(model.screenshots[1].name == other.name && model.sidebarSelections == selection
                     && model.selectedScreenshotID == loaded && ProjectSettings(model.layout(for: original.id).settings) == layout)
        precondition(model.isDirty)
        model.undo()
        precondition(model.screenshots[0].name == original.name && model.fingerprint == saved && !model.isDirty)
        model.redo()
        precondition(model.screenshots[0].name == "Features Overview" && model.isDirty)
        model.renameScreenshot(original.id, to: "Features Overview")
        model.renameScreenshot(original.id, to: "   \n  ")
        model.renameScreenshot(UUID(), to: "Unknown")
        model.undo()
        precondition(!model.isDirty, "Blank, missing and unchanged names must not add undo entries")
        model.redo()
        precondition(model.writeProject(to: project))
        let reopened = EditorModel(frameLibrary: library)
        try reopened.restoreProject(FramedProject.read(from: project), at: project)
        precondition(reopened.fingerprint == model.fingerprint && !reopened.isDirty)
        precondition(reopened.screenshots[0].name == "Features Overview"
                     && reopened.screenshots[0].sourceFilename == source.lastPathComponent)
        let export = ExportWorker.availableURL(in: root, name: reopened.screenshots[0].name, extension: "png")
        precondition(export.lastPathComponent == "Features Overview.png")
        reopened.renameScreenshot(original.id, to: "../Screenshots:Example\\Name\nTest")
        precondition(!reopened.screenshots[0].name.contains("/") && !reopened.screenshots[0].name.contains(":")
                     && !reopened.screenshots[0].name.contains("\\") && !reopened.screenshots[0].name.contains("\n"))
        reopened.renameScreenshot(original.id, to: String(repeating: "📷", count: 100))
        precondition(reopened.screenshots[0].name.utf8.count <= 180)
        let unchangedSource = try Data(contentsOf: source)
        precondition(unchangedSource == bytes)
        model.releaseProjectAccess(); reopened.releaseProjectAccess()
        print("PASS: rename, immediate metadata changes, original bytes/name preservation, multi-selection, layout isolation, dirty tracking, undo/redo, no-op names, persistence, export names and safe filename bounds")
    }
}
