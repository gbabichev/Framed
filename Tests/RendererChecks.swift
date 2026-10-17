// Run: swiftc Framed/ScreenshotPreset.swift Framed/CompositionRenderer.swift Tests/RendererChecks.swift -o /tmp/framed-checks && /tmp/framed-checks <mockup-folder> <screenshot-file>
import AppKit
import ImageIO

@main
struct RendererChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Provide mockup directory and screenshot path") }
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: args[1]), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.path < $1.path }
        let shot = try ImportedImage(url: URL(fileURLWithPath: args[2]))
        var sampleWritten = false
        for url in urls {
            let frame = try ImportedImage(url: url)
            let opening = ScreenOpening.detect(in: frame.image)
            print(url.lastPathComponent, opening.map { String(describing: $0.bounds) } ?? "Manual calibration needed")
            if url.lastPathComponent.contains("Outer Closed Portrait") {
                require(opening != nil, "Expected sample screen opening")
                var settings = CompositionSettings()
                settings.preset = ScreenshotPreset.all.first { $0.width == 1398 }!
                let output = try CompositionRenderer.render(screenshot: shot.image, mockup: frame.image, opening: opening, settings: settings)
                require(output.width == 1398 && output.height == 2034, "Incorrect output dimensions")
                for jpeg in [false, true] {
                    let data = try CompositionRenderer.encode(output, jpeg: jpeg)
                    let source = CGImageSourceCreateWithData(data as CFData, nil)!
                    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                    require(decoded.width == 1398 && decoded.height == 2034, "Encoding changed dimensions")
                    require([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(decoded.alphaInfo), "Export has alpha")
                    if !sampleWritten { try data.write(to: URL(fileURLWithPath: "/tmp/framed-sample.\(jpeg ? "jpg" : "png")")) }
                }
                sampleWritten = true
                settings.landscape = true
                let landscape = try CompositionRenderer.render(screenshot: shot.image, mockup: nil, opening: nil, settings: settings)
                require(landscape.width == 2034 && landscape.height == 1398, "Landscape dimensions")
            }
        }
        require(sampleWritten, "Did not test sample exports")
        try syntheticChecks()
        print("PASS: sample mockups, PNG/JPEG, dimensions, opacity, manual fallback, asymmetric screen geometry, and orientation")
    }

    static func syntheticChecks() throws {
        // Off-center opening catches vertical inversion; colored source halves catch image flips.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let frameContext = CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        frameContext.setFillColor(CGColor(gray: 0.2, alpha: 1)); frameContext.fill(CGRect(x: 0,y: 0,width: 200,height: 300))
        frameContext.clear(CGRect(x: 20, y: 150, width: 100, height: 120))
        let frame = frameContext.makeImage()!
        let opening = ScreenOpening.detect(in: frame)!
        require(abs(opening.bounds.minY - 0.1) < 0.01, "Screen origin must be top-left")
        let shotContext = CGContext(data: nil, width: 100, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        shotContext.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); shotContext.fill(CGRect(x: 0,y: 0,width: 100,height: 60))
        shotContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); shotContext.fill(CGRect(x: 0,y: 60,width: 100,height: 60))
        let shot = shotContext.makeImage()!
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset(name: "Test", width: 200, height: 300)
        settings.deviceScale = 1
        settings.background = .green
        let frameOnly = try CompositionRenderer.render(screenshot: nil, mockup: frame, opening: nil, settings: settings)
        let frameOnlyBitmap = NSBitmapImageRep(cgImage: frameOnly)
        require(frameOnlyBitmap.colorAt(x: 50, y: 50)!.greenComponent > 0.9,
                "Frame-only preview should reveal the canvas through the empty screen")
        require(frameOnlyBitmap.colorAt(x: 150, y: 100)!.redComponent < 0.3,
                "Frame-only preview should retain the bezel")
        settings.transparentBackground = true
        let transparentFrame = try CompositionRenderer.render(screenshot: nil, mockup: frame, opening: nil, settings: settings)
        require(NSBitmapImageRep(cgImage: transparentFrame).colorAt(x: 50, y: 50)!.alphaComponent < 0.01,
                "Frame-only preview should preserve an empty transparent screen")
        settings.transparentBackground = false
        let output = try CompositionRenderer.render(screenshot: shot, mockup: frame, opening: opening, settings: settings)
        let bitmap = NSBitmapImageRep(cgImage: output)
        let top = bitmap.colorAt(x: 50, y: 50)!.usingColorSpace(.deviceRGB)!
        let bottom = bitmap.colorAt(x: 50, y: 130)!.usingColorSpace(.deviceRGB)!
        require(top.redComponent > 0.9 && bottom.blueComponent > 0.9, "Screenshot or mask inverted")
        let outside = bitmap.colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!
        let reference = NSBitmapImageRep(cgImage: frame).colorAt(x: 150, y: 100)!.usingColorSpace(.deviceRGB)!
        require(abs(outside.redComponent - reference.redComponent) < 0.02, "Screenshot leaked beyond screen")
        settings.manualScreen = true
        settings.screenX = 0.1; settings.screenY = 0.1; settings.screenWidth = 0.5; settings.screenHeight = 0.4
        settings.cornerRadius = 0
        let manual = try CompositionRenderer.render(screenshot: shot, mockup: frame, opening: nil, settings: settings)
        let manualTop = NSBitmapImageRep(cgImage: manual).colorAt(x: 50, y: 50)!.usingColorSpace(.deviceRGB)!
        require(manualTop.redComponent > 0.9, "Manual fallback geometry")
        settings.manualScreen = false
        do {
            _ = try CompositionRenderer.render(screenshot: shot, mockup: frame, opening: nil, settings: settings)
            fatalError("Uncalibrated mockup should fail")
        } catch is FramedError { }
    }
}
