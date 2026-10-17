import AppKit

@main struct FrameFilterChecks {
    static func main() throws {
        let examples: [(String, FrameDeviceFamily?)] = [
            ("Apple Watch S11 - 42mm - Titanium Gold + Milanese Loop", .watch),
            ("AW Ultra 3 - Natural + Milanese Loop", .watch),
            ("  apple watch s11 - Silver.png ", .watch),
            ("iPhone Duo - Night Sky - Outer Open", .iPhone),
            ("iPhone Air - Light Gold - Portrait", .iPhone),
            ("iPad Air 13\" (M4) - Purple - Portrait", .iPad),
            ("MacBook Neo - Citrus", .mac), ("iMac - Blue", .mac), ("Mac Studio", .mac),
            ("Apple TV - 4K", nil), ("Custom bezel", nil), ("Macaron", nil)
        ]
        for (name, expected) in examples { precondition(FrameDeviceFamily.detect(in: name) == expected, name) }
        let context = CGContext(data: nil, width: 10, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        let image = context.makeImage()!
        let frames = examples.map { SavedFrame(id: UUID(), name: $0.0, width: 10, height: 20, digest: UUID().uuidString, thumbnail: image) }
        precondition(SavedFrame.filtered(frames, family: nil, search: "").count == examples.count)
        let watches = SavedFrame.filtered(frames, family: .watch, search: " ULTRA ")
        precondition(watches.count == 1 && watches[0].name.hasPrefix("AW Ultra"))
        precondition(SavedFrame.filtered(frames, family: .mac, search: "Portrait").isEmpty)
        precondition(SavedFrame.filtered(frames, family: .iPad, search: "purple").count == 1)
        var selection = FrameSelection()
        selection.selectAll(frames.map(\.id))
        selection.retain(Set(watches.map(\.id)))
        precondition(selection.ids == Set(watches.map(\.id)), "Hidden frames must not remain selected for deletion")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FrameFilterChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root)
        let watch = try library.store(ImportedImage(id: UUID(), name: "AW Ultra 3 - Natural", image: image))
        let model = EditorModel(frameLibrary: library)
        let baseline = model.fingerprint
        try library.rename(watch, to: "Marketing hero")
        let reloaded = FrameLibrary(directory: root)
        precondition(reloaded.frames.first?.family == .watch && reloaded.frames.first?.name == "Marketing hero",
                     "Renaming must preserve imported family across launches")
        let metadataURL = root.appendingPathComponent(watch.id.uuidString).appendingPathComponent("metadata.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
        legacy.removeValue(forKey: "family"); legacy["name"] = "iPad Pro - Silver"
        try JSONSerialization.data(withJSONObject: legacy).write(to: metadataURL)
        let migrated = FrameLibrary(directory: root)
        precondition(migrated.frames.first?.family == .iPad, "Existing library metadata must infer a family")
        try migrated.rename(migrated.frames[0], to: "Tablet hero")
        precondition(FrameLibrary(directory: root).frames.first?.family == .iPad)
        precondition(model.fingerprint == baseline && !model.isDirty && !model.canUndo)
        if let folder = CommandLine.arguments.dropFirst().first {
            let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
            let catalog = urls.map { SavedFrame(id: UUID(), name: $0.deletingPathExtension().lastPathComponent, width: 10, height: 20, digest: "test", thumbnail: image) }
            var covered = 0
            for family in FrameDeviceFamily.allCases {
                let count = SavedFrame.filtered(catalog, family: family, search: "").count
                covered += count
                print("\(family.title): \(count)")
            }
            let unmatched = catalog.filter { $0.family == nil }
            precondition(unmatched.allSatisfy { $0.name.hasPrefix("Apple TV") }, "An Apple device filename was missed")
            precondition(SavedFrame.filtered(catalog, family: nil, search: "").count == urls.count)
            print("Catalog: \(covered)/\(urls.count) categorized; \(unmatched.count) other frames available in All")
        }
        print("PASS: family detection, AW Ultra names, search intersection, visible selection, rename persistence, legacy metadata, unknown names, and dirty/undo isolation")
    }
}
