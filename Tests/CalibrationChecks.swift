import AppKit

@main
struct CalibrationChecks {
    static func main() throws {
        var settings = CompositionSettings()
        settings.screenX = 0.05; settings.screenWidth = 0.9
        let originalRight = settings.screenRight
        settings.screenLeft = 0.43
        precondition(abs(settings.screenRight - originalRight) < 0.000001, "Moving left must keep the right edge fixed")
        precondition(abs(settings.screenWidth - 0.52) < 0.000001, "Displayed width must equal the rendered width")
        settings.screenRight = 2
        precondition(settings.screenRight == 1, "Right edge escaped frame")
        settings.screenLeft = 1
        precondition(abs(settings.screenLeft - 0.9) < 0.000001)
        settings.screenRight = 0
        precondition(abs(settings.manualBounds.width - 0.1) < 0.000001, "Edges crossed")
        settings.screenTop = -1; settings.screenBottom = 2
        precondition(settings.screenTop == 0 && settings.screenBottom == 1)
        settings.screenTop = 2; settings.screenBottom = 0
        precondition(abs(settings.manualBounds.height - 0.1) < 0.000001)
        for value in stride(from: -0.2, through: 1.2, by: 0.01) {
            settings.screenLeft = value; settings.screenRight = 1 - value
            settings.screenTop = value; settings.screenBottom = 1 - value
            let bounds = settings.manualBounds
            precondition(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 1.000001 && bounds.maxY <= 1.000001)
            precondition(bounds.width >= 0.099999 && bounds.height >= 0.099999)
            precondition(abs(bounds.width - settings.screenWidth) < 0.000001, "Width silently clamped")
            _ = try ProjectSettings(settings).restored()
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CalibrationChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        context.clear(CGRect(x: 10, y: 20, width: 180, height: 260))
        let frame = ImportedImage(id: UUID(), name: "Test", image: context.makeImage()!)
        let library = FrameLibrary(directory: directory)
        let saved = try library.store(frame)
        let model = EditorModel(frameLibrary: library)
        precondition(model.useLibraryFrame(saved))
        let detected = model.opening!.bounds
        model.manualCalibrationEnabled = true
        precondition(model.settings.manualScreen && model.settings.manualBounds == detected)
        model.settings.screenLeft = 0.4
        model.resetScreenCalibration()
        precondition(!model.settings.manualScreen && model.settings.manualBounds == detected)
        let path = directory.appendingPathComponent("Calibration.framed")
        precondition(model.writeProject(to: path))
        model.manualCalibrationEnabled = true
        precondition(model.isDirty, "Manual calibration must dirty project")
        model.resetScreenCalibration()
        precondition(!model.isDirty, "Reset should restore saved automatic state")
        print("PASS: independent edges, clamping, minimum area, saveable settings, detected starting bounds, reset, dirty state")
    }
}
