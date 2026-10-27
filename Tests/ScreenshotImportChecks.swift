import AppKit

@main struct ScreenshotImportChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotImportChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 3200, height: 2400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        let bytes = try CompositionRenderer.encode(context.makeImage()!, jpeg: false)
        let urls = try ["First", "Second", "Third", "Fourth"].map { name -> URL in
            let url = root.appendingPathComponent(name + ".png")
            try bytes.write(to: url)
            return url
        }
        let bad = root.appendingPathComponent("Missing.png")
        let model = EditorModel(frameLibrary: FrameLibrary(directory: root.appendingPathComponent("Frames")))
        model.addDeviceSection(.iPad)
        let tablet = model.activeSection!.id
        model.settings.deviceScale = 0.61
        model.settings.headline.firstLine = "Inherited template"
        model.addDeviceSection(.mac)
        let mac = model.activeSection!.id
        model.selectDeviceSection(tablet)
        let clean = model.fingerprint
        let importURLs = [urls[0], bad] + Array(urls.dropFirst())
        var beats = 0, longestGap = 0.0
        let heartbeat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - previous); beats += 1; previous = now
            }
        }
        var completedID: UUID?
        var completionCalled = false
        let started = ProcessInfo.processInfo.systemUptime
        model.startScreenshotImport(importURLs) { id in completedID = id; completionCalled = true }
        let dispatch = ProcessInfo.processInfo.systemUptime - started
        precondition(model.isBusy && model.screenshots.isEmpty)
        var rejected = false
        model.startScreenshotImport(urls) { id in precondition(id == nil); rejected = true }
        precondition(rejected)
        // Destination must be captured when the import starts, before decoding suspends.
        model.selectDeviceSection(mac)
        while model.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        heartbeat.cancel(); _ = await heartbeat.value
        precondition(dispatch < 0.1 && longestGap < 0.25 && beats > 0,
                     "Import blocked the main actor: dispatch \(dispatch), max gap \(longestGap), beats \(beats)")
        precondition(completionCalled && completedID == model.screenshots.last?.id)
        precondition(model.screenshots.map(\.name) == ["First", "Second", "Third", "Fourth"])
        precondition(model.sidebarGroups.first { $0.id == tablet }!.screenshots.count == 4
                     && model.sidebarGroups.first { $0.id == mac }!.screenshots.isEmpty)
        precondition(model.screenshots.allSatisfy { $0.sourceData == bytes && $0.image.width == 3200 && $0.image.height == 2400 })
        precondition(model.settings.headline.firstLine == "Inherited template" && model.settings.deviceScale == 0.61)
        precondition(model.error?.contains("Missing.png") == true && model.status == "Imported 4 image(s).")
        model.undo()
        precondition(model.screenshots.isEmpty && model.fingerprint == clean,
                     "One undo must revert the entire import without touching device templates")
        model.redo()
        precondition(model.screenshots.count == 4)
        let imported = model.fingerprint
        model.startScreenshotImport([bad])
        while model.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        precondition(model.fingerprint == imported && model.error != nil)
        model.undo()
        precondition(model.screenshots.isEmpty, "An all-failed import must not consume an undo step")
        print(String(format: "PASS: off-main decoding, %.3fs dispatch, %.3fs main-actor max gap (%d heartbeats), busy guards, captured destination, order, source bytes, template inheritance, partial failures, completion, and grouped undo/redo", dispatch, longestGap, beats))
    }
}
