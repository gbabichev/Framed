import AppKit

@main struct FramePreparationChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FramePreparationChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source: URL
        if let path = CommandLine.arguments.dropFirst().first { source = URL(fileURLWithPath: path) }
        else {
            let context = CGContext(data: nil, width: 1800, height: 2600, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.2, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 2600))
            context.clear(CGRect(x: 100, y: 100, width: 1600, height: 2400))
            source = root.appendingPathComponent("Source.png")
            try ProjectImage(ImportedImage(id: UUID(), name: "Test", image: context.makeImage()!)).png.write(to: source)
        }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let imported = await library.importFiles([source])
        let frame = imported.first!
        var maxGap = 0.0, beats = 0
        let heartbeat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ProcessInfo.processInfo.systemUptime
                maxGap = max(maxGap, now - previous); previous = now; beats += 1
            }
        }
        try await Task.sleep(for: .milliseconds(25))
        let start = ProcessInfo.processInfo.systemUptime
        async let firstRequest = library.preparedFrame(for: frame)
        async let secondRequest = library.preparedFrame(for: frame)
        let (first, second) = try await (firstRequest, secondRequest)
        let cold = ProcessInfo.processInfo.systemUptime - start
        heartbeat.cancel(); _ = await heartbeat.value
        precondition(first === second && first.opening != nil, "Concurrent requests must share a prepared frame and mask")
        precondition(maxGap < 0.25 && beats > 2, "Frame preparation stalled the main actor")
        let model = EditorModel(frameLibrary: library)
        let baseline = model.fingerprint
        let warmStart = ProcessInfo.processInfo.systemUptime
        try await model.prefetchLibraryFrame(frame)
        let warm = ProcessInfo.processInfo.systemUptime - warmStart
        precondition(model.fingerprint == baseline && !model.isDirty && !model.canUndo && !model.isBusy && model.mockups.isEmpty,
                     "Prefetch must not edit a project, dirty its window, or add an undo step")
        let applied = await model.useLibraryFrameInBackground(frame)
        precondition(applied && model.selectedMockup?.image === first.image.image && model.opening?.mask === first.opening?.mask)
        model.undo(); precondition(!model.isDirty && model.mockups.isEmpty)
        model.redo(); precondition(model.selectedMockup != nil && model.opening != nil)

        // Cancelling the selection prefetch must not cancel an active Use Frame consumer.
        let sharedLibrary = FrameLibrary(directory: library.directory)
        let prefetch = Task { @MainActor in try await sharedLibrary.preparedFrame(for: frame) }
        let use = Task { @MainActor in try await sharedLibrary.preparedFrame(for: frame) }
        try await Task.sleep(for: .milliseconds(20))
        prefetch.cancel()
        let shared = try await use.value
        do { _ = try await prefetch.value; fatalError("Cancelled prefetch succeeded") } catch is CancellationError { }
        let sharedCached = try await sharedLibrary.preparedFrame(for: frame)
        precondition(shared === sharedCached)

        let abandonedLibrary = FrameLibrary(directory: library.directory)
        let abandoned = Task { @MainActor in try await abandonedLibrary.preparedFrame(for: frame) }
        try await Task.sleep(for: .milliseconds(50))
        let cancelStart = ProcessInfo.processInfo.systemUptime
        abandoned.cancel()
        do { _ = try await abandoned.value; fatalError("Abandoned selection succeeded") } catch is CancellationError { }
        precondition(ProcessInfo.processInfo.systemUptime - cancelStart < 0.75, "Abandoned mask work kept running")
        let retriedSelection = try await abandonedLibrary.preparedFrame(for: frame)
        precondition(retriedSelection.opening != nil, "Cancelled job prevented a later selection")

        // Failed preparations must be evicted so a repaired library asset can be retried.
        let asset = library.directory.appendingPathComponent(frame.id.uuidString).appendingPathComponent("frame.png")
        let bytes = try Data(contentsOf: asset)
        let retryLibrary = FrameLibrary(directory: library.directory)
        try Data("corrupt".utf8).write(to: asset)
        do { _ = try await retryLibrary.preparedFrame(for: frame); fatalError("Corrupt frame accepted") } catch is FramedError { }
        try bytes.write(to: asset)
        let repaired = try await retryLibrary.preparedFrame(for: frame)
        precondition(repaired.opening != nil)
        try library.rename(frame, to: "Renamed Frame")
        let renamed = library.frames.first!
        let otherWindow = EditorModel(frameLibrary: library)
        let renamedApplied = await otherWindow.useLibraryFrameInBackground(renamed)
        precondition(renamedApplied && otherWindow.selectedMockup?.name == "Renamed Frame"
                     && otherWindow.selectedMockup?.image === first.image.image, "Cache should be reusable across windows and renames")

        // Clear the library cache and remove its PNG: an existing project must still switch instantly.
        library.reload()
        try FileManager.default.removeItem(at: asset)
        model.selectMockup(nil)
        let loadedStart = ProcessInfo.processInfo.systemUptime
        let reused = await model.useLibraryFrameInBackground(renamed)
        let loaded = ProcessInfo.processInfo.systemUptime - loadedStart
        precondition(reused && model.selectedMockup?.image === first.image.image && model.error == nil && loaded < 0.1,
                     "Already-loaded project frame went back to disk")
        await library.removeFrames([renamed.id])
        do { _ = try await library.preparedFrame(for: renamed); fatalError("Removed frame remained cached") } catch is FramedError { }
        precondition(model.opening != nil && model.selectedMockup != nil, "Global removal damaged the embedded project frame")
        print(String(format: "PASS: cold %.3fs, cached prefetch %.4fs, loaded reuse %.4fs, main-actor max gap %.3fs; shared jobs/masks, cancellation, retries, rename, removal, undo and dirty isolation", cold, warm, loaded, maxGap))
    }
}
