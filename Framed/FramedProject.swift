import AppKit
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    // Keep the package distinct from the original JSON UTI: Launch Services can
    // retain declarations from older app builds installed on the same Mac.
    static let framedProject = UTType(exportedAs: "com.georgebabichev.framed.project-package", conformingTo: .package)
    static let legacyFramedProject = UTType(exportedAs: "com.georgebabichev.framed.project", conformingTo: .json)
}

nonisolated struct ProjectSettings: Codable, Equatable, Sendable {
    var preset: ScreenshotPreset
    var landscape: Bool
    var deviceScale: Double
    var deviceX: Double?
    var deviceY: Double?
    var red: Double
    var green: Double
    var blue: Double
    var transparentBackground: Bool?
    var effects: CompositionEffects?
    var headline: HeadlineSettings?
    var desktop: DesktopSettings?
    var fillScreen: Bool
    var windowMode: Bool?
    var manualScreen: Bool
    var screenX: Double
    var screenY: Double
    var screenWidth: Double
    var screenHeight: Double
    var cornerRadius: Double

    init(_ settings: CompositionSettings) {
        preset = settings.preset; landscape = settings.landscape
        deviceScale = settings.deviceScale
        deviceX = settings.deviceX; deviceY = settings.deviceY
        transparentBackground = settings.transparentBackground
        effects = settings.effects
        headline = settings.headline
        desktop = settings.desktop
        windowMode = settings.windowMode
        let color = settings.background.usingColorSpace(.sRGB) ?? .white
        red = max(0, min(1, color.redComponent))
        green = max(0, min(1, color.greenComponent))
        blue = max(0, min(1, color.blueComponent))
        fillScreen = settings.fillScreen; manualScreen = settings.manualScreen
        screenX = settings.screenX; screenY = settings.screenY
        screenWidth = settings.screenWidth; screenHeight = settings.screenHeight
        cornerRadius = settings.cornerRadius
    }

    func restored() throws -> CompositionSettings {
        guard (desktop ?? DesktopSettings()).isValid, (headline ?? HeadlineSettings()).isValid, (effects ?? CompositionEffects()).isValid, ScreenshotPreset.all.contains(preset),
              (0...1).contains(deviceX ?? 0.5), (0...1).contains(deviceY ?? 0.5),
              (0.4...1).contains(deviceScale), [red, green, blue].allSatisfy({ (0...1).contains($0) }),
              (0...0.9).contains(screenX), (0...0.9).contains(screenY),
              (0.099999...1).contains(screenWidth), (0.099999...1).contains(screenHeight),
              (0...0.25).contains(cornerRadius) else {
            throw FramedError.message("This project contains unsupported canvas settings.")
        }
        var settings = CompositionSettings()
        settings.preset = preset; settings.landscape = landscape; settings.deviceScale = deviceScale
        settings.deviceX = deviceX ?? 0.5; settings.deviceY = deviceY ?? 0.5
        settings.background = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        settings.transparentBackground = transparentBackground ?? false
        settings.effects = effects ?? CompositionEffects()
        settings.headline = headline ?? HeadlineSettings()
        settings.desktop = desktop ?? DesktopSettings()
        settings.windowMode = windowMode ?? (desktop?.enabled == true)
        settings.fillScreen = fillScreen; settings.manualScreen = manualScreen
        settings.screenX = screenX; settings.screenY = screenY
        settings.screenWidth = screenWidth; settings.screenHeight = screenHeight
        settings.cornerRadius = cornerRadius
        return settings
    }
}

