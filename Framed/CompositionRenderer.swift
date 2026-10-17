import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreText

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

nonisolated enum GlowCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: Self { self }
    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: self == .topRight || self == .bottomRight ? size.width : 0,
                y: self == .topLeft || self == .topRight ? size.height : 0)
    }
}

nonisolated enum DeviceFadeEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, bottom
    var id: Self { self }
    var title: String { self == .top ? "Top" : "Bottom" }
}

nonisolated struct CompositionEffects: Codable, Equatable, Sendable {
    var cornerGlow = false
    var glowCorner = GlowCorner.topLeft
    var glowRed = 0.98
    var glowGreen = 0.76
    var glowBlue = 0.68
    var glowStrength = 0.65
    var glowSpread = 0.85
    var deviceFade = false
    var fadeEdge = DeviceFadeEdge.bottom
    var fadeDepth = 0.35
    var fadeStrength = 1.0

    var glowColor: NSColor {
        get { NSColor(srgbRed: glowRed, green: glowGreen, blue: glowBlue, alpha: 1) }
        set {
            guard let color = newValue.usingColorSpace(.sRGB) else { return }
            glowRed = color.redComponent; glowGreen = color.greenComponent; glowBlue = color.blueComponent
        }
    }
    var isValid: Bool {
        [glowRed, glowGreen, glowBlue, glowStrength, fadeStrength].allSatisfy { (0...1).contains($0) }
            && (0.2...1.5).contains(glowSpread) && (0.1...0.8).contains(fadeDepth)
    }
}

nonisolated enum HeadlineWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular, medium, semibold, bold
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var value: NSFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

