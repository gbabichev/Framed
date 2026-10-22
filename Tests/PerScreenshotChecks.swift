import AppKit

@main
struct PerScreenshotChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PerScreenshot-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        let image = context.makeImage()!
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        let fixture = root.appendingPathComponent("Fixture.png")
        try CompositionRenderer.encode(image, jpeg: false).write(to: fixture)
        model.load([fixture, fixture, fixture], asMockups: false)
        let a = model.screenshots[0], b = model.screenshots[1], c = model.screenshots[2]
        model.selectedScreenshotID = a.id
        model.settings.headline.enabled = true; model.settings.headline.firstLine = "Alpha"
        model.settings.deviceX = 0.25
        context.clear(CGRect(x: 10, y: 10, width: 80, height: 180))
        let frame = try library.store(ImportedImage(id: UUID(), name: "Frame", image: context.makeImage()!))
        precondition(model.useLibraryFrame(frame))
        let frameID = model.selectedMockupID
        model.selectedScreenshotID = b.id
        precondition(model.settings.deviceX == 0.5 && model.selectedMockupID == nil, "Selection leaked another screenshot's layout")
        model.settings.headline.firstLine = "Bravo"; model.settings.deviceY = 0.65
        model.copyStyle(from: a.id); model.pasteStyle(to: b.id)
        precondition(model.settings.deviceX == 0.25 && model.settings.headline.firstLine == "Bravo" && model.selectedMockupID == frameID)
        model.selectedScreenshotID = a.id
        precondition(model.settings.headline.firstLine == "Alpha")
        model.duplicateScreenshot(a.id)
        let duplicate = model.selectedScreenshotID!
        precondition(duplicate != a.id && model.settings.headline.firstLine == "Alpha" && model.selectedMockupID == frameID)
        model.settings.headline.firstLine = "Duplicate"
        model.selectedScreenshotID = a.id
        precondition(model.settings.headline.firstLine == "Alpha", "Duplicate shared mutable layout")
        model.moveScreenshots(from: IndexSet(integer: 0), to: 4)
        precondition(model.screenshots.map(\.id) == [duplicate, b.id, c.id, a.id])
        model.moveScreenshot(a.id, by: -1)
        precondition(model.screenshots.map(\.id) == [duplicate, b.id, a.id, c.id])
        model.moveScreenshot(a.id, by: 1)
        precondition(model.screenshots.map(\.id) == [duplicate, b.id, c.id, a.id])
        let path = root.appendingPathComponent("Set.framed")
        precondition(model.writeProject(to: path))
        let fingerprint = model.fingerprint
        let frameImage = model.mockups.first { $0.id == frameID }!.image
        let thumbnail = try CompositionRenderer.deviceThumbnail(screenshot: image, mockup: frameImage,
                                                                opening: model.screenOpening(for: frameID), settings: model.settings)
        precondition(thumbnail.width == 44 && thumbnail.height == 88, "Thumbnail must fit the complete frame within 88 pixels")
        let pixels = thumbnail.dataProvider!.data! as Data
        precondition(pixels[(thumbnail.height / 2) * thumbnail.bytesPerRow + (thumbnail.width / 2) * 4 + 3] == 255,
                     "The thumbnail's transparent screen must contain the screenshot")
        var moved = model.settings
        moved.deviceX = 0.9; moved.deviceY = 0.1; moved.deviceScale = 0.4
        let movedThumbnail = try CompositionRenderer.deviceThumbnail(screenshot: image, mockup: frameImage,
                                                                     opening: model.screenOpening(for: frameID), settings: moved)
        let thumbnailPNG = try CompositionRenderer.encode(thumbnail, jpeg: false)
        let movedPNG = try CompositionRenderer.encode(movedThumbnail, jpeg: false)
        precondition(thumbnailPNG == movedPNG,
                     "Canvas placement must not crop or shrink the sidebar device")
        precondition(!model.isDirty, "Rendering thumbnails must not dirty a project")
        model.copyStyle(from: a.id)
        precondition(!model.isDirty, "Copying style must not change the project")
        model.selectedScreenshotID = b.id; model.selectedScreenshotID = c.id
        precondition(!model.isDirty && model.fingerprint == fingerprint, "Browsing must not dirty project")
        model.applyStyleToAll(from: a.id)
        precondition(model.isDirty && model.settings.deviceX == 0.25)
        model.selectedScreenshotID = b.id
        precondition(model.settings.headline.firstLine == "Bravo", "Apply all overwrote headline text")
        let reopened = EditorModel(frameLibrary: library)
        let savedProject = try FramedProject.read(from: path)
        try reopened.restoreProject(savedProject, at: path)
        precondition(!reopened.isDirty && !reopened.deviceSections.isEmpty,
                     "Legacy projects must open clean with inferred device sections")
        for record in savedProject.layouts! {
            let layout = reopened.layout(for: record.screenshotID)
            precondition(ProjectSettings(layout.settings) == record.settings && layout.mockupID == record.mockupID,
                         "Migration must preserve every saved screenshot layout")
        }
        reopened.selectedScreenshotID = b.id
        precondition(reopened.settings.headline.firstLine == "Bravo" && reopened.selectedMockupID == frameID)
        reopened.selectedScreenshotID = c.id
        precondition(reopened.selectedMockupID == nil, "No-frame layout inherited the selected frame")
        let legacySettings = ProjectSettings(model.layout(for: a.id).settings)
        var legacy = try model.makeProject()
        legacy.version = 1; legacy.layouts = nil; legacy.settings = legacySettings; legacy.selectedMockupID = frameID
        let migrated = EditorModel(frameLibrary: library)
        try migrated.restoreProject(legacy, at: root.appendingPathComponent("Legacy.framed"))
        for shot in migrated.screenshots {
            migrated.selectedScreenshotID = shot.id
            precondition(ProjectSettings(migrated.settings) == legacySettings && migrated.selectedMockupID == frameID)
        }
        let migratedProject = try migrated.makeProject()
        precondition(!migrated.isDirty && migratedProject.version == 4)
        var invalid = try model.makeProject()
        invalid.layouts!.removeLast()
        let before = reopened.fingerprint
        do { try reopened.restoreProject(invalid, at: path); fatalError("Missing layout accepted") } catch is FramedError { }
        precondition(reopened.fingerprint == before)
        let sourceURL = root.appendingPathComponent("New screenshot.png")
        try CompositionRenderer.encode(image, jpeg: false).write(to: sourceURL)
        model.selectedScreenshotID = a.id
        model.useScreenshotAsDefault(a.id)
        let inherited = ProjectSettings(model.settings)
        model.load([sourceURL], asMockups: false)
        precondition(ProjectSettings(model.settings) == inherited && model.selectedMockupID == frameID,
                     "Imported screenshots must inherit the active device default layout")
        model.settings.deviceX = 0.75
        precondition(model.layout(for: a.id).settings.deviceX == 0.25)
        model.releaseProjectAccess(); reopened.releaseProjectAccess(); migrated.releaseProjectAccess()
        print("PASS: individual settings/frames, selection cleanliness, duplicate isolation, style/text preservation, ordering, roundtrip, v1 migration and invalid layout rejection")
    }
}
