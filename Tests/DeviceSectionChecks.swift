import AppKit

@main
struct DeviceSectionChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceSectionChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        let context = CGContext(data: nil, width: 80, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
        let url = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: url)
        model.addDeviceSection(.mac)
        let mac = model.activeSection!.id
        model.settings.headline.firstLine = "Mac default"
        model.settings.deviceScale = 0.7
        model.load([url, url], asMockups: false)
        let a = model.screenshots[0].id, b = model.screenshots[1].id
        precondition(model.settings.preset.name == "Mac" && model.settings.deviceScale == 0.7)
        model.settings.headline.firstLine = "Specific wording"
        model.settings.deviceScale = 0.5
        model.selectDeviceSection(mac)
        precondition(model.selectedScreenshot == nil && model.settings.deviceScale == 0.7)
        model.settings.deviceScale = 0.8
        precondition(model.layout(for: a).settings.deviceScale == 0.7 && model.layout(for: b).settings.deviceScale == 0.5,
                     "Editing defaults must preserve existing screenshot overrides")
        model.applyDeviceLayout(mac)
        precondition(model.layout(for: b).settings.deviceScale == 0.8
                     && model.layout(for: b).settings.headline.firstLine == "Specific wording")
        model.undo()
        precondition(model.layout(for: b).settings.deviceScale == 0.5)
        model.addDeviceSection(.iPhone)
        let phone = model.activeSection!.id
        model.load([url], asMockups: false)
        let c = model.selectedScreenshotID!
        precondition(model.settings.preset.name.contains("iPhone") && model.screenshotsForExport(.device).map(\.id) == [c])
        model.moveScreenshot(b, toSection: phone)
        precondition(model.layout(for: b).settings.deviceScale == 0.5, "Moving sections preserves the screenshot layout")
        model.reorderScreenshots(in: phone, from: IndexSet(integer: 0), to: 2)
        precondition(model.sidebarGroups[1].screenshots.map(\.id) == [c, b])
        model.useScreenshotAsDefault(b)
        model.selectDeviceSection(phone)
        precondition(model.settings.deviceScale == 0.5)
        model.addDeviceSection(.iPhone)
        precondition(model.deviceSections.count == 2, "Adding an existing family selects its section")
        let path = root.appendingPathComponent("Devices.framed")
        precondition(model.writeProject(to: path))
        let saved = model.fingerprint
        model.sidebarSelection = .screenshot(a)
        model.selectDeviceSection(mac)
        precondition(!model.isDirty, "Selection and browsing do not dirty a project")
        let reopened = EditorModel(frameLibrary: library)
        try reopened.restoreProject(FramedProject.read(from: path), at: path)
        precondition(reopened.fingerprint == saved && !reopened.isDirty)
        precondition(reopened.selectedScreenshot == nil && reopened.activeSection?.id == phone,
                     "Device template selection survives save/open")
        precondition(reopened.screenshotsForExport(.project).map(\.id) == [a, c, b])
        var legacy = try model.makeProject()
        legacy.version = 2; legacy.deviceSections = nil; legacy.selectedDeviceSectionID = nil
        for index in legacy.layouts!.indices { legacy.layouts![index].sectionID = nil }
        let migrated = try ProjectFileWorker.prepare(legacy)
        precondition(migrated.memberships.count == 3 && migrated.deviceSections.count == 2,
                     "Legacy screenshot layouts migrate into device families")
        var invalid = try model.makeProject()
        invalid.layouts![0].sectionID = UUID()
        do { _ = try ProjectFileWorker.prepare(invalid); fatalError("Dangling section accepted") } catch is FramedError { }
        model.removeDeviceSection(mac)
        precondition(model.screenshots.count == 2 && model.deviceSections.count == 1)
        model.undo()
        precondition(model.fingerprint == saved, "Removing a device undoes its screenshots and defaults together")
        model.releaseProjectAccess(); reopened.releaseProjectAccess()
        print("PASS: templates, per-screenshot isolation, device assignment/order, export scopes, selection cleanliness, project roundtrip, migration, validation and undo")
    }
}