nonisolated struct ProjectImage: Codable, Sendable {
    var id: UUID
    var name: String
    // Kept as `png` for reading legacy JSON; package assets retain their source format.
    var png: Data
    var sourceFilename: String? = nil
    var file: String? = nil

    private enum CodingKeys: String, CodingKey { case id, name, png, sourceFilename, file }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        png = try values.decodeIfPresent(Data.self, forKey: .png) ?? Data()
        sourceFilename = try values.decodeIfPresent(String.self, forKey: .sourceFilename)
        file = try values.decodeIfPresent(String.self, forKey: .file)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        if !png.isEmpty { try values.encode(png, forKey: .png) }
        try values.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
        try values.encodeIfPresent(file, forKey: .file)
    }

    init(id: UUID, name: String, png: Data) {
        self.id = id; self.name = name; self.png = png
    }

    init(_ imported: ImportedImage) throws {
        id = imported.id; name = imported.name
        sourceFilename = imported.sourceFilename
        if let original = imported.sourceData {
            png = original
            return
        }
        sourceFilename = imported.name + ".png"
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FramedError.message("Could not embed \(name) in the project.")
        }
        CGImageDestinationAddImage(destination, imported.image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FramedError.message("Could not embed \(name).") }
        png = data as Data
    }

    func restored() throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000, width * height <= 60_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw FramedError.message("The embedded image ‘\(name)’ is missing or invalid.")
        }
        return ImportedImage(id: id, name: name, image: image, sourceData: png, sourceFilename: sourceFilename)
    }
}

nonisolated struct ProjectScreenshotLayout: Codable, Equatable, Sendable {
    var screenshotID: UUID
    var sectionID: UUID? = nil
    var mockupID: UUID?
    var settings: ProjectSettings
    var styleOverrides: StyleOverrides? = nil
}

nonisolated struct ScreenshotLayout: Sendable {
    var settings: CompositionSettings
    var mockupID: UUID?
    var styleOverrides = StyleOverrides()
}

nonisolated struct FramedProject: Codable, Sendable {
    var version = 2
    var screenshots: [ProjectImage]
    var mockups: [ProjectImage]
    var selectedScreenshotID: UUID?
    var selectedMockupID: UUID?
    var settings: ProjectSettings
    var jpeg: Bool
    var layouts: [ProjectScreenshotLayout]?
    var deviceSections: [DeviceSection]? = nil
    var selectedDeviceSectionID: UUID? = nil
    var projectStyle: ProjectStyle? = nil

    static func read(from url: URL, progress: (ProjectLoadingProgress) -> Void = { _ in }) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let project = isDirectory.boolValue ? try ProjectPackage.read(from: url, progress: progress)
            : try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard (1...4).contains(project.version) else { throw FramedError.message("This project was created by a newer version of Framed.") }
        return project
    }

    func write(to url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try ProjectPackage.write(self, to: url)
    }
}

/// Capture immutable images on the main actor; materialize asset records off it.
nonisolated struct ProjectSaveSnapshot: Sendable {
    var metadata: FramedProject
    let screenshots: [ImportedImage]
    let mockups: [ImportedImage]

    func materialized() throws -> FramedProject {
        var project = metadata
        project.screenshots = try screenshots.map { try ProjectImage($0) }
        project.mockups = try mockups.map { try ProjectImage($0) }
        return project
    }
}

/// Comparing IDs avoids re-encoding large images every time a slider changes.
struct ProjectFingerprint: Equatable {
    var screenshots: [UUID]
    var mockups: [UUID]
    var layouts: [ProjectScreenshotLayout]
    var emptySettings: ProjectSettings?
    var emptyMockupID: UUID?
    var jpeg: Bool
    var deviceSections: [DeviceSection] = []
    var memberships: [UUID: UUID] = [:]
    var projectStyle = ProjectStyle()
    var screenshotNames: [UUID: String] = [:]
}

/// Fully prepared away from the UI; publishing it only replaces in-memory state.
nonisolated struct PreparedProject: Sendable {
    let screenshots: [ImportedImage]
    let mockups: [ImportedImage]
    let openings: [UUID: ScreenOpening]
    let frameDigests: [UUID: String]
    let layouts: [UUID: ScreenshotLayout]
    let settings: CompositionSettings
    let selectedScreenshotID: UUID?
    let selectedMockupID: UUID?
    let jpeg: Bool
    let deviceSections: [DeviceSection]
    let memberships: [UUID: UUID]
    let selectedDeviceSectionID: UUID?
    let projectStyle: ProjectStyle
}