nonisolated struct HeadlineSettings: Codable, Equatable, Sendable {
    var enabled = false
    var firstLine = "Your headline"
    var secondLine = ""
    var fontFamily = ""
    var weight = HeadlineWeight.bold
    // Font size and center scale with the canvas, preserving layout across export sizes.
    var size = 0.05
    var red = 0.08, green = 0.08, blue = 0.10
    var x = 0.5, y = 0.055

    var color: NSColor {
        get { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
        set {
            guard let color = newValue.usingColorSpace(.sRGB) else { return }
            red = min(1, max(0, color.redComponent)); green = min(1, max(0, color.greenComponent)); blue = min(1, max(0, color.blueComponent))
        }
    }
    var firstLineInput: String {
        get { firstLine }
        set { firstLine = Self.singleLine(newValue) }
    }
    var secondLineInput: String {
        get { secondLine }
        set { secondLine = Self.singleLine(newValue) }
    }
    private static func singleLine(_ value: String) -> String {
        String(value.components(separatedBy: .newlines).joined(separator: " ").prefix(200))
    }
    var isValid: Bool {
        [red, green, blue, x, y].allSatisfy { (0...1).contains($0) }
            && (0.01...0.15).contains(size) && firstLine.count <= 200 && secondLine.count <= 200
            && !firstLine.contains(where: { $0.isNewline }) && !secondLine.contains(where: { $0.isNewline })
            && fontFamily.count <= 200
    }
}

struct HeadlineLayout {
    let rect: CGRect // Top-left canvas coordinates, shared by rendering and drag hit testing.
    let lines: [CTLine]
    let widths: [CGFloat]
    let ascent: CGFloat
    let lineHeight: CGFloat
}

enum HeadlineRenderer {
    static func layout(_ headline: HeadlineSettings, canvas: CGSize) -> HeadlineLayout? {
        guard headline.enabled else { return nil }
        let text = [headline.firstLine, headline.secondLine].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !text.isEmpty else { return nil }
        let fontSize = canvas.width * headline.size
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: headline.fontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: headline.weight.value.rawValue]
        ])
        let font = headline.fontFamily.isEmpty ? NSFont.systemFont(ofSize: fontSize, weight: headline.weight.value)
            : NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: headline.weight.value)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: headline.color]
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let maxWidth = canvas.width * 0.9
        let lines = text.map { value -> CTLine in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            return CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth
                ? CTLineCreateTruncatedLine(line, maxWidth, .end, token) ?? line : line
        }
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        for line in lines {
            var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
            CTLineGetTypographicBounds(line, &a, &d, &l)
            ascent = max(ascent, a); descent = max(descent, d); leading = max(leading, l)
        }
        let lineHeight = (ascent + descent + leading) * 1.1
        let width = min(canvas.width, max(fontSize, widths.max() ?? fontSize))
        let height = min(canvas.height, ascent + descent + CGFloat(lines.count - 1) * lineHeight)
        let centerX = min(canvas.width - width / 2, max(width / 2, headline.x * canvas.width))
        let centerY = min(canvas.height - height / 2, max(height / 2, headline.y * canvas.height))
        return HeadlineLayout(rect: CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height),
                              lines: lines, widths: widths, ascent: ascent, lineHeight: lineHeight)
    }

    static func draw(_ headline: HeadlineSettings, canvas: CGSize, context: CGContext) {
        guard let layout = layout(headline, canvas: canvas) else { return }
        context.saveGState()
        context.textMatrix = .identity
        for (index, line) in layout.lines.enumerated() {
            context.textPosition = CGPoint(x: layout.rect.midX - layout.widths[index] / 2,
                                           y: canvas.height - layout.rect.minY - layout.ascent - CGFloat(index) * layout.lineHeight)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}

nonisolated enum CenterSnapping {
    /// Use preview points so the magnetic zone feels consistent at any canvas size.
    static func position(_ point: CGPoint, canvas: CGSize, enabled: Bool, threshold: CGFloat = 8) -> CGPoint {
        guard enabled else { return point }
        func snap(_ value: CGFloat, extent: CGFloat) -> CGFloat {
            guard extent.isFinite, extent > 0 else { return value }
            return abs(value - 0.5) * extent <= threshold ? 0.5 : value
        }
        return CGPoint(x: snap(point.x, extent: canvas.width), y: snap(point.y, extent: canvas.height))
    }
}

nonisolated enum PreviewResolution {
    /// Render one source pixel per display pixel for the aspect-fitted canvas.
    static func maxDimension(canvas: CGSize, viewport: CGSize, displayScale: CGFloat) -> Double {
        guard canvas.width > 0, canvas.height > 0, viewport.width > 0, viewport.height > 0,
              [canvas.width, canvas.height, viewport.width, viewport.height, displayScale].allSatisfy(\.isFinite),
              displayScale > 0 else { return 1 }
        let fit = min(viewport.width / canvas.width, viewport.height / canvas.height)
        let native = max(canvas.width, canvas.height)
        return Double(max(1, min(native, ceil(native * fit * displayScale))))
    }
}

nonisolated struct CompositionSettings: Sendable {
    var preset = ScreenshotPreset.all[0]
    var landscape = false
    var deviceScale = 0.88
    var deviceX = 0.5
    var deviceY = 0.5
    var background = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1)
    var transparentBackground = false
    var effects = CompositionEffects()
    var headline = HeadlineSettings()
    var fillScreen = false
    var manualScreen = false
    var screenX = 0.05
    var screenY = 0.05
    var screenWidth = 0.90
    var screenHeight = 0.90
    var cornerRadius = 0.06
    var showHeadline: Bool {
        get { headline.enabled }
        set {
            // Offer headroom only for the default placement; respect an existing layout.
            if newValue && !headline.enabled && abs(deviceX - 0.5) < 0.0001 && abs(deviceY - 0.5) < 0.0001 {
                deviceY = 0.54
            } else if !newValue && headline.enabled && abs(deviceX - 0.5) < 0.0001 && abs(deviceY - 0.54) < 0.0001 {
                deviceY = 0.5
            }
            headline.enabled = newValue
        }
    }
    mutating func resetDevicePosition() {
        deviceX = 0.5; deviceY = headline.enabled ? 0.54 : 0.5
    }
    var headlineFontSize: Double {
        get { headline.size * outputSize.width }
        set { headline.size = min(0.15, max(0.01, newValue / outputSize.width)) }
    }
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
    /// A device-only preview: independent of canvas placement, headline, and effects.
    static func deviceThumbnail(screenshot: CGImage, mockup: CGImage, opening: ScreenOpening?,
                                settings: CompositionSettings, maxDimension: Int = 88) throws -> CGImage {
        let ratio = min(1, Double(maxDimension) / Double(max(mockup.width, mockup.height)))
        let width = max(1, Int((Double(mockup.width) * ratio).rounded()))
        let height = max(1, Int((Double(mockup.height) * ratio).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FramedError.message("Could not allocate the device thumbnail.")
        }
        var centered = settings
        centered.deviceScale = 1; centered.deviceX = 0.5; centered.deviceY = 0.5
        context.interpolationQuality = .high
        try drawForeground(screenshot: screenshot, mockup: mockup, opening: opening, settings: centered,
                           size: CGSize(width: width, height: height), context: context)
        guard let image = context.makeImage() else { throw FramedError.message("Could not render the device thumbnail.") }
        return image
    }

    static func deviceRect(image: CGImage, canvas: CGSize, scale: Double, center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        let factor = min(canvas.width / Double(image.width), canvas.height / Double(image.height)) * scale
        let size = CGSize(width: Double(image.width) * factor, height: Double(image.height) * factor)
        return CGRect(x: canvas.width * center.x - size.width / 2,
                      y: canvas.height * (1 - center.y) - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func deviceRect(image: CGImage, canvas: CGSize, settings: CompositionSettings) -> CGRect {
        deviceRect(image: image, canvas: canvas, scale: settings.deviceScale,
                   center: CGPoint(x: settings.deviceX, y: settings.deviceY))
    }

    static func targetRect(canvas: CGSize, settings: CompositionSettings) -> CGRect {
        let width = canvas.width * settings.deviceScale, height = canvas.height * settings.deviceScale
        return CGRect(x: canvas.width * settings.deviceX - width / 2,
                      y: canvas.height * (1 - settings.deviceY) - height / 2, width: width, height: height)
    }

    static func foregroundRect(screenshot: CGImage, mockup: CGImage?, canvas: CGSize, settings: CompositionSettings) -> CGRect {
        if mockup == nil && settings.fillScreen { return targetRect(canvas: canvas, settings: settings) }
        return deviceRect(image: mockup ?? screenshot, canvas: canvas, settings: settings)
    }

    static func render(screenshot: CGImage, mockup: CGImage?, opening: ScreenOpening?,
                       settings: CompositionSettings, maxDimension: Double? = nil, forceOpaque: Bool = false) throws -> CGImage {
        let full = settings.outputSize
        let ratio: CGFloat = maxDimension.map { min(CGFloat(1), CGFloat($0) / max(full.width, full.height)) } ?? 1
        let size = CGSize(width: max(1, (full.width * ratio).rounded()), height: max(1, (full.height * ratio).rounded()))
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
        drawCornerGlow(in: context, size: size, effects: settings.effects)
        if settings.effects.deviceFade {
            guard let layer = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                        bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw FramedError.message("Could not allocate the device effect layer.")
            }
            layer.interpolationQuality = .high
            try drawForeground(screenshot: screenshot, mockup: mockup, opening: opening,
                               settings: settings, size: size, context: layer)
            let device = foregroundRect(screenshot: screenshot, mockup: mockup, canvas: size, settings: settings)
            guard let foreground = layer.makeImage(),
                  let mask = fadeMask(size: size, device: device, effects: settings.effects) else {
                throw FramedError.message("Could not render the device fade.")
            }
            context.saveGState()
            context.clip(to: CGRect(origin: .zero, size: size), mask: mask)
            context.draw(foreground, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        } else {
            try drawForeground(screenshot: screenshot, mockup: mockup, opening: opening,
                               settings: settings, size: size, context: context)
        }
        HeadlineRenderer.draw(settings.headline, canvas: size, context: context)
        guard let result = context.makeImage() else { throw FramedError.message("Could not render the composition.") }
        return result
    }

    private static func drawForeground(screenshot: CGImage, mockup: CGImage?, opening: ScreenOpening?,
                                       settings: CompositionSettings, size: CGSize, context: CGContext) throws {
        if let mockup {
            let device = deviceRect(image: mockup, canvas: size, settings: settings)
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
            let target = targetRect(canvas: size, settings: settings)
            draw(screenshot, in: target, fill: settings.fillScreen, context: context)
        }
    }

    private static func drawCornerGlow(in context: CGContext, size: CGSize, effects: CompositionEffects) {
        guard effects.cornerGlow, effects.glowStrength > 0 else { return }
        let colors = [effects.glowColor.withAlphaComponent(effects.glowStrength).cgColor,
                      effects.glowColor.withAlphaComponent(effects.glowStrength * 0.3).cgColor,
                      effects.glowColor.withAlphaComponent(0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: colors as CFArray, locations: [0, 0.5, 1]) else { return }
        let origin = effects.glowCorner.point(in: size)
        context.drawRadialGradient(gradient, startCenter: origin, startRadius: 0,
                                   endCenter: origin, endRadius: hypot(size.width, size.height) * effects.glowSpread,
                                   options: [.drawsAfterEndLocation])
    }

    private static func fadeMask(size: CGSize, device: CGRect, effects: CompositionEffects) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                        colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1 - effects.fadeStrength, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        let top = effects.fadeEdge == .top
        let end = top ? device.maxY : device.minY
        let start = end + (top ? -1 : 1) * device.height * effects.fadeDepth
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: start), end: CGPoint(x: 0, y: end),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage()
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
