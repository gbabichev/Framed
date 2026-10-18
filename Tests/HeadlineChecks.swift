import AppKit

@main
struct HeadlineChecks {
    static func main() throws {
        var headline = HeadlineSettings()
        let canvas = CGSize(width: 800, height: 1600)
        precondition(HeadlineRenderer.layout(headline, canvas: canvas) == nil)
        headline.enabled = true
        headline.firstLine = "Build something"
        headline.secondLine = "worth sharing"
        headline.color = .blue
        headline.y = 0.15
        let layout = HeadlineRenderer.layout(headline, canvas: canvas)!
        precondition(layout.lines.count == 2 && layout.rect.minY > 0)
        var equalText = headline
        equalText.firstLine = "Matching text"; equalText.secondLine = "Matching text"
        let proportional = HeadlineRenderer.layout(equalText, canvas: canvas)!
        precondition(abs(proportional.widths[1] / proportional.widths[0] - 0.75) < 0.01,
                     "Subheadline must render at 75% of the main headline size")
        equalText.firstLine = ""
        let subheadlineOnly = HeadlineRenderer.layout(equalText, canvas: canvas)!
        precondition(abs(subheadlineOnly.widths[0] - proportional.widths[1]) < 0.01,
                     "An empty main headline must not promote the subheadline to full size")
        let half = HeadlineRenderer.layout(headline, canvas: CGSize(width: 400, height: 800))!
        precondition(abs(half.rect.midX * 2 - layout.rect.midX) < 0.01 && abs(half.rect.height * 2 - layout.rect.height) < 0.01,
                     "Preview and export text geometry must scale consistently")
        headline.x = 0; headline.y = 1
        let clamped = HeadlineRenderer.layout(headline, canvas: canvas)!
        precondition(clamped.rect.minX >= 0 && clamped.rect.maxY <= canvas.height)
        headline.firstLineInput = "a\nb\rc"
        precondition(headline.firstLine == "a b c")
        headline.secondLineInput = String(repeating: "x", count: 300)
        precondition(headline.secondLine.count == 200)
        let truncated = HeadlineRenderer.layout(headline, canvas: canvas)!
        precondition(truncated.lines.count == 2 && truncated.rect.width <= canvas.width * 0.9 + 0.001)
        headline.secondLine = ""
        precondition(HeadlineRenderer.layout(headline, canvas: canvas)!.lines.count == 1)
        headline.firstLine = " "
        precondition(HeadlineRenderer.layout(headline, canvas: canvas) == nil)

        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset(name: "Headline test", width: 800, height: 1600)
        settings.deviceScale = 0.4
        settings.transparentBackground = true
        headline.firstLine = "Build something"; headline.secondLine = "worth sharing"
        headline.x = 0.5; headline.y = 0.15
        settings.headline = headline
        let shotContext = CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        shotContext.setFillColor(NSColor.red.cgColor)
        shotContext.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        let output = try CompositionRenderer.render(screenshot: shotContext.makeImage()!, mockup: nil, opening: nil, settings: settings)
        let bitmap = NSBitmapImageRep(cgImage: output)
        let expected = HeadlineRenderer.layout(headline, canvas: canvas)!
        var topPixels = 0, bottomPixels = 0
        for y in Int(expected.rect.minY)..<Int(ceil(expected.rect.maxY)) {
            for x in Int(expected.rect.minX)..<Int(ceil(expected.rect.maxX)) {
                let color = bitmap.colorAt(x: x, y: y)!
                if color.alphaComponent > 0.5 {
                    precondition(color.blueComponent > 0.9 && color.redComponent < 0.1, "Text color incorrect")
                    if CGFloat(y) < expected.rect.midY { topPixels += 1 } else { bottomPixels += 1 }
                }
            }
        }
        precondition(topPixels > 100 && bottomPixels > 100, "Both lines must render upright in their layout bounds")
        var persisted = CompositionSettings()
        persisted.headline = headline
        persisted.headline.fontFamily = "Helvetica"
        persisted.headline.weight = .semibold
        persisted.headlineFontSize = 72
        let data = try JSONEncoder().encode(ProjectSettings(persisted))
        let restored = try JSONDecoder().decode(ProjectSettings.self, from: data).restored()
        precondition(restored.headline == persisted.headline)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "headline")
        let old = try JSONDecoder().decode(ProjectSettings.self, from: JSONSerialization.data(withJSONObject: legacy)).restored()
        precondition(!old.headline.enabled)
        var invalid = ProjectSettings(persisted)
        invalid.headline!.firstLine = "a\nb"
        do { _ = try invalid.restored(); fatalError("Multiline field accepted") } catch is FramedError { }
        print("PASS: two-line layout, preview scaling, canvas bounds, input cleanup, text pixels/color, fonts and project compatibility")
    }
}