/// Counts describe the current stage rather than an estimated overall percentage.
nonisolated struct ProjectLoadingProgress: Sendable, Equatable {
    enum Stage: Sendable {
        case readingProject, readingImages, screenshots, frames, screenDetection, layouts, finishing
    }
    var stage: Stage
    var completed = 0
    var total = 0
    var itemName: String? = nil

    var message: String {
        switch stage {
        case .readingProject: "Reading project…"
        case .readingImages: "Reading image files…"
        case .screenshots: "Preparing screenshots…"
        case .frames: "Preparing device frames…"
        case .screenDetection: "Detecting device screens…"
        case .layouts: "Checking layouts…"
        case .finishing: "Finishing up…"
        }
    }
}

nonisolated enum ProjectFileWorker {
    @concurrent
    static func write(_ snapshot: ProjectSaveSnapshot, to url: URL) async throws {
        try snapshot.materialized().write(to: url)
    }

    @concurrent
    static func read(from url: URL, progress: @escaping @Sendable (ProjectLoadingProgress) async -> Void) async throws -> PreparedProject {
        // Bridge synchronous decoding/file coordination to ordered UI updates.
        // The consumer can publish progress while an individual image is processing.
        let (updates, continuation) = AsyncStream<ProjectLoadingProgress>.makeStream()
        let reporter = Task {
            for await update in updates { await progress(update) }
        }
        do {
            try Task.checkCancellation()
            continuation.yield(ProjectLoadingProgress(stage: .readingProject))
            let project = try autoreleasepool {
                try FramedProject.read(from: url) { continuation.yield($0) }
            }
            try Task.checkCancellation()
            let prepared = try autoreleasepool {
                try prepare(project) { continuation.yield($0) }
            }
            continuation.yield(ProjectLoadingProgress(stage: .finishing))
            continuation.finish()
            await reporter.value
            try Task.checkCancellation()
            return prepared
        } catch {
            continuation.finish()
            await reporter.value
            throw error
        }
    }

    static func prepare(_ project: FramedProject, progress: (ProjectLoadingProgress) -> Void = { _ in }) throws -> PreparedProject {
        try Task.checkCancellation()
        guard (1...4).contains(project.version) else { throw FramedError.message("Unsupported project version.") }
        // Decode and validate everything before replacing the current canvas.
        let restoredSettings = try project.settings.restored()
        let sharedStyle = project.version >= 4 ? project.projectStyle : nil
        guard (project.version < 4 || sharedStyle != nil),
              sharedStyle.map({ $0.headline.isValid && $0.effects.isValid }) ?? true else {
            throw FramedError.message("This project contains an invalid project style.")
        }
        func restore(_ records: [ProjectImage], stage: ProjectLoadingProgress.Stage) throws -> [ImportedImage] {
            try records.enumerated().map { index, record in
                try Task.checkCancellation()
                progress(ProjectLoadingProgress(stage: stage, completed: index, total: records.count, itemName: record.name))
                let image = try autoreleasepool { try record.restored() }
                progress(ProjectLoadingProgress(stage: stage, completed: index + 1, total: records.count, itemName: record.name))
                return image
            }
        }
        let shots = try restore(project.screenshots, stage: .screenshots)
        let frames = try restore(project.mockups, stage: .frames)
        progress(ProjectLoadingProgress(stage: .layouts))
        let allIDs = (shots + frames).map(\.id)
        guard Set(allIDs).count == allIDs.count,
              project.selectedScreenshotID == nil || shots.contains(where: { $0.id == project.selectedScreenshotID }),
              project.selectedMockupID == nil || frames.contains(where: { $0.id == project.selectedMockupID }) else {
            throw FramedError.message("This project contains invalid image references.")
        }
        var restoredLayouts: [UUID: ScreenshotLayout] = [:]
        if project.version >= 2 {
            guard let records = project.layouts, records.count == shots.count,
                  Set(records.map(\.screenshotID)) == Set(shots.map(\.id)) else {
                throw FramedError.message("This project contains missing or duplicate screenshot layouts.")
            }
            for record in records {
                guard record.mockupID == nil || frames.contains(where: { $0.id == record.mockupID }) else {
                    throw FramedError.message("A screenshot layout refers to a missing frame.")
                }
                restoredLayouts[record.screenshotID] = ScreenshotLayout(settings: try record.settings.restored(), mockupID: record.mockupID, styleOverrides: sharedStyle == nil ? .all : record.styleOverrides ?? .all)
            }
        } else {
            for shot in shots {
                restoredLayouts[shot.id] = ScreenshotLayout(settings: restoredSettings, mockupID: project.selectedMockupID, styleOverrides: .all)
            }
        }
        if project.version >= 3 {
            guard let sections = project.deviceSections, let records = project.layouts,
                  records.allSatisfy({ $0.sectionID != nil }), (!sections.isEmpty || (project.version >= 4 && shots.isEmpty)) else {
                throw FramedError.message("This project contains missing device sections.")
            }
        }
        var sections = project.deviceSections ?? []
        for index in sections.indices {
            if sharedStyle == nil { sections[index].styleOverrides = .all }
        }
        var memberships: [UUID: UUID] = [:]
        guard Set(sections.map(\.id)).count == sections.count else {
            throw FramedError.message("This project contains duplicate device sections.")
        }
        for section in sections {
            guard section.name.map({ $0.count <= 80 && !$0.contains(where: { $0.isNewline }) }) ?? true else {
                throw FramedError.message("This project contains an invalid device section name.")
            }
            _ = try section.settings.restored()
            guard section.mockupID == nil || frames.contains(where: { $0.id == section.mockupID }) else {
                throw FramedError.message("A device layout refers to a missing frame.")
            }
        }
        for shot in shots {
            let layout = restoredLayouts[shot.id]!
            if let sectionID = project.layouts?.first(where: { $0.screenshotID == shot.id })?.sectionID {
                guard sections.contains(where: { $0.id == sectionID }) else {
                    throw FramedError.message("A screenshot refers to a missing device section.")
                }
                memberships[shot.id] = sectionID
            } else {
                let device = ProjectDevice.detect(layout.settings.preset.name)
                if let section = sections.first(where: { $0.device == device }) {
                    memberships[shot.id] = section.id
                } else {
                    let section = DeviceSection(device: device, settings: ProjectSettings(layout.settings), mockupID: layout.mockupID)
                    sections.append(section); memberships[shot.id] = section.id
                }
            }
        }
        if let selected = project.selectedDeviceSectionID, !sections.contains(where: { $0.id == selected }) {
            throw FramedError.message("The selected device section is missing.")
        }
        var detected: [UUID: ScreenOpening] = [:]
        var digests: [UUID: String] = [:]
        for (index, frame) in frames.enumerated() {
            try Task.checkCancellation()
            progress(ProjectLoadingProgress(stage: .screenDetection, completed: index, total: frames.count, itemName: frame.name))
            if let opening = ScreenOpening.detect(in: frame.image) { detected[frame.id] = opening }
            digests[frame.id] = FrameFileWorker.digest(project.mockups[index].png)
            progress(ProjectLoadingProgress(stage: .screenDetection, completed: index + 1, total: frames.count, itemName: frame.name))
        }
        try Task.checkCancellation()
        return PreparedProject(screenshots: shots, mockups: frames, openings: detected, frameDigests: digests,
                               layouts: restoredLayouts, settings: restoredSettings,
                               selectedScreenshotID: project.selectedDeviceSectionID != nil ? project.selectedScreenshotID : project.selectedScreenshotID ?? shots.first?.id,
                               selectedMockupID: project.selectedMockupID, jpeg: project.jpeg,
                               deviceSections: sections, memberships: memberships, selectedDeviceSectionID: project.selectedDeviceSectionID,
                               projectStyle: sharedStyle ?? ProjectStyle(headline: restoredSettings.headline.sharedStyle, effects: restoredSettings.effects))
    }
}
