import AppKit

@main
struct DevicePositionChecks {
    static func main() throws {
        var settings = CompositionSettings()
        settings.showHeadline = true
        precondition(settings.deviceX == 0.5 && settings.deviceY == 0.54)
        settings.showHeadline = true
        precondition(settings.deviceY == 0.54, "Repeated enabling must not drift")
        settings.showHeadline = false
        precondition(settings.deviceY == 0.5)
        settings.deviceX = 0.4; settings.deviceY = 0.62
        settings.showHeadline = true; settings.showHeadline = false
        precondition(settings.deviceX == 0.4 && settings.deviceY == 0.62, "Headline must respect custom placement")
        settings.showHeadline = true; settings.resetDevicePosition()
        precondition(settings.deviceX == 0.5 && settings.deviceY == 0.54)
        settings.showHeadline = false; settings.resetDevicePosition()
        precondition(settings.deviceY == 0.5)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func context() -> CGContext {
            CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let shotContext = context()
        shotContext.setFillColor(NSColor.red.cgColor)
        shotContext.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        let shot = shotContext.makeImage()!
        let frameContext = context()
        frameContext.setFillColor(NSColor.green.cgColor)
        frameContext.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        frameContext.clear(CGRect(x: 10, y: 10, width: 80, height: 180))
        let frame = frameContext.makeImage()!
        let opening = ScreenOpening.detect(in: frame)!
        settings.preset = ScreenshotPreset(name: "Position test", width: 200, height: 400)
        settings.deviceScale = 0.8; settings.transparentBackground = true
        settings.manualScreen = true
        settings.screenX = 0.1; settings.screenY = 0.05
        settings.screenWidth = 0.8; settings.screenHeight = 0.9
        for framed in [false, true] {
            for manual in [false, true] {
                for fade in [false, true] {
                    settings.manualScreen = manual
                    settings.effects.deviceFade = fade
                    settings.deviceX = 0.5; settings.deviceY = 0.5
                    let base = try CompositionRenderer.render(screenshot: shot, mockup: framed ? frame : nil,
                                                              opening: opening, settings: settings)
                    settings.deviceX = 0.6; settings.deviceY = 0.6
                    let moved = try CompositionRenderer.render(screenshot: shot, mockup: framed ? frame : nil,
                                                               opening: opening, settings: settings)
                    let first = NSBitmapImageRep(cgImage: base), second = NSBitmapImageRep(cgImage: moved)
                    for (x, y) in [(25, 100), (100, 100), (100, 340), (25, 340)] {
                        let a = first.colorAt(x: x, y: y)!, b = second.colorAt(x: x + 20, y: y + 40)!
                        precondition(abs(a.alphaComponent - b.alphaComponent) < 0.01, "Mask/fade did not follow device")
                        precondition(abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01,
                                     "Frame and screenshot must translate together")
                    }
                }
            }
        }
        let full = CompositionRenderer.foregroundRect(screenshot: shot, mockup: frame, canvas: CGSize(width: 200, height: 400), settings: settings)
        let preview = CompositionRenderer.foregroundRect(screenshot: shot, mockup: frame, canvas: CGSize(width: 100, height: 200), settings: settings)
        precondition(abs(full.midX - preview.midX * 2) < 0.001 && abs(full.midY - preview.midY * 2) < 0.001)
        var saved = CompositionSettings()
        saved.deviceX = 0.3; saved.deviceY = 0.65
        let data = try JSONEncoder().encode(ProjectSettings(saved))
        let restored = try JSONDecoder().decode(ProjectSettings.self, from: data).restored()
        precondition(restored.deviceX == 0.3 && restored.deviceY == 0.65)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "deviceX"); legacy.removeValue(forKey: "deviceY")
        let old = try JSONDecoder().decode(ProjectSettings.self, from: JSONSerialization.data(withJSONObject: legacy)).restored()
        precondition(old.deviceX == 0.5 && old.deviceY == 0.5)
        print("PASS: headline headroom without drift, custom placement, reset, frame/screenshot/mask/fade translation, preview scaling and project compatibility")
    }
}
