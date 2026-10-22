import AppKit

@main struct ProjectStyleChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectStyleChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let model = EditorModel(frameLibrary: library)
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: url)
        model.addDeviceSection(.iPhone)
        let phone = model.activeSection!.id
        model.load([url, url], asMockups: false)
        let a = model.screenshots[0].id, b = model.screenshots[1].id
        model.settings.headline.x = 0.3
        model.settings.headline.y = 0.2
        model.settings.deviceScale = 0.65
        let position = model.settings.headline
        let canvas = model.settings.preset
        model.addDeviceSection(.mac)
        let mac = model.activeSection!.id
        model.load([url], asMockups: false)
        let c = model.selectedScreenshotID!
        model.selectProjectStyle()
        let before = model.fingerprint
        model.projectStyleSettings.headline.enabled = true
        model.projectStyleSettings.headline.firstLine = "One app, every device"
        model.projectStyleSettings.effects.cornerGlow = true
        precondition(model.isDirty && model.fingerprint != before)
        for id in [a, b, c] {
            precondition(model.layout(for: id).settings.headline.firstLine == "One app, every device")
            precondition(model.layout(for: id).settings.effects.cornerGlow)
        }
        precondition(model.layout(for: b).settings.headline.x == position.x
                     && model.layout(for: b).settings.headline.y == position.y
                     && model.layout(for: b).settings.deviceScale == 0.65
                     && model.layout(for: b).settings.preset == canvas,
                     "Shared styles must preserve local placement, scale and canvas")
        model.selectDeviceSection(phone)
        model.setFollowsParentStyle(false, component: .headline)
        model.settings.headline.firstLine = "Phone headline"
        precondition(model.layout(for: a).settings.headline.firstLine == "Phone headline"
                     && model.layout(for: c).settings.headline.firstLine == "One app, every device")
        model.sidebarSelections = [.screenshot(a)]
        model.setFollowsParentStyle(false, component: .effects)
        model.settings.effects.cornerGlow = false
        model.setFollowsParentStyle(false, component: .headline)
        model.settings.headline.firstLine = "Local headline"
        model.selectProjectStyle()
        model.projectStyleSettings.headline.firstLine = "Updated project"
        model.projectStyleSettings.effects.deviceFade = true
        precondition(model.layout(for: a).settings.headline.firstLine == "Local headline"
                     && !model.layout(for: a).settings.effects.deviceFade)
        precondition(model.layout(for: b).settings.headline.firstLine == "Phone headline"
                     && model.layout(for: b).settings.effects.deviceFade)
        precondition(model.layout(for: c).settings.headline.firstLine == "Updated project")
        model.sidebarSelections = [.screenshot(a)]
        model.setFollowsParentStyle(true, component: .headline)
        precondition(model.settings.headline.firstLine == "Phone headline")
        model.moveScreenshots([b], toSection: mac)
        precondition(model.layout(for: b).settings.headline.firstLine == "Updated project",
                     "Linked screenshots must follow their new device after moving")
        model.selectProjectStyle()
        let customized = model.fingerprint
        model.applyProjectStyleToAll()
        precondition([a,b,c].allSatisfy { model.layout(for: $0).settings.headline.firstLine == "Updated project"
            && model.layout(for: $0).settings.effects.deviceFade })
        model.undo()
        precondition(model.fingerprint == customized, "Apply to All must undo all link changes in one step")
        model.redo()
        model.projectStyleSettings.headline.firstLine = "Saved shared headline"
        let saved = root.appendingPathComponent("Styles.framed")
        precondition(model.writeProject(to: saved))
        let reopened = EditorModel(frameLibrary: library)
        try reopened.restoreProject(FramedProject.read(from: saved), at: saved)
        precondition(model.fingerprint == reopened.fingerprint && !reopened.isDirty)
        reopened.projectStyleSettings.headline.firstLine = "Changed after reopening"
        precondition([a,b,c].allSatisfy { reopened.layout(for: $0).settings.headline.firstLine == "Changed after reopening" })
        reopened.undo()
        precondition(!reopened.isDirty, "Undoing a shared edit must restore the clean fingerprint")
        // v3 projects retain every device and screenshot as a local customization.
        var legacy = try model.makeProject()
        legacy.version = 3; legacy.projectStyle = nil
        for index in legacy.layouts!.indices {
            legacy.layouts![index].settings = ProjectSettings(model.layout(for: legacy.layouts![index].screenshotID).settings)
            legacy.layouts![index].styleOverrides = nil
        }
        for index in legacy.deviceSections!.indices { legacy.deviceSections![index].styleOverrides = nil }
        let old = EditorModel(frameLibrary: library)
        try old.restoreProject(legacy, at: saved)
        let original = old.layout(for: a).settings.headline
        old.projectStyleSettings.headline.firstLine = "New template"
        precondition(old.layout(for: a).settings.headline == original, "Opening an old project must preserve its existing styles")
        old.applyProjectStyleToAll()
        precondition(old.layout(for: a).settings.headline.firstLine == "New template")
        let empty = EditorModel(frameLibrary: library)
        empty.projectStyleSettings.headline.enabled = true
        empty.projectStyleSettings.headline.firstLine = "Template before importing"
        let emptyURL = root.appendingPathComponent("Template.framed")
        precondition(empty.writeProject(to: emptyURL))
        let emptyRestored = EditorModel(frameLibrary: library)
        try emptyRestored.restoreProject(FramedProject.read(from: emptyURL), at: emptyURL)
        precondition(empty.fingerprint == emptyRestored.fingerprint && !emptyRestored.isDirty)
        emptyRestored.load([url], asMockups: false)
        precondition(emptyRestored.settings.headline.firstLine == "Template before importing")
        for editor in [model, reopened, old, empty, emptyRestored] { editor.releaseProjectAccess() }
        print("PASS: live cross-device styles, independent card overrides, local placement/canvas, moves, Apply to All undo/redo, package persistence, clean tracking, legacy preservation, and template-only projects")
    }
}
