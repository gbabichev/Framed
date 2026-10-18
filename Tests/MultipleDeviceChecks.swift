import AppKit

@main struct MultipleDeviceChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MultipleDeviceChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        model.addDeviceSection(.iPad)
        let portrait = model.activeSection!.id
        model.renameDeviceSection(portrait, to: "iPad Portrait")
        model.settings.headline.firstLine = "Portrait headline"
        model.duplicateDeviceLayout(portrait)
        let landscape = model.activeSection!.id
        model.renameDeviceSection(landscape, to: "iPad Landscape")
        model.settings.landscape = true
        precondition(model.settings.headline.firstLine == "Portrait headline")
        model.settings.headline.firstLine = "Landscape headline"
        model.selectDeviceSection(portrait)
        precondition(!model.settings.landscape && model.settings.headline.firstLine == "Portrait headline",
                     "Same-class section defaults must remain independent")
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: url)
        model.load([url], asMockups: false)
        let a = model.selectedScreenshotID!
        model.selectDeviceSection(landscape)
        model.load([url], asMockups: false)
        let b = model.selectedScreenshotID!
        precondition(model.settings.landscape && !model.layout(for: a).settings.landscape)
        let path = root.appendingPathComponent("Multiple.framed")
        precondition(model.writeProject(to: path))
        let restored = EditorModel(frameLibrary: library)
        try restored.restoreProject(FramedProject.read(from: path), at: path)
        precondition(restored.deviceSections.map(\.title) == ["iPad Portrait", "iPad Landscape"])
        precondition(restored.sidebarGroups[0].screenshots.map(\.id) == [a]
                     && restored.sidebarGroups[1].screenshots.map(\.id) == [b],
                     "Save/open must not merge sections of the same device class")
        precondition(restored.fingerprint == model.fingerprint && !restored.isDirty)
        restored.renameDeviceSection(landscape, to: "Marketing Landscape")
        precondition(restored.isDirty)
        restored.undo()
        precondition(!restored.isDirty && restored.deviceSections[1].title == "iPad Landscape")
        restored.addDeviceSection(.iPad)
        restored.addDeviceSection(.iPad)
        precondition(Set(restored.deviceSections.map(\.title)).count == 4)
        restored.renameDeviceSection(portrait, to: "iPad/Scene")
        restored.renameDeviceSection(landscape, to: "iPad:Scene")
        let folders = restored.deviceExportFolderNames
        precondition(folders[portrait] == "iPad-Scene" && folders[landscape] == "iPad-Scene 2",
                     "Export folders must remain separate even when sanitized names collide")
        precondition(folders.values.allSatisfy { !$0.contains("/") && $0 != "." && $0 != ".." })
        var old = try model.makeProject()
        for index in old.deviceSections!.indices { old.deviceSections![index].name = nil }
        let prepared = try ProjectFileWorker.prepare(old)
        precondition(prepared.deviceSections.allSatisfy { $0.title == "iPad" },
                     "Older sections without names must still open")
        model.releaseProjectAccess(); restored.releaseProjectAccess()
        print("PASS: repeated device classes, independent orientations/defaults, duplicated layouts, named roundtrip, membership, rename undo, unique names and isolated export folders")
    }
}
