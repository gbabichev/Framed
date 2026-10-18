import AppKit

@main struct SectionDropChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SectionDropChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = EditorModel(frameLibrary: FrameLibrary(directory: root.appendingPathComponent("Frames")))
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = root.appendingPathComponent("Screenshot.png")
        try CompositionRenderer.encode(context.makeImage()!, jpeg: false).write(to: url)
        model.addDeviceSection(.iPhone)
        let phone = model.activeSection!.id
        model.load([url, url], asMockups: false)
        let shot = model.screenshots[0].id
        model.selectedScreenshotID = shot
        model.settings.headline.firstLine = "Keep my text"
        model.settings.deviceScale = 0.63
        let layout = ProjectSettings(model.settings)
        model.addDeviceSection(.mac)
        let mac = model.activeSection!.id
        let before = model.fingerprint
        precondition(model.handleSidebarDrop([NSItemProvider(object: shot.uuidString as NSString)], sectionID: mac))
        for _ in 0..<300 {
            if model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.map(\.id) == [shot],
                     "Dropping on an empty device must transfer the screenshot")
        precondition(model.sidebarGroups.first(where: { $0.id == phone })!.screenshots.count == 1)
        precondition(ProjectSettings(model.layout(for: shot).settings) == layout,
                     "Cross-device drops must preserve all screenshot edits")
        model.undo()
        precondition(model.fingerprint == before, "One undo must restore the original device")
        model.redo()
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.count == 1)
        model.load([url], asMockups: false, sectionID: mac)
        let second = model.selectedScreenshotID!
        precondition(model.handleSidebarDrop([NSItemProvider(object: second.uuidString as NSString)], sectionID: mac, at: 0))
        for _ in 0..<300 {
            if model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.first?.id == second { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.sidebarGroups.first(where: { $0.id == mac })!.screenshots.map(\.id) == [second, shot],
                     "Explicit row drops must retain insertion ordering")
        model.isBusy = true
        precondition(!model.handleSidebarDrop([NSItemProvider(object: shot.uuidString as NSString)], sectionID: phone))
        print("PASS: empty-device transfers, existing-device insertion, layout preservation, grouped undo/redo and busy guards")
    }
}
