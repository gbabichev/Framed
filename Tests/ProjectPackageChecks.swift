import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct ProjectPackageChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PackageChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 80, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 80, height: 160))
        let jpeg = NSMutableData()
        let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let sourceURL = root.appendingPathComponent("Original photo.jpg")
        try (jpeg as Data).write(to: sourceURL)
        let frameURL = root.appendingPathComponent("Original frame.png")
        context.clear(CGRect(x: 8, y: 12, width: 64, height: 136))
        let frameBytes = try CompositionRenderer.encode(context.makeImage()!, jpeg: false)
        try frameBytes.write(to: frameURL)
        let library = FrameLibrary(directory: root.appendingPathComponent("Library"))
        let model = EditorModel(frameLibrary: library)
        model.load([sourceURL], asMockups: false)
        let shot = model.selectedScreenshot!
        precondition(shot.sourceData == jpeg as Data && shot.image.width == 160 && shot.image.height == 80)
        let frame = try library.store(ImportedImage(url: frameURL))
        try library.rename(frame, to: "Renamed frame")
        let usedFrame = await model.useLibraryFrameInBackground(library.frames[0])
        precondition(usedFrame)
        precondition(model.selectedMockup?.sourceData == frameBytes && model.selectedMockup?.sourceFilename == frameURL.lastPathComponent)
        model.duplicateScreenshot(shot.id)
        let projectURL = root.appendingPathComponent("Originals.framed")
        precondition(model.writeProject(to: projectURL))
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        let manifestURL = projectURL.appendingPathComponent("project.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let object = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        let metadata = object["project"] as! [String: Any]
        let shots = metadata["screenshots"] as! [[String: Any]]
        precondition(shots.allSatisfy { $0["png"] == nil && $0["file"] != nil }, "Manifest must not embed Base64 image data")
        let shotPath = shots[0]["file"] as! String
        precondition(shots[1]["file"] as! String == shotPath, "Duplicate screenshots must share one asset")
        let assetURL = projectURL.appendingPathComponent(shotPath)
        let firstAssetBytes = try Data(contentsOf: assetURL)
        precondition(firstAssetBytes == jpeg as Data, "Original JPEG bytes must be unchanged")
        let screenshotFiles = try FileManager.default.contentsOfDirectory(atPath: projectURL.appendingPathComponent("Screenshots").path)
        precondition(screenshotFiles.count == 1)
        let assetDate = try assetURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let reopened = EditorModel(frameLibrary: library)
        try reopened.restoreProject(FramedProject.read(from: projectURL), at: projectURL)
        precondition(reopened.screenshots[0].image.width == 160 && reopened.screenshots[0].image.height == 80,
                     "EXIF orientation must survive package save/open")
        precondition(reopened.screenshots[0].sourceFilename == sourceURL.lastPathComponent && !reopened.isDirty)
        try FileManager.default.removeItem(at: sourceURL); try FileManager.default.removeItem(at: frameURL)
        reopened.settings.deviceScale = 0.7
        precondition(reopened.writeProject(to: projectURL), "Replacement package save must succeed")
        let savedAssetBytes = try Data(contentsOf: assetURL)
        precondition(savedAssetBytes == jpeg as Data)
        let savedDate = try assetURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        precondition(savedDate == assetDate,
                     "Layout saves should reuse unchanged asset files")
        var failedSave = try reopened.makeProject()
        failedSave.screenshots[0].png = Data()
        do { try failedSave.write(to: projectURL); fatalError("Empty asset save accepted") } catch is FramedError { }
        let afterFailure = try FramedProject.read(from: projectURL)
        precondition(afterFailure.screenshots[0].png == jpeg as Data,
                     "A failed replacement must leave the previous package intact")
        let portableURL = root.appendingPathComponent("Portable.framed")
        precondition(reopened.writeProject(to: portableURL), "Save As must copy all originals without their source files")
        let portable = try FramedProject.read(from: portableURL)
        precondition(portable.screenshots[0].png == jpeg as Data && portable.mockups[0].png == frameBytes)
        let legacyURL = root.appendingPathComponent("Legacy.framed")
        var legacy = try reopened.makeProject()
        legacy.screenshots = try legacy.screenshots.map { record in
            let image = try record.restored()
            return try ProjectImage(ImportedImage(id: image.id, name: image.name, image: image.image))
        }
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let legacyBytes = try Data(contentsOf: legacyURL)
        let legacyRead = try FramedProject.read(from: legacyURL)
        try legacyRead.write(to: legacyURL)
        isDirectory = false
        precondition(FileManager.default.fileExists(atPath: legacyURL.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                     "Saving an old JSON project must atomically replace it with a package")
        let convertedLegacy = try FramedProject.read(from: legacyURL)
        precondition(convertedLegacy.screenshots[0].png == legacyRead.screenshots[0].png)
        precondition(!legacyBytes.isEmpty)
        var malicious = object
        var badMetadata = metadata
        var badShots = shots
        badShots[0]["file"] = "../outside.jpg"
        badMetadata["screenshots"] = badShots; malicious["project"] = badMetadata
        try JSONSerialization.data(withJSONObject: malicious).write(to: manifestURL)
        do { _ = try FramedProject.read(from: projectURL); fatalError("Escaping asset path accepted") } catch is FramedError { }
        try manifestData.write(to: manifestURL)
        try Data("corrupted".utf8).write(to: assetURL)
        do { _ = try FramedProject.read(from: projectURL); fatalError("Damaged asset accepted") } catch is FramedError { }
        model.releaseProjectAccess(); reopened.releaseProjectAccess()
        print("PASS: original JPEG/PNG bytes and names, EXIF orientation, frame library preservation, compact manifest, deduplication, replacement/Save As, unchanged asset reuse, legacy conversion, path validation and corruption detection")
    }
}
