import AppKit
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    static let framedProject = UTType(exportedAs: "com.georgebabichev.framed.project", conformingTo: .json)
}

struct ProjectSettings: Codable, Equatable {
    var preset: ScreenshotPreset
    var landscape: Bool
    var deviceScale: Double
    var red: Double
    var green: Double
    var blue: Double
    var fillScreen: Bool
    var manualScreen: Bool
    var screenX: Double
    var screenY: Double
    var screenWidth: Double
    var screenHeight: Double
    var cornerRadius: Double

    init(_ settings: CompositionSettings) {
        preset = settings.preset; landscape = settings.landscape
        deviceScale = settings.deviceScale
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
        guard ScreenshotPreset.all.contains(preset),
              (0.4...1).contains(deviceScale), [red, green, blue].allSatisfy({ (0...1).contains($0) }),
              (0...0.8).contains(screenX), (0...0.8).contains(screenY),
              (0.1...1).contains(screenWidth), (0.1...1).contains(screenHeight),
              (0...0.25).contains(cornerRadius) else {
            throw FramedError.message("This project contains unsupported canvas settings.")
        }
        var settings = CompositionSettings()
        settings.preset = preset; settings.landscape = landscape; settings.deviceScale = deviceScale
        settings.background = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
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
    var png: Data

    init(id: UUID, name: String, png: Data) {
        self.id = id; self.name = name; self.png = png
    }

    init(_ imported: ImportedImage) throws {
        id = imported.id; name = imported.name
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
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FramedError.message("The embedded image ‘\(name)’ is missing or invalid.")
        }
        return ImportedImage(id: id, name: name, image: image)
    }
}

struct FramedProject: Codable {
    var version = 1
    var screenshots: [ProjectImage]
    var mockups: [ProjectImage]
    var selectedScreenshotID: UUID?
    var selectedMockupID: UUID?
    var settings: ProjectSettings
    var jpeg: Bool

    static func read(from url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let project = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard project.version == 1 else { throw FramedError.message("This project was created by a newer version of Framed.") }
        return project
    }

    func write(to url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Comparing IDs avoids re-encoding large images every time a slider changes.
struct ProjectFingerprint: Equatable {
    var screenshots: [UUID]
    var mockups: [UUID]
    var selectedMockupID: UUID?
    var settings: ProjectSettings
    var jpeg: Bool
}
