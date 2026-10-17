import AppKit
import ImageIO

@main
struct EffectsChecks {
    static func main() throws {
        func solid(_ color: NSColor, width: Int = 100, height: Int = 200) -> CGImage {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()!
        }
        func alpha(_ image: CGImage, x: Int, y: Int) -> CGFloat {
            NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!.alphaComponent
        }
        let shot = solid(.red)
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset(name: "Effects test", width: 200, height: 400)
        settings.deviceScale = 0.8
        settings.transparentBackground = true
        settings.effects.deviceFade = true
        for edge in DeviceFadeEdge.allCases {
            settings.effects.fadeEdge = edge
            let output = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings)
            let top = alpha(output, x: 100, y: 60), bottom = alpha(output, x: 100, y: 340)
            precondition(edge == .bottom ? top > 0.99 && bottom < 0.3 : bottom > 0.99 && top < 0.3,
                         "Fade edge inverted or alpha missing: \(edge), \(top), \(bottom)")
            let png = try CompositionRenderer.encode(output, jpeg: false)
            let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
            precondition(abs(alpha(decoded, x: 100, y: 340) - bottom) < 0.01)
            let opaque = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings, forceOpaque: true)
            precondition(alpha(opaque, x: 100, y: 340) == 1, "JPEG composition must stay opaque")
        }
        settings.fillScreen = true
        settings.effects.fadeEdge = .bottom
        let wide = solid(.red, width: 1000, height: 100)
        let filled = try CompositionRenderer.render(screenshot: wide, mockup: nil, opening: nil, settings: settings)
        precondition(alpha(filled, x: 100, y: 60) > 0.99 && alpha(filled, x: 100, y: 340) < 0.3,
                     "Fill-mode fade must follow the cropped screen area")
        let frameContext = CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        frameContext.setFillColor(NSColor.green.cgColor)
        frameContext.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        frameContext.clear(CGRect(x: 10, y: 10, width: 80, height: 180))
        let frame = frameContext.makeImage()!
        let framed = try CompositionRenderer.render(screenshot: shot, mockup: frame,
                                                     opening: ScreenOpening.detect(in: frame), settings: settings)
        precondition(abs(alpha(framed, x: 25, y: 340) - alpha(framed, x: 100, y: 340)) < 0.01,
                     "Frame and screenshot must fade together, once")
        settings.fillScreen = false
        settings.effects.fadeStrength = 0
        let noFade = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings)
        precondition(alpha(noFade, x: 100, y: 60) == 1 && alpha(noFade, x: 100, y: 340) == 1)
        settings.effects.deviceFade = false
        settings.effects.cornerGlow = true
        settings.effects.glowStrength = 1
        settings.effects.glowSpread = 0.3
        settings.effects.glowColor = .red
        for corner in GlowCorner.allCases {
            settings.effects.glowCorner = corner
            let image = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings)
            let point = corner.point(in: CGSize(width: 200, height: 400))
            let x = point.x == 0 ? 1 : 198
            let y = point.y == 0 ? 398 : 1
            precondition(alpha(image, x: x, y: y) > 0.9, "Glow origin wrong: \(corner)")
            precondition(alpha(image, x: 199 - x, y: 399 - y) < 0.01, "Glow leaked beyond selected radius")
        }
        var savedSettings = CompositionSettings()
        savedSettings.effects = settings.effects
        savedSettings.effects.deviceFade = true
        savedSettings.effects.fadeStrength = 0.7
        savedSettings.effects.fadeEdge = .top
        let data = try JSONEncoder().encode(ProjectSettings(savedSettings))
        let roundtrip = try JSONDecoder().decode(ProjectSettings.self, from: data).restored()
        precondition(roundtrip.effects == savedSettings.effects, "Effects lost on project roundtrip")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "effects")
        let old = try JSONDecoder().decode(ProjectSettings.self, from: JSONSerialization.data(withJSONObject: legacy)).restored()
        precondition(old.effects == CompositionEffects(), "Older projects must load with effects off")
        var invalid = ProjectSettings(savedSettings)
        invalid.effects!.fadeDepth = 5
        do { _ = try invalid.restored(); fatalError("Invalid effects accepted") } catch is FramedError { }
        print("PASS: fade directions/strength, transparent PNG, opaque export, four glow corners, effects roundtrip, legacy defaults and validation")
    }
}
