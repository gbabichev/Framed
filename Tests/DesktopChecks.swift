import AppKit

@main
struct DesktopChecks {
    static func main() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func context(_ width: Int, _ height: Int) -> CGContext {
            CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        let frameContext = context(400, 300)
        frameContext.setFillColor(CGColor(gray: 0.2, alpha: 1))
        frameContext.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        frameContext.clear(CGRect(x: 20, y: 20, width: 360, height: 260))
        let frame = frameContext.makeImage()!, opening = ScreenOpening.detect(in: frame)!
        let windowContext = context(100, 100)
        windowContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        windowContext.fill(CGRect(x: 10, y: 10, width: 80, height: 80))
        let window = windowContext.makeImage()!
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset(name: "Test", width: 400, height: 300)
        settings.deviceScale = 1
        settings.desktop.enabled = true
        settings.desktop.shadow = false
        settings.desktop.windowScale = 0.5
        func render() throws -> NSBitmapImageRep {
            NSBitmapImageRep(cgImage: try CompositionRenderer.render(screenshot: window, mockup: frame,
                opening: opening, settings: settings))
        }
        let bitmap = try render()
        let wallpaper = bitmap.colorAt(x: 50, y: 50)!
        precondition(wallpaper.blueComponent > 0.5, "Desktop must replace black bars")
        precondition(bitmap.colorAt(x: 200, y: 150)!.redComponent > 0.95, "Window must remain centered")
        precondition(bitmap.colorAt(x: 138, y: 150)!.blueComponent > 0.5, "Transparent image padding must reveal wallpaper")
        precondition(bitmap.colorAt(x: 5, y: 5)!.redComponent < 0.3, "Wallpaper must stay inside bezel")
        settings.desktop.windowX = 0; settings.desktop.windowY = 0
        let moved = try render()
        precondition(moved.colorAt(x: 85, y: 85)!.redComponent > 0.95, "Window must move toward top-left")
        settings.desktop.enabled = false
        let disabled = try render()
        precondition(disabled.colorAt(x: 50, y: 50)!.blueComponent < 0.01, "Disabling must retain original black screen behavior")
        settings.preset = ScreenshotPreset.all[0]
        settings.desktop.enabled = true
        settings.desktop.shadow = true
        let data = try JSONEncoder().encode(ProjectSettings(settings))
        let restored = try JSONDecoder().decode(ProjectSettings.self, from: data).restored()
        precondition(restored.desktop == settings.desktop, "Desktop settings must survive save/open")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "desktop")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacySettings = try JSONDecoder().decode(ProjectSettings.self, from: legacyData).restored()
        precondition(legacySettings.desktop.enabled == false,
                     "Old projects must default to no desktop")
        // Optional real-image sample: pass a screenshot path and a frame path.
        if CommandLine.arguments.count == 3 {
            let shot = try ImportedImage(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            let mac = try ImportedImage(url: URL(fileURLWithPath: CommandLine.arguments[2]))
            settings.preset = ScreenshotPreset.all.first { $0.width == 2560 && $0.height == 1600 }!
            settings.desktop.windowScale = 0.85; settings.desktop.windowX = 0.5; settings.desktop.windowY = 0.5
            let sample = try CompositionRenderer.render(screenshot: shot.image, mockup: mac.image,
                opening: ScreenOpening.detect(in: mac.image), settings: settings)
            try CompositionRenderer.encode(sample, jpeg: false).write(to: URL(fileURLWithPath: "/tmp/framed-desktop-sample.png"))
        }
        print("PASS: wallpaper, transparency, clipping, positioning, legacy rendering, project round-trip and migration")
    }
}
