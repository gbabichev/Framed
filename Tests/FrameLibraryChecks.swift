import AppKit

@main
struct FrameLibraryChecks {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FrameLibraryChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Frames")
        let source = root.appendingPathComponent("Source.png")
        let context = CGContext(data: nil, width: 500, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 480, height: 780))
        context.clear(CGRect(x: 30, y: 40, width: 440, height: 720))
        let imported = ImportedImage(id: UUID(), name: "Test phone", image: context.makeImage()!)
        try ProjectImage(imported).png.write(to: source)
        let library = FrameLibrary(directory: directory)
        precondition(library.frames.isEmpty)
        let first = try library.store(ImportedImage(url: source))
        precondition(first.thumbnail.width <= 320 && first.thumbnail.height <= 320, "Unbounded thumbnail")
        let duplicate = try library.store(ImportedImage(url: source))
        precondition(duplicate.id == first.id && library.frames.count == 1, "Repeated import duplicated frame")
        try FileManager.default.removeItem(at: source)
        let relaunched = FrameLibrary(directory: directory)
        precondition(relaunched.frames.count == 1 && relaunched.frames[0].id == first.id, "Library not persisted")
        let restored = try relaunched.image(for: first)
        precondition(restored.image.width == 500 && restored.image.height == 800, "Stored asset changed dimensions")
        precondition(NSBitmapImageRep(cgImage: restored.image).colorAt(x: 250, y: 400)!.alphaComponent == 0, "Lost screen transparency")
        let model = EditorModel(frameLibrary: relaunched)
        precondition(!model.isDirty && model.mockups.isEmpty, "Browsing a library dirtied an empty project")
        precondition(model.useLibraryFrame(first) && model.isDirty, "Choosing a frame did not affect canvas")
        model.settings.manualScreen = true
        model.settings.screenX = 0.12
        precondition(model.useLibraryFrame(first) && model.settings.manualScreen && model.settings.screenX == 0.12,
                     "Reselecting same frame lost calibration")
        let projectURL = root.appendingPathComponent("Portable.framed")
        precondition(model.writeProject(to: projectURL))
        try relaunched.rename(first, to: "Renamed phone")
        precondition(!model.isDirty && model.selectedFrameDisplayName == "Renamed phone", "Library rename changed canvas or failed to update display name")
        let afterRename = FrameLibrary(directory: directory)
        precondition(afterRename.frames[0].name == "Renamed phone" && afterRename.frames[0].id == first.id, "Rename not persisted")
        let reopened = EditorModel(frameLibrary: afterRename)
        try reopened.restoreProject(FramedProject.read(from: projectURL), at: projectURL)
        precondition(!reopened.isDirty && reopened.selectedLibraryFrameID == first.id, "Project did not match reusable copy")
        try afterRename.remove(afterRename.frames[0])
        precondition(afterRename.frames.isEmpty && !reopened.isDirty && reopened.selectedMockup != nil, "Library removal damaged current project")
        precondition(FrameLibrary(directory: directory).frames.isEmpty, "Removal not persisted")
        let portable = EditorModel(frameLibrary: afterRename)
        try portable.restoreProject(FramedProject.read(from: projectURL), at: projectURL)
        precondition(portable.selectedMockup != nil && portable.opening != nil && afterRename.frames.isEmpty,
                     "Project depended on removed library asset or silently resurrected it")
        portable.saveSelectedFrameToLibrary()
        precondition(afterRename.frames.count == 1 && !portable.isDirty && portable.selectedFrameIsInLibrary,
                     "Adding embedded frame to library changed canvas")
        let frame = afterRename.frames[0]
        let assetURL = directory.appendingPathComponent(frame.id.uuidString).appendingPathComponent("frame.png")
        try Data("broken".utf8).write(to: assetURL)
        do { _ = try afterRename.image(for: frame); fatalError("Corrupt stored PNG accepted") }
        catch is FramedError { }
        _ = try afterRename.store(portable.selectedMockup!)
        _ = try afterRename.image(for: frame)
        let badFolder = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: false)
        try Data("broken".utf8).write(to: badFolder.appendingPathComponent("metadata.json"))
        afterRename.reload()
        precondition(afterRename.frames.count == 1 && afterRename.error != nil, "Corrupt entry hid healthy entries or failed silently")
        let blocked = root.appendingPathComponent("Blocked")
        try Data().write(to: blocked)
        let failing = FrameLibrary(directory: blocked)
        do { _ = try failing.store(imported); fatalError("Import into unwritable library succeeded") }
        catch { precondition(failing.frames.isEmpty, "Failed import published an entry") }
        model.releaseProjectAccess(); reopened.releaseProjectAccess(); portable.releaseProjectAccess()
        print("PASS: durable frame copies and previews, deduplication, rename/remove, portable projects, calibration preservation, dirty isolation, corruption repair and failed imports")
    }
}
