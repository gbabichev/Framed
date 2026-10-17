import AppKit
import ImageIO

@main
struct TransparencyChecks {
    static func main() throws {
        let context = CGContext(data: nil, width: 40, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        let shot = context.makeImage()!
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset.all[0]
        settings.background = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.8, alpha: 1)
        settings.transparentBackground = true
        let transparent = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings, maxDimension: 300)
        let png = try CompositionRenderer.encode(transparent, jpeg: false)
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
        let bitmap = NSBitmapImageRep(cgImage: decoded)
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0, "PNG background must remain transparent")
        precondition(bitmap.colorAt(x: decoded.width / 2, y: decoded.height / 2)!.alphaComponent == 1, "Screenshot must remain opaque")
        let opaque = try CompositionRenderer.render(screenshot: shot, mockup: nil, opening: nil, settings: settings, maxDimension: 300, forceOpaque: true)
        for jpeg in [false, true] {
            let encoded = try CompositionRenderer.encode(opaque, jpeg: jpeg)
            let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(encoded as CFData, nil)!, 0, nil)!
            precondition([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))
            let pixels = CGContext(data: nil, width: image.width, height: image.height,
                                   bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            pixels.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = pixels.data!.assumingMemoryBound(to: UInt8.self)
            precondition(abs(Double(bytes[1]) / 255 - 0.6) < 0.03, "Opaque exports must use chosen color")
        }
        // Persist the option and accept project files written before transparency existed.
        let saved = ProjectSettings(settings)
        let data = try JSONEncoder().encode(saved)
        let roundtrip = try JSONDecoder().decode(ProjectSettings.self, from: data).restored()
        precondition(roundtrip.transparentBackground)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "transparentBackground")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let restored = try JSONDecoder().decode(ProjectSettings.self, from: legacyData).restored()
        precondition(!restored.transparentBackground, "Old projects must stay opaque")
        print("PASS: transparent PNG, opaque screenshot, JPEG color flattening, project roundtrip and legacy project compatibility")
    }
}
