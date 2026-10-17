import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ImportedImage: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let image: CGImage
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    init(id: UUID, name: String, image: CGImage) {
        self.id = id; self.name = name; self.image = image
    }

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
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.image = image
    }
}

nonisolated enum FramedError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let message): message } }
}

nonisolated struct ScreenOpening: Sendable {
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
        // Detection stays bounded for predictable import cost. Export clipping is refined
        // from source alpha; enlarging the thresholded detection grid causes stair-stepping.
        let seed = largest[largest.count / 2]
        let nativeMask = refinedMask(in: image, seed: CGPoint(x: (Double(seed % w) + 0.5) / Double(w),
                                                              y: (Double(seed / w) + 0.5) / Double(h)))
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let maskImage = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: [], provider: provider, decode: nil,
                                      shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return Self(bounds: CGRect(x: Double(minX) / Double(w), y: Double(minY) / Double(h),
                                   width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h)),
                    mask: nativeMask ?? maskImage)
    }

    private static func refinedMask(in image: CGImage, seed: CGPoint) -> CGImage? {
        // This exceeds the longest supported export side while bounding very large imports.
        let scale = min(1, 4096 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let seedX = min(width - 1, max(0, Int(seed.x * Double(width))))
        let seedY = min(height - 1, max(0, Int(seed.y * Double(height))))
        guard alpha[seedY * width + seedX] < 16 else { return nil }

        func flood(threshold: UInt8) -> [UInt8]? {
            var remaining = alpha
            var mask = [UInt8](repeating: 0, count: width * height)
            var seeds = [seedY * width + seedX]
            // Scanline flood fill avoids a queue containing every screen pixel.
            while let point = seeds.popLast() {
                guard remaining[point] < threshold else { continue }
                let y = point / width
                var left = point % width
                while left > 0 && remaining[y * width + left - 1] < threshold { left -= 1 }
                var right = point % width
                while right < width - 1 && remaining[y * width + right + 1] < threshold { right += 1 }
                guard left > 0, right < width - 1, y > 0, y < height - 1 else { return nil }
                var aboveRun = false, belowRun = false
                for x in left...right {
                    let index = y * width + x
                    remaining[index] = 255
                    let above = remaining[index - width] < threshold
                    let below = remaining[index + width] < threshold
                    if above && !aboveRun { seeds.append(index - width) }
                    if below && !belowRun { seeds.append(index + width) }
                    aboveRun = above; belowRun = below
                }
                // Tuck clipping one pixel beneath the opaque bezel. The original PNG's
                // antialiased alpha supplies the visible edge, including camera cutouts.
                for row in (y - 1)...(y + 1) {
                    for x in (left - 1)...(right + 1) { mask[row * width + x] = 255 }
                }
            }
            return mask
        }
        // Some translucent artwork has no opaque barrier. Fall back to the same
        // enclosed region threshold as detection, still at the refined resolution.
        guard let mask = flood(threshold: 254) ?? flood(threshold: 16),
              let provider = CGDataProvider(data: Data(mask) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct CompositionSettings {
    var preset = ScreenshotPreset.all[0]
    var landscape = false
    var deviceScale = 0.88
    var background = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1)
    var transparentBackground = false
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
    // Edges move independently while preserving the opposite edge and a usable screen area.
    // These projections keep the stored rectangle equal to what the controls display.
    var screenLeft: Double {
        get { manualBounds.minX }
        set { setScreenEdges(left: min(max(0, newValue), screenRight - 0.1), top: screenTop,
                             right: screenRight, bottom: screenBottom) }
    }
    var screenRight: Double {
        get { manualBounds.maxX }
        set { setScreenEdges(left: screenLeft, top: screenTop,
                             right: max(screenLeft + 0.1, min(1, newValue)), bottom: screenBottom) }
    }
    var screenTop: Double {
        get { manualBounds.minY }
        set { setScreenEdges(left: screenLeft, top: min(max(0, newValue), screenBottom - 0.1),
                             right: screenRight, bottom: screenBottom) }
    }
    var screenBottom: Double {
        get { manualBounds.maxY }
        set { setScreenEdges(left: screenLeft, top: screenTop, right: screenRight,
                             bottom: max(screenTop + 0.1, min(1, newValue))) }
    }
    private mutating func setScreenEdges(left: Double, top: Double, right: Double, bottom: Double) {
        screenX = left; screenY = top
        screenWidth = right - left; screenHeight = bottom - top
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
                       settings: CompositionSettings, maxDimension: Double? = nil, forceOpaque: Bool = false) throws -> CGImage {
        let full = settings.outputSize
        let ratio: CGFloat = maxDimension.map { min(CGFloat(1), CGFloat($0) / max(full.width, full.height)) } ?? 1
        let size = CGSize(width: (full.width * ratio).rounded(), height: (full.height * ratio).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: (settings.transparentBackground && !forceOpaque
                                          ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else {
            throw FramedError.message("Could not allocate the export canvas.")
        }
        context.interpolationQuality = .high
        if !settings.transparentBackground || forceOpaque {
            context.setFillColor(settings.background.withAlphaComponent(1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
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
