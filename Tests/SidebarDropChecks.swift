import AppKit
import UniformTypeIdentifiers

@main
struct SidebarDropChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SidebarDropChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        let data = try CompositionRenderer.encode(context.makeImage()!, jpeg: false)
        let providers = try ["First", "Second"].map { name -> NSItemProvider in
            let url = root.appendingPathComponent(name + ".png")
            try data.write(to: url)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(url.dataRepresentation, nil)
                return nil
            }
            return provider
        }
        let model = EditorModel(frameLibrary: FrameLibrary(directory: root.appendingPathComponent("Frames")))
        precondition(!model.importDroppedScreenshots([NSItemProvider(object: "Internal drag" as NSString)]),
                     "Internal screenshot drags must not be imported as files")
        model.isBusy = true
        precondition(!model.importDroppedScreenshots(providers), "Busy editor must reject file drops")
        model.isBusy = false
        precondition(model.importDroppedScreenshots(providers))
        for _ in 0..<500 {
            if model.screenshots.count == 2 || model.error != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(model.error == nil && model.screenshots.map(\.name) == ["First", "Second"],
                     "Dropped files must import once in provider order")
        precondition(model.selectedScreenshotID == model.screenshots.last?.id && model.isDirty)
        model.undo()
        precondition(model.screenshots.isEmpty && !model.isDirty && !model.canUndo,
                     "One undo must remove the entire drop and restore the empty project")
        model.redo()
        precondition(model.screenshots.map(\.name) == ["First", "Second"])
        print("PASS: file drops, provider order, busy guards, internal-drag isolation, selection and grouped undo/redo")
    }
}
