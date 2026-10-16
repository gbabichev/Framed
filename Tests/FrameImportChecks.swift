import AppKit

@main
struct FrameImportChecks {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FrameImportChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let urls: [URL]
        if let path = CommandLine.arguments.dropFirst().first {
            urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.path < $1.path }
        } else {
            let context = CGContext(data: nil, width: 1800, height: 2600, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 2600))
            context.clear(CGRect(x: 100, y: 100, width: 1600, height: 2400))
            let source = root.appendingPathComponent("Test frame.png")
            try ProjectImage(ImportedImage(id: UUID(), name: "Test frame", image: context.makeImage()!)).png.write(to: source)
            urls = Array(repeating: source, count: 10)
        }
        precondition(!urls.isEmpty)
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        var heartbeats = 0
        var longestGap: TimeInterval = 0
        let heartbeat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - previous); previous = now
                heartbeats += 1
            }
        }
        let result = await library.importFiles(urls)
        heartbeat.cancel()
        _ = await heartbeat.value
        precondition(heartbeats > 5 && longestGap < 0.5, "Main actor stalled during import: \(longestGap)s")
        precondition(result.count == urls.count && library.importCompleted == urls.count && !library.isImporting && library.error == nil,
                     "Import completion/progress incorrect")
        let expectedCount = library.frames.count
        let reloaded = FrameLibrary(directory: library.directory)
        precondition(reloaded.frames.count == expectedCount, "Completed imports not durable")

        let cancelLibrary = FrameLibrary(directory: root.appendingPathComponent("Cancelled"))
        let batch = urls + urls + urls
        let task = Task { @MainActor in await cancelLibrary.importFiles(batch) }
        while cancelLibrary.importCompleted == 0 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        let partial = await task.value
        precondition(!partial.isEmpty && partial.count < batch.count && !cancelLibrary.isImporting && cancelLibrary.error == nil,
                     "Cancellation lost completed imports or failed to stop")
        let children = try FileManager.default.contentsOfDirectory(at: cancelLibrary.directory, includingPropertiesForKeys: nil)
        precondition(!children.contains { $0.lastPathComponent.hasPrefix(".importing-") }, "Cancellation left staging files")
        _ = await cancelLibrary.importFiles(urls)
        precondition(cancelLibrary.frames.count == expectedCount, "Retry duplicated or lost frames")

        let badURL = root.appendingPathComponent("Broken.png")
        try Data("broken".utf8).write(to: badURL)
        let mixed = FrameLibrary(directory: root.appendingPathComponent("Mixed"))
        let successes = await mixed.importFiles([badURL, urls[0]])
        precondition(successes.count == 1 && mixed.error != nil && mixed.importCompleted == 2 && !mixed.isImporting,
                     "One bad file stopped the remaining imports")
        let model = EditorModel(frameLibrary: library)
        let emptyBaseline = model.fingerprint
        model.startFrameImport(urls)
        precondition(model.isBusy && model.isPresentingFrameImport, "Import dialog not presented immediately")
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!model.isPresentingFrameImport && model.fingerprint == emptyBaseline && !model.isDirty && model.mockups.isEmpty,
                     "Import dirtied an empty project or automatically selected a frame")
        let applied = await model.useLibraryFrameInBackground(library.frames[0])
        precondition(applied && model.isDirty && model.opening != nil, "Explicit Use Frame must change the canvas")
        precondition(model.writeProject(to: root.appendingPathComponent("Canvas.framed")))
        let savedBaseline = model.fingerprint
        model.startFrameImport(urls)
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.fingerprint == savedBaseline && !model.isDirty, "Import dirtied a saved project")
        model.settings.deviceScale = 0.6
        let editedBaseline = model.fingerprint
        model.startFrameImport(urls)
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.fingerprint == editedBaseline && model.isDirty, "Import changed an edited canvas or cleared its dirty state")
        model.releaseProjectAccess()
        print("PASS: background import with \(heartbeats) main-actor heartbeats (max gap \(String(format: "%.3f", longestGap))s), progress, cancellation/retry, staging cleanup, partial failures, library-only imports for empty/saved/dirty projects, and explicit frame application")
    }
}
