import AppKit
import ImageIO

@main
struct ProjectChecks {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FramedProjectChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("Roundtrip.framed")
        let source = directory.appendingPathComponent("source.png")
        let context = CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        context.clear(CGRect(x: 10, y: 15, width: 80, height: 170))
        let image = context.makeImage()!
        let imported = ImportedImage(id: UUID(), name: "Embedded frame", image: image)
        try ProjectImage(imported).png.write(to: source)
        let library = FrameLibrary(directory: directory.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        precondition(!model.isDirty, "New empty project must be clean")
        model.load([source], asMockups: false)
        let beforeFrameImport = model.fingerprint
        model.load([source], asMockups: true)
        precondition(model.fingerprint == beforeFrameImport, "Frame import changed project")
        precondition(model.useLibraryFrame(library.frames[0]))
        precondition(model.isDirty, "Import must dirty project")
        model.settings.preset = ScreenshotPreset.all[6]
        model.settings.landscape = true
        model.settings.deviceScale = 0.77
        model.settings.background = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        model.settings.fillScreen = true
        model.settings.manualScreen = true
        model.settings.screenX = 0.12; model.settings.screenY = 0.13
        model.settings.screenWidth = 0.71; model.settings.screenHeight = 0.72
        model.settings.cornerRadius = 0.15
        model.settings.transparentBackground = true
        model.settings.effects.cornerGlow = true
        model.settings.effects.glowCorner = .bottomRight
        model.settings.effects.glowStrength = 0.42
        model.settings.effects.deviceFade = true
        model.settings.effects.fadeEdge = .top
        model.settings.effects.fadeDepth = 0.27
        model.settings.headline.enabled = true
        model.settings.headline.firstLine = "Saved headline"
        model.settings.headline.secondLine = "Second line"
        model.settings.headline.fontFamily = "Helvetica"
        model.settings.headline.weight = .medium
        model.settings.headline.x = 0.38; model.settings.headline.y = 0.22
        model.settings.headline.size = 0.07
        model.settings.headline.color = .blue
        model.jpeg = true
        let expected = model.fingerprint
        let selected = model.selectedScreenshotID
        precondition(model.writeProject(to: path), "Project save failed")
        precondition(!model.isDirty && model.projectURL == path, "Save must establish clean baseline and URL")
        try FileManager.default.removeItem(at: source)
        let reopened = EditorModel(frameLibrary: library)
        try reopened.restoreProject(FramedProject.read(from: path), at: path)
        precondition(reopened.fingerprint == expected, "Roundtrip lost project settings or image identity")
        precondition(reopened.selectedScreenshotID == selected && !reopened.isDirty, "Selection/baseline not restored")
        precondition(reopened.opening != nil, "Mockup mask not rebuilt")
        let png = try ProjectImage(reopened.mockups[0]).png
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
        precondition(decoded.width == 100 && decoded.height == 200, "Embedded image dimensions changed")
        precondition(NSBitmapImageRep(cgImage: decoded).colorAt(x: 50, y: 50)!.alphaComponent == 0, "Mockup transparency lost")
        precondition(reopened.settings.transparentBackground, "Transparency not restored")
        reopened.settings.transparentBackground = false
        precondition(reopened.isDirty, "Background changes must dirty project")
        reopened.settings.transparentBackground = true
        precondition(!reopened.isDirty, "Restoring saved background must clear dirty state")
        reopened.settings.effects.cornerGlow = false
        precondition(reopened.isDirty, "Effect changes must dirty project")
        reopened.settings.effects.cornerGlow = true
        precondition(!reopened.isDirty, "Restoring saved effects must clear dirty state")
        reopened.settings.headline.x = 0.6
        precondition(reopened.isDirty, "Moving headline must dirty project")
        reopened.settings.headline.x = 0.38
        precondition(!reopened.isDirty, "Restoring saved headline position must clear dirty state")
        reopened.status = "Transient status"; reopened.error = "Transient error"
        precondition(!reopened.isDirty, "Status/error must not dirty project")
        reopened.selectedScreenshotID = nil
        precondition(!reopened.isDirty, "Browsing selection must not dirty canvas")
        reopened.settings.deviceScale = 0.81
        precondition(reopened.isDirty, "Layout edit must dirty project")
        reopened.settings.deviceScale = 0.77
        precondition(!reopened.isDirty, "Returning to saved state must clear dirty indicator")
        reopened.jpeg = false
        precondition(reopened.isDirty, "Export format edit must be retained")
        let missingParent = directory.appendingPathComponent("missing/fail.framed")
        precondition(!reopened.writeProject(to: missingParent) && reopened.isDirty, "Failed save must preserve dirty state")
        precondition(reopened.projectURL == path, "Failed save changed project URL")
        var invalid = try FramedProject.read(from: path)
        invalid.settings.screenWidth = 4
        do { try reopened.restoreProject(invalid, at: path); fatalError("Invalid settings accepted") }
        catch is FramedError { }
        precondition(reopened.isDirty && reopened.jpeg == false, "Failed open changed current canvas")
        invalid = try FramedProject.read(from: path)
        invalid.version = 200
        do { try reopened.restoreProject(invalid, at: path); fatalError("Future version accepted") }
        catch is FramedError { }
        let baseline = reopened.fingerprint
        invalid = try FramedProject.read(from: path)
        invalid.mockups[0].png = Data("broken".utf8)
        do { try reopened.restoreProject(invalid, at: path); fatalError("Corrupt embedded asset accepted") }
        catch is FramedError { }
        precondition(reopened.fingerprint == baseline, "Corrupt project changed current canvas")
        model.releaseProjectAccess(); reopened.releaseProjectAccess()
        print("PASS: portable project roundtrip, all settings and selection, embedded alpha, rebuilt masks, dirty tracking, failed save/open preservation, future/corrupt file rejection")
    }
}
