import AppKit

@main
struct MaskEdgeChecks {
    static func main() throws {
        let width = 1600, height = 3200
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let frameContext = context(width, height)
        frameContext.setFillColor(CGColor(gray: 0, alpha: 1))
        frameContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        frameContext.setBlendMode(.clear)
        frameContext.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 1400, height: 3000),
                                    cornerWidth: 220.3, cornerHeight: 220.3, transform: nil))
        frameContext.fillPath()
        frameContext.setBlendMode(.normal)
        frameContext.fillEllipse(in: CGRect(x: 650.3, y: 2900.7, width: 299.4, height: 110.6))
        let frame = frameContext.makeImage()!
        let opening = ScreenOpening.detect(in: frame)!
        precondition(opening.mask.width == width && opening.mask.height == height, "Export mask lost source resolution")
        let shotContext = context(1400, 3000)
        shotContext.setFillColor(CGColor(gray: 1, alpha: 1))
        shotContext.fill(CGRect(x: 0, y: 0, width: 1400, height: 3000))
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset(name: "Edge test", width: width, height: height)
        settings.deviceScale = 1
        settings.fillScreen = true
        let output = try CompositionRenderer.render(screenshot: shotContext.makeImage()!, mockup: frame,
                                                     opening: opening, settings: settings)
        let renderedContext = context(width, height)
        renderedContext.draw(output, in: CGRect(x: 0, y: 0, width: width, height: height))
        let source = frameContext.data!.assumingMemoryBound(to: UInt8.self)
        let rendered = renderedContext.data!.assumingMemoryBound(to: UInt8.self)
        var samples = 0
        for y in 110..<500 {
            for x in 110..<1490 {
                let index = (y * width + x) * 4
                let alpha = Int(source[index + 3])
                if alpha > 0 && alpha < 255 {
                    // White screenshot beneath black antialiased bezel/camera artwork.
                    let expected = 255 - alpha
                    precondition(abs(Int(rendered[index]) - expected) <= 3,
                                 "Clipping damaged source antialiasing at \(x),\(y): \(rendered[index]) vs \(expected)")
                    samples += 1
                }
            }
        }
        precondition(samples > 100, "Expected curved edge and camera antialias samples")
        print("PASS: source-resolution mask and \(samples) antialiased corner/camera pixels without hard clipping seams")
    }
}
