import AppKit

@main
struct ProjectOpenChecks {
    static func main() async throws {
        guard let argument = CommandLine.arguments.dropFirst().first else {
            fatalError("Pass a .framed project to exercise background opening")
        }
        let source = URL(fileURLWithPath: argument)
        let original = try projectFiles(at: source)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectOpenChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root.appendingPathComponent("Frames"))
        let progressLog = LoadingProgressLog()
        let expected = try await ProjectFileWorker.read(from: source) { update in
            await progressLog.append(update)
        }
        let updates = await progressLog.updates
        precondition(updates.first?.stage == .readingProject && updates.last?.stage == .finishing)
        for (stage, total) in [(ProjectLoadingProgress.Stage.screenshots, expected.screenshots.count),
                               (.frames, expected.mockups.count), (.screenDetection, expected.mockups.count)] where total > 0 {
            let events = updates.filter { $0.stage == stage }
            precondition(events.count == total * 2 && events.first?.completed == 0 && events.last?.completed == total,
                         "Every image must report progress before and after processing")
            precondition(events.allSatisfy { $0.total == total && $0.itemName != nil })
            precondition(zip(events, events.dropFirst()).allSatisfy { $0.completed <= $1.completed },
                         "Progress must be delivered in order")
        }
        if (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            let events = updates.filter { $0.stage == .readingImages }
            let total = expected.screenshots.count + expected.mockups.count
            precondition(events.count == total * 2 && events.last?.completed == total,
                         "Package reading must report individual asset progress")
        }
        _ = await library.importSources(expected.mockups.map { .image($0) })
        let model = EditorModel(frameLibrary: library)
        var beats = 0, longestGap = 0.0
        let heartbeat = Task { @MainActor in
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ProcessInfo.processInfo.systemUptime
                longestGap = max(longestGap, now - previous); previous = now; beats += 1
            }
        }
        try await Task.sleep(for: .milliseconds(25))
        let started = ProcessInfo.processInfo.systemUptime
        model.requestOpenProject(at: source)
        let dispatchTime = ProcessInfo.processInfo.systemUptime - started
        precondition(model.isBusy && model.isOpeningProject && model.screenshots.isEmpty)
        // A second request cannot race the first or replace its result.
        model.requestOpenProject(at: root.appendingPathComponent("Missing.framed"))
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        heartbeat.cancel(); _ = await heartbeat.value
        precondition(dispatchTime < 0.1 && longestGap < 0.25 && beats > 5,
                     "Main actor stalled: dispatch \(dispatchTime)s, longest gap \(longestGap)s")
        precondition(!model.isOpeningProject && model.error == nil && !model.isDirty && model.projectURL == source)
        precondition(model.screenshots.map(\.id) == expected.screenshots.map(\.id) && model.mockups.map(\.id) == expected.mockups.map(\.id))
        for shot in model.screenshots {
            let layout = expected.layouts[shot.id]!
            precondition(ProjectSettings(model.layout(for: shot.id).settings) == ProjectSettings(layout.settings))
            model.selectedScreenshotID = shot.id
            if layout.mockupID != nil { precondition(model.selectedLibraryFrameID != nil, "Embedded PNG did not match its library copy") }
        }
        precondition(!model.isDirty)
        let baseline = model.fingerprint
        model.requestOpenProject(at: source)
        model.cancelProjectOpen()
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.error == nil && !model.isOpeningProject && !model.isCancellingProjectOpen && model.fingerprint == baseline)
        model.requestOpenProject(at: source)
        try await Task.sleep(for: .milliseconds(50))
        if model.isOpeningProject {
            model.cancelProjectOpen()
            while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.error == nil && model.fingerprint == baseline && model.projectURL == source,
                         "Cancelling an in-flight image decode replaced the current project")
        }
        let corrupt = root.appendingPathComponent("Corrupt.framed")
        try Data("not JSON".utf8).write(to: corrupt)
        model.requestOpenProject(at: corrupt)
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.error != nil && model.fingerprint == baseline && model.projectURL == source && !model.isDirty)
        model.error = nil
        var broken = try FramedProject.read(from: source)
        broken.mockups[0].png = Data("broken image".utf8)
        let invalid = root.appendingPathComponent("Broken image.framed")
        try broken.write(to: invalid)
        model.requestOpenProject(at: invalid)
        while model.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(model.error != nil && model.fingerprint == baseline && model.projectURL == source)
        let unchanged = try projectFiles(at: source)
        precondition(original == unchanged, "Opening modified the source project")
        model.releaseProjectAccess()
        print(String(format: "PASS: background open %.3fs, dispatch %.3fs, main-actor max gap %.3fs (%d heartbeats); library matching, layout preservation, clean state, cancellation, concurrent-open rejection, atomic decode/image failures, and ordered per-image progress", elapsed, dispatchTime, longestGap, beats))
    }
    static func projectFiles(at url: URL) throws -> [String: Data] {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !isDirectory.boolValue { return ["project": try Data(contentsOf: url)] }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw FramedError.message("Couldn’t inspect test project")
        }
        var files: [String: Data] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[String(file.path.dropFirst(url.path.count))] = try Data(contentsOf: file)
            }
        }
        return files
    }

}

private actor LoadingProgressLog {
    private(set) var updates: [ProjectLoadingProgress] = []
    func append(_ update: ProjectLoadingProgress) { updates.append(update) }
}
