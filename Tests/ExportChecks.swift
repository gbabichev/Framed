import AppKit
import ImageIO

@main struct ExportChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExportChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let width = 320, height = 480
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var random: UInt32 = 1
        for index in 0..<(width * height) {
            random = 1664525 &* random &+ 1013904223
            pixels[index * 4] = UInt8(truncatingIfNeeded: random >> 16)
            pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: random >> 8)
            pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: random)
            pixels[index * 4 + 3] = 255
        }
        let image = context.makeImage()!
        let high = try CompositionRenderer.encode(image, jpeg: true, jpegQuality: 1)
        let low = try CompositionRenderer.encode(image, jpeg: true, jpegQuality: 0.2)
        precondition(low.count < high.count, "JPEG quality must control encoded file size")
        let shot = ImportedImage(id: UUID(), name: "Screenshot", image: image)
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset.all[0]
        settings.transparentBackground = true
        let original = ProjectSettings(settings)
        var options = ExportOptions()
        options.scale = 0.5
        let path = directory.appendingPathComponent("01-Screenshot.png")
        try await ExportWorker.write(screenshot: shot, mockup: nil, opening: nil, settings: settings,
            jpeg: false, options: options, url: path, overwrite: false)
        let source = CGImageSourceCreateWithURL(path as CFURL, nil)!
        let exported = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(exported.width == 603 && exported.height == 1311, "Export must use requested scale")
        precondition(NSBitmapImageRep(cgImage: exported).colorAt(x: 0, y: 0)!.alphaComponent < 0.01,
                     "PNG resizing must retain transparency")
        let second = ExportWorker.availableURL(in: directory, name: "01-Screenshot", extension: "png")
        precondition(second.deletingLastPathComponent().path == directory.path && second.lastPathComponent == "01-Screenshot-2.png",
                     "Batch files must save directly in the chosen folder with collision-safe names")
        let data = try Data(contentsOf: path)
        do {
            try await ExportWorker.write(screenshot: shot, mockup: nil, opening: nil, settings: settings,
                jpeg: false, options: options, url: path, overwrite: false)
            preconditionFailure("Batch export must never overwrite an existing file")
        } catch { }
        let unchanged = try Data(contentsOf: path)
        precondition(unchanged == data)
        options.preset = ScreenshotPreset.all.first { $0.name == "Mac" && $0.width == 1280 }!
        options.jpegQuality = 0.5
        let jpegURL = directory.appendingPathComponent("Mac.jpg")
        try await ExportWorker.write(screenshot: shot, mockup: nil, opening: nil, settings: settings,
            jpeg: true, options: options, url: jpegURL, overwrite: false)
        let jpegSource = CGImageSourceCreateWithURL(jpegURL as CFURL, nil)!
        let jpeg = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil)!
        precondition(jpeg.width == 640 && jpeg.height == 400, "Canvas override and scaling must combine")
        precondition(NSBitmapImageRep(cgImage: jpeg).colorAt(x: 0, y: 0)!.alphaComponent == 1,
                     "JPEG must flatten transparent canvases")
        precondition(ProjectSettings(settings) == original, "Export sizing must not change the project layout")
        print("PASS: JPEG compression, output scaling, canvas override, PNG alpha, opaque JPEG, direct folder and collision protection")
    }
}
