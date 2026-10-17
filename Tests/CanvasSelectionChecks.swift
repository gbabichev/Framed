import AppKit

@main struct CanvasSelectionChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasSelection-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        let original = ProjectSettings(model.settings)
        func makeFrame(_ name: String, width: Int, height: Int) throws -> SavedFrame {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.clear(CGRect(x: 10, y: 10, width: width - 20, height: height - 20))
            return try library.store(ImportedImage(id: UUID(), name: name, image: context.makeImage()!))
        }
        let mac = try makeFrame("MacBook Pro 16-inch", width: 366, height: 243)
        precondition(model.useLibraryFrame(mac))
        precondition(model.settings.preset.name == "Mac" && model.settings.landscape,
                     "Selecting a Mac frame must immediately set a landscape Mac canvas")
        let macSettings = ProjectSettings(model.settings)
        model.undo()
        precondition(model.selectedMockupID == nil && ProjectSettings(model.settings) == original,
                     "Undo must restore frame and canvas together")
        model.redo()
        precondition(ProjectSettings(model.settings) == macSettings)
        // A first screenshot with exact iPad dimensions must inherit the chosen Mac frame's canvas.
        let context = CGContext(data: nil, width: 2048, height: 2732, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let path = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: path)
        model.load([path], asMockups: false)
        precondition(model.settings.preset.name == "Mac", "Import must retain an existing frame canvas")
        let first = model.selectedScreenshotID!
        let ipad = try makeFrame("iPad Pro Portrait", width: 220, height: 286)
        precondition(model.useLibraryFrame(ipad))
        precondition(model.settings.preset.name.hasPrefix("iPad") && !model.settings.landscape)
        let shot = ImportedImage(id: UUID(), name: "Second", image: context.makeImage()!)
        model.screenshots.append(shot); model.selectedScreenshotID = shot.id
        precondition(model.useLibraryFrame(mac))
        precondition(model.settings.preset.name == "Mac")
        model.selectedScreenshotID = first
        precondition(model.settings.preset.name.hasPrefix("iPad"), "Frame selection must affect only the active layout")
        model.settings.preset = ScreenshotPreset.all[0]
        precondition(model.settings.preset == ScreenshotPreset.all[0], "Manual canvas overrides must remain available")
        print("PASS: frame selection matches canvas, undo/redo, import inheritance, per-screenshot isolation, manual override")
    }
}
