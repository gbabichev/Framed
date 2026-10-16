import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class EditorModel {
    var screenshots: [ImportedImage] = []
    var mockups: [ImportedImage] = []
    var selectedScreenshotID: UUID?
    var selectedMockupID: UUID?
    var settings = CompositionSettings()
    var jpeg = false
    var error: String?
    var status = "Import screenshots to get started."
    var isBusy = false
    private var openings: [UUID: ScreenOpening] = [:]
    let frameLibrary: FrameLibrary
    private var libraryIDs: [UUID: UUID] = [:]
    var isShowingFrameLibrary = false
    var isPresentingFrameImport = false
    @ObservationIgnored private var frameImportTask: Task<Void, Never>?
    private(set) var projectURL: URL?
    private var savedFingerprint: ProjectFingerprint?
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var hasProjectAccess = false
    var isPresentingProjectDialog = false

    init(frameLibrary: FrameLibrary = .shared) {
        self.frameLibrary = frameLibrary
        savedFingerprint = fingerprint
    }

    var selectedLibraryFrameID: UUID? { selectedMockupID.flatMap { libraryIDs[$0] } }

    var selectedFrameDisplayName: String? {
        if let id = selectedLibraryFrameID, let frame = frameLibrary.frames.first(where: { $0.id == id }) { return frame.name }
        return selectedMockup?.name
    }

    var selectedFrameIsInLibrary: Bool {
        guard let id = selectedLibraryFrameID else { return false }
        return frameLibrary.frames.contains { $0.id == id }
    }

    func saveSelectedFrameToLibrary() {
        guard let frame = selectedMockup else { return }
        do { libraryIDs[frame.id] = try frameLibrary.store(frame).id }
        catch { frameLibrary.error = error.localizedDescription }
    }

    @discardableResult
    func useLibraryFrame(_ frame: SavedFrame) -> Bool {
        do {
            if let existing = mockups.first(where: { libraryIDs[$0.id] == frame.id }) {
                selectMockup(existing.id)
            } else {
                let image = try frameLibrary.image(for: frame)
                applyFrame(frame, image: image, opening: ScreenOpening.detect(in: image.image))
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func useLibraryFrameInBackground(_ frame: SavedFrame) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let (image, opening) = try await FrameFileWorker.prepare(frame, directory: frameLibrary.directory)
            try Task.checkCancellation()
            applyFrame(frame, image: image, opening: opening)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    private func applyFrame(_ frame: SavedFrame, image: ImportedImage, opening: ScreenOpening?) {
        if let existing = mockups.first(where: { libraryIDs[$0.id] == frame.id }) {
            selectMockup(existing.id)
            return
        }
        mockups.append(image)
        libraryIDs[image.id] = frame.id
        if let opening { openings[image.id] = opening }
        selectMockup(image.id)
    }

    func startFrameImport(_ urls: [URL], completion: @escaping (UUID?) -> Void = { _ in }) {
        startFrameImportSources(urls.map { .file($0) }, completion: completion)
    }

    func saveSelectedFrameToLibraryInBackground(completion: @escaping (UUID?) -> Void = { _ in }) {
        guard let frame = selectedMockup else { return }
        startFrameImportSources([.image(frame)]) { [self] id in
            if let id { libraryIDs[frame.id] = id }
            completion(id)
        }
    }

    private func startFrameImportSources(_ sources: [FrameImportSource], completion: @escaping (UUID?) -> Void) {
        guard !sources.isEmpty, !isBusy, !frameLibrary.isImporting, !frameLibrary.isRemoving else { return }
        isBusy = true
        isPresentingFrameImport = true
        frameImportTask = Task { @MainActor [self] in
            let imported = await frameLibrary.importSources(sources)
            status = Task.isCancelled ? "Import stopped. Completed frames remain in the library." : "Imported \(imported.count) frame(s)."
            isBusy = false
            isPresentingFrameImport = false
            frameImportTask = nil
            if !isShowingFrameLibrary, let message = frameLibrary.error {
                error = message
                frameLibrary.error = nil
            }
            completion(imported.last?.id)
        }
    }

    func cancelFrameImport() {
        frameLibrary.markImportCancelling()
        frameImportTask?.cancel()
    }

    var projectTitle: String { projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    var fingerprint: ProjectFingerprint {
        ProjectFingerprint(screenshots: screenshots.map(\.id), mockups: mockups.map(\.id),
                           selectedMockupID: selectedMockupID, settings: ProjectSettings(settings), jpeg: jpeg)
    }
    var isDirty: Bool { fingerprint != savedFingerprint }

    func makeProject() throws -> FramedProject {
        try FramedProject(screenshots: screenshots.map { try ProjectImage($0) }, mockups: mockups.map { try ProjectImage($0) },
                          selectedScreenshotID: selectedScreenshotID, selectedMockupID: selectedMockupID,
                          settings: ProjectSettings(settings), jpeg: jpeg)
    }

    func restoreProject(_ project: FramedProject, at url: URL) throws {
        guard project.version == 1 else { throw FramedError.message("Unsupported project version.") }
        // Decode and validate everything before replacing the current canvas.
        let restoredSettings = try project.settings.restored()
        let shots = try project.screenshots.map { try $0.restored() }
        let frames = try project.mockups.map { try $0.restored() }
        let allIDs = (shots + frames).map(\.id)
        guard Set(allIDs).count == allIDs.count,
              project.selectedScreenshotID == nil || shots.contains(where: { $0.id == project.selectedScreenshotID }),
              project.selectedMockupID == nil || frames.contains(where: { $0.id == project.selectedMockupID }) else {
            throw FramedError.message("This project contains invalid image references.")
        }
        let detected = Dictionary(uniqueKeysWithValues: frames.compactMap { frame in
            ScreenOpening.detect(in: frame.image).map { (frame.id, $0) }
        })
        screenshots = shots; mockups = frames; openings = detected
        selectedScreenshotID = project.selectedScreenshotID ?? shots.first?.id
        selectedMockupID = project.selectedMockupID
        settings = restoredSettings; jpeg = project.jpeg
        adoptProjectURL(url)
        savedFingerprint = fingerprint
        status = "Opened \(url.lastPathComponent)."
        libraryIDs = [:]
        for frame in frames {
            // Opening a project never resurrects a frame deliberately removed from the library.
            libraryIDs[frame.id] = try? frameLibrary.matching(frame)?.id
        }
    }

    private func adoptProjectURL(_ url: URL) {
        if hasProjectAccess, let projectURL { projectURL.stopAccessingSecurityScopedResource() }
        projectURL = url
        hasProjectAccess = url.startAccessingSecurityScopedResource()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func releaseProjectAccess() {
        if hasProjectAccess, let projectURL { projectURL.stopAccessingSecurityScopedResource() }
        hasProjectAccess = false
    }

    @discardableResult
    func writeProject(to url: URL) -> Bool {
        do {
            try makeProject().write(to: url)
            adoptProjectURL(url)
            savedFingerprint = fingerprint
            status = "Saved \(url.lastPathComponent)."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func saveProject(asNewFile: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !isBusy, !isPresentingProjectDialog else { completion(false); return }
        if let projectURL, !asNewFile { completion(writeProject(to: projectURL)); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.framedProject]
        panel.nameFieldStringValue = projectURL?.lastPathComponent ?? "Untitled.framed"
        panel.directoryURL = projectURL?.deletingLastPathComponent()
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        isPresentingProjectDialog = true
        let handle: (NSApplication.ModalResponse) -> Void = { [self] response in
            isPresentingProjectDialog = false
            guard response == .OK, let url = panel.url else { completion(false); return }
            completion(writeProject(to: url))
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(panel.runModal()) }
    }

    func openProject() {
        guard !isBusy, !isPresentingProjectDialog else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.framedProject]
        isPresentingProjectDialog = true
        let handle: (NSApplication.ModalResponse) -> Void = { [self] response in
            isPresentingProjectDialog = false
            guard response == .OK, let url = panel.url else { return }
            requestOpenProject(at: url)
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(panel.runModal()) }
    }

    func requestOpenProject(at url: URL) {
        guard !isBusy, !isPresentingProjectDialog else { return }
        // Validate before asking to replace a working project.
        do {
            let project = try FramedProject.read(from: url)
            confirmDiscardingChanges { [self] proceed in
                guard proceed else { return }
                do { try restoreProject(project, at: url) }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    func confirmDiscardingChanges(completion: @escaping (Bool) -> Void) {
        if isShowingFrameLibrary {
            isShowingFrameLibrary = false
            if let window, let sheet = window.attachedSheet {
                window.endSheet(sheet)
                sheet.orderOut(nil)
            }
        }
        guard !isBusy, !isPresentingProjectDialog else { completion(false); return }
        guard isDirty else { completion(true); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to ‘\(projectTitle)’?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        isPresentingProjectDialog = true
        let handle: (NSApplication.ModalResponse) -> Void = { [self] response in
            isPresentingProjectDialog = false
            switch response {
            case .alertFirstButtonReturn: saveProject(completion: completion)
            case .alertSecondButtonReturn: completion(true)
            default: completion(false)
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) }
        else { handle(alert.runModal()) }
    }

    var selectedScreenshot: ImportedImage? { screenshots.first { $0.id == selectedScreenshotID } }
    var selectedMockup: ImportedImage? { mockups.first { $0.id == selectedMockupID } }
    var opening: ScreenOpening? { selectedMockupID.flatMap { openings[$0] } }
    var canExport: Bool { selectedScreenshot != nil && (selectedMockup == nil || opening != nil || settings.manualScreen) && !isBusy }

    var warnings: [String] {
        guard let shot = selectedScreenshot else { return [] }
        var messages: [String] = []
        var target = settings.outputSize
        if let mockup = selectedMockup {
            guard let bounds = settings.manualScreen ? settings.manualBounds : opening?.bounds else {
                return ["No enclosed transparent screen found. Enable manual screen area, or choose another transparent PNG frame."]
            }
            let device = CompositionRenderer.deviceRect(image: mockup.image, canvas: target, scale: settings.deviceScale)
            target = CGSize(width: device.width * bounds.width, height: device.height * bounds.height)
            let screenAspect = target.width / target.height
            let shotAspect = Double(shot.image.width) / Double(shot.image.height)
            if abs(screenAspect / shotAspect - 1) > 0.025 {
                messages.append(settings.fillScreen ? "Aspect ratios differ. Fill crops the screenshot; check the preview." : "Aspect ratios differ. Fit keeps all content with black bars inside the screen.")
            }
        } else {
            target.width *= settings.deviceScale; target.height *= settings.deviceScale
        }
        let sx = target.width / Double(shot.image.width), sy = target.height / Double(shot.image.height)
        if (settings.fillScreen ? max(sx, sy) : min(sx, sy)) > 1.05 {
            messages.append("The screenshot will be enlarged. A higher-resolution source will look sharper.")
        }
        return messages
    }

    func importImages(mockups importingMockups: Bool, completion: @escaping (UUID?) -> Void = { _ in }) {
        guard !isBusy, !frameLibrary.isImporting, !frameLibrary.isRemoving else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = importingMockups ? [.png] : [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.message = importingMockups ? "Choose front-facing PNG mockups with transparent screen openings." : "Choose screenshots from a device or simulator."
        guard panel.runModal() == .OK else { return }
        if importingMockups {
            startFrameImport(panel.urls, completion: completion)
        } else {
            load(panel.urls, asMockups: false)
        }
    }

    func load(_ urls: [URL], asMockups: Bool) {
        var failures: [String] = []
        for url in urls {
            do {
                let imported = try ImportedImage(url: url)
                if asMockups {
                    try frameLibrary.store(imported)
                } else {
                    screenshots.append(imported)
                    selectedScreenshotID = imported.id
                    if screenshots.count == 1 {
                        let w = imported.image.width, h = imported.image.height
                        if let preset = ScreenshotPreset.all.first(where: { ($0.width == w && $0.height == h) || ($0.width == h && $0.height == w) }) {
                            settings.preset = preset
                            settings.landscape = w > h && preset.width < preset.height
                        }
                    }
                }
            } catch { failures.append(error.localizedDescription) }
        }
        status = "Imported \(urls.count - failures.count) image(s)."
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func selectMockup(_ id: UUID?) {
        guard id != selectedMockupID else { return }
        selectedMockupID = id
        settings.manualScreen = false
        if let bounds = opening?.bounds {
            settings.screenX = bounds.minX; settings.screenY = bounds.minY
            settings.screenWidth = bounds.width; settings.screenHeight = bounds.height
        }
    }

    func removeScreenshot(_ id: UUID) {
        screenshots.removeAll { $0.id == id }
        if selectedScreenshotID == id { selectedScreenshotID = screenshots.first?.id }
    }

    func exportSelected() {
        guard let screenshot = selectedScreenshot, canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [jpeg ? .jpeg : .png]
        panel.nameFieldStringValue = "\(screenshot.name)-framed.\(jpeg ? "jpg" : "png")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let image = try CompositionRenderer.render(screenshot: screenshot.image, mockup: selectedMockup?.image, opening: opening, settings: settings)
            try CompositionRenderer.encode(image, jpeg: jpeg).write(to: url, options: .atomic)
            status = "Saved \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }

    func exportAll() {
        guard canExport else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Export here"
        panel.message = "A new folder will be created for this export. Every screenshot uses the current frame and layout."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        isBusy = true
        // Yield between images so progress and window events remain responsive.
        Task { @MainActor in
            let folder = directory.appendingPathComponent("Framed-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let images = screenshots, configuration = settings, mockup = selectedMockup?.image, mask = opening, useJPEG = jpeg
            var count = 0
            defer { isBusy = false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                for (index, shot) in images.enumerated() {
                    let image = try CompositionRenderer.render(screenshot: shot.image, mockup: mockup, opening: mask, settings: configuration)
                    let safeName = shot.name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
                    let url = folder.appendingPathComponent(String(format: "%02d-", index + 1) + safeName + (useJPEG ? ".jpg" : ".png"))
                    try CompositionRenderer.encode(image, jpeg: useJPEG).write(to: url, options: .atomic)
                    count += 1
                    status = "Exported \(count) of \(images.count)…"
                    await Task.yield()
                }
                status = "Saved \(count) screenshots in \(folder.lastPathComponent)."
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch { self.error = "Export stopped after \(count) files. \(error.localizedDescription)" }
        }
    }
}
