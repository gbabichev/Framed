import AppKit

@main
struct FrameBulkChecks {
    @MainActor
    static func main() async throws {
        let ids = (0..<6).map { _ in UUID() }
        var selection = FrameSelection()
        selection.select(ids[1], visible: ids, toggle: false, extend: false)
        selection.select(ids[3], visible: ids, toggle: true, extend: false)
        precondition(selection.ids == [ids[1], ids[3]], "Toggle selection")
        selection.select(ids[1], visible: ids, toggle: true, extend: false)
        precondition(selection.ids == [ids[3]], "Toggle deselection")
        selection.select(ids[1], visible: ids, toggle: false, extend: false)
        selection.select(ids[4], visible: ids, toggle: false, extend: true)
        precondition(selection.ids == Set(ids[1...4]), "Shift range")
        selection.selectAll([ids[0], ids[5]])
        precondition(selection.ids == [ids[0], ids[5]], "Filtered select-all included hidden IDs")
        selection.retain([ids[5]])
        precondition(selection.ids == [ids[5]], "Stale selections retained")
        selection.clear()
        precondition(selection.ids.isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FrameBulkChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FrameLibrary(directory: root)
        for n in 0..<5 {
            let context = CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: CGFloat(n + 1) / 6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            context.clear(CGRect(x: 10, y: 10, width: 180, height: 280))
            try library.store(ImportedImage(id: UUID(), name: "Frame \(n)", image: context.makeImage()!))
        }
        let originals = library.frames
        let model = EditorModel(frameLibrary: library)
        precondition(model.useLibraryFrame(originals[0]))
        let fingerprint = model.fingerprint
        await library.removeFrames([originals[0].id, originals[2].id])
        precondition(library.frames.count == 3 && model.fingerprint == fingerprint && model.selectedMockup != nil,
                     "Bulk deletion lost project data")
        precondition(FrameLibrary(directory: root).frames.count == 3, "Bulk removal did not persist")
        precondition(!library.isRemoving)
        let remaining = library.frames
        // An already-missing directory is treated as removed, so stale entries can be cleaned up.
        try FileManager.default.removeItem(at: root.appendingPathComponent(remaining[0].id.uuidString))
        await library.removeFrames([remaining[0].id, UUID()])
        precondition(library.frames.count == 2, "Stale/unknown removal IDs mishandled")
        await library.removeFrames(Set(library.frames.map(\.id)))
        precondition(library.frames.isEmpty && FrameLibrary(directory: root).frames.isEmpty, "Remove all not durable")
        precondition(model.selectedMockup != nil && model.fingerprint == fingerprint, "Remove all changed current canvas")
        print("PASS: toggle/range/filter selection, stale selection cleanup, bulk removal, remove all, durability and project independence")
    }
}
