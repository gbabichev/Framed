import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ImportedImage: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let image: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    init(url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000,
              width * height <= 60_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary) else {
            throw FramedError.message("Could not read \(url.lastPathComponent). Use an image up to 60 megapixels and 16,000 pixels per side.")
        }
        self.name = url.deletingPathExtension().lastPathComponent
        self.image = image
    }
}

enum FramedError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}

struct ScreenOpening {
    /// Normalized coordinates measured from the top-left of the mockup.
    let bounds: CGRect
    let mask: CGImage

    static func detect(in image: CGImage) -> Self? {
        // Work at a bounded resolution; the original mockup remains full resolution.
        let scale = min(1, 1200 / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var visited = [Bool](repeating: false, count: w * h)
        var largest: [Int] = []
        for seed in 0..<(w * h) where !visited[seed] && pixels[seed * 4 + 3] < 16 {
            var queue = [seed]
            visited[seed] = true
            var cursor = 0
            var touchesEdge = false
            while cursor < queue.count {
                let p = queue[cursor]; cursor += 1
                let x = p % w, y = p / w
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { touchesEdge = true }
                for next in [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1,
                             y > 0 ? p - w : -1, y < h - 1 ? p + w : -1] where next >= 0 {
                    if !visited[next] && pixels[next * 4 + 3] < 16 {
                        visited[next] = true; queue.append(next)
                    }
                }
            }
            if !touchesEdge && queue.count > largest.count { largest = queue }
        }
        guard largest.count > w * h / 50 else { return nil }
        var minX = w, minY = h, maxX = 0, maxY = 0
        var mask = [UInt8](repeating: 0, count: w * h)
        for p in largest {
            minX = min(minX, p % w); maxX = max(maxX, p % w)
            minY = min(minY, p / w); maxY = max(maxY, p / w)
            mask[p] = 255
        }
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let maskImage = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: [], provider: provider, decode: nil,
                                      shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return Self(bounds: CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                                   width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h)),
                    mask: maskImage)
    }
}

struct CompositionSettings {
    var preset = ScreenshotPreset.all[0]
    var landscape = false
    var deviceScale = 0.88
    var background = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1)
    var fillScreen = false
    var manualScreen = false
    var screenX = 0.05
    var screenY = 0.05
    var screenWidth = 0.90
    var screenHeight = 0.90
    var cornerRadius = 0.06
    var outputSize: CGSize { preset.size(landscape: landscape) }
    var manualBounds: CGRect {
        CGRect(x: screenX, y: screenY, width: min(screenWidth, 1 - screenX), height: min(screenHeight, 1 - screenY))
    }
}

enum CompositionRenderer {
    static func deviceRect(image: CGImage, canvas: CGSize, scale: Double) -> CGRect {
        let factor = min(canvas.width / Double(image.width), canvas.height / Double(image.height)) * scale
        let size = CGSize(width: Double(image.width) * factor, height: Double(image.height) * factor)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func render(screenshot: CGImage, mockup: CGImage?, opening: ScreenOpening?,
                       settings: CompositionSettings, maxDimension: Double? = nil) throws -> CGImage {
        let full = settings.outputSize
        let ratio: CGFloat = maxDimension.map { min(CGFloat(1), CGFloat($0) / max(full.width, full.height)) } ?? 1
        let size = CGSize(width: (full.width * ratio).rounded(), height: (full.height * ratio).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw FramedError.message("Could not allocate the export canvas.")
        }
        context.interpolationQuality = .high
        context.setFillColor(settings.background.withAlphaComponent(1).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if let mockup {
            let device = deviceRect(image: mockup, canvas: size, scale: settings.deviceScale)
            guard settings.manualScreen || opening != nil else {
                throw FramedError.message("Set the mockup’s screen area before exporting.")
            }
            let normalized = settings.manualScreen ? settings.manualBounds : opening!.bounds
            let screen = CGRect(x: device.minX + normalized.minX * device.width,
                                y: device.minY + (1 - normalized.maxY) * device.height,
                                width: normalized.width * device.width, height: normalized.height * device.height)
            context.saveGState()
            if !settings.manualScreen, let opening {
                context.clip(to: device, mask: opening.mask)
            } else {
                let radius = min(screen.width, screen.height) * settings.cornerRadius
                context.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.clip()
            }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(screen)
            draw(screenshot, in: screen, fill: settings.fillScreen, context: context)
            context.restoreGState()
            context.draw(mockup, in: device)
        } else {
            let target = CGRect(x: size.width * (1 - settings.deviceScale) / 2,
                                y: size.height * (1 - settings.deviceScale) / 2,
                                width: size.width * settings.deviceScale, height: size.height * settings.deviceScale)
            draw(screenshot, in: target, fill: settings.fillScreen, context: context)
        }
        guard let result = context.makeImage() else { throw FramedError.message("Could not render the composition.") }
        return result
    }

    private static func draw(_ image: CGImage, in rect: CGRect, fill: Bool, context: CGContext) {
        let sx = rect.width / Double(image.width), sy = rect.height / Double(image.height)
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.saveGState()
        context.clip(to: rect)
        context.draw(image, in: CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
        context.restoreGState()
    }

    static func encode(_ image: CGImage, jpeg: Bool) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, (jpeg ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil) else {
            throw FramedError.message("Could not create the image encoder.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FramedError.message("Could not encode the image.") }
        return data as Data
    }
}
