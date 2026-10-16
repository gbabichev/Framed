import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers

nonisolated struct SavedFrame: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let width: Int
    let height: Int
    let digest: String
    let thumbnail: CGImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.digest == rhs.digest
    }
}

nonisolated enum FrameImportSource: Sendable {
    case file(URL)
    case image(ImportedImage)
    var name: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .image(let image): image.name
        }
    }
}

@Observable
final class FrameLibrary {
    static let shared = FrameLibrary()
    let directory: URL
    private(set) var frames: [SavedFrame] = []
    var error: String?


    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Framed/Frames", isDirectory: true)
        reload()
    }

    func reload() {
        error = nil
        guard FileManager.default.fileExists(atPath: directory.path) else { frames = []; return }
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            var loaded: [SavedFrame] = []
            var failures = 0
            for folder in folders {
                do {
                    let metadata = try JSONDecoder().decode(FrameMetadata.self, from: Data(contentsOf: folder.appendingPathComponent("metadata.json")))
                    guard metadata.version == 1, folder.lastPathComponent == metadata.id.uuidString,
                          !metadata.name.isEmpty, metadata.width > 0, metadata.height > 0,
                          FileManager.default.fileExists(atPath: folder.appendingPathComponent("frame.png").path) else {
                        throw FramedError.message("Invalid frame library entry.")
                    }
                    let thumbnailURL = folder.appendingPathComponent("thumbnail.png")
                    let source = CGImageSourceCreateWithURL(thumbnailURL as CFURL, nil)
                        ?? CGImageSourceCreateWithURL(folder.appendingPathComponent("frame.png") as CFURL, nil)
                    guard let source, let thumbnail = FrameFileWorker.thumbnail(source) else { throw FramedError.message("Invalid frame preview.") }
                    loaded.append(SavedFrame(id: metadata.id, name: metadata.name, width: metadata.width,
                                             height: metadata.height, digest: metadata.digest, thumbnail: thumbnail))
                } catch { failures += 1 }
            }
            frames = sorted(loaded)
            if failures > 0 { error = "Couldn’t load \(failures) frame(s). Their files remain in the frame library folder." }
        } catch { self.error = "Couldn’t read the frame library. \(error.localizedDescription)" }
    }

    private(set) var isImporting = false
    private(set) var importTotal = 0
    private(set) var importCompleted = 0
    private(set) var importFilename = ""
    private(set) var isCancellingImport = false

    func markImportCancelling() { isCancellingImport = true }

    func importFiles(_ urls: [URL]) async -> [SavedFrame] {
        await importSources(urls.map { .file($0) })
    }

    func importSources(_ sources: [FrameImportSource]) async -> [SavedFrame] {
        guard !isImporting else { return [] }
        isImporting = true
        isCancellingImport = false
        importTotal = sources.count
        importCompleted = 0
        error = nil
        var imported: [SavedFrame] = []
        var failures: [String] = []
        defer { isImporting = false; importFilename = "" }
        for source in sources {
            if Task.isCancelled { break }
            importFilename = source.name
            do {
                let frame = try await FrameFileWorker.importSource(source, directory: directory, frames: frames)
                // A file committed before cancellation must still appear in the library.
                publish(frame)
                imported.append(frame)
            } catch is CancellationError { break }
            catch { failures.append("\(source.name): \(error.localizedDescription)") }
            importCompleted += 1
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
        return imported
    }

    @discardableResult
    func store(_ image: ImportedImage) throws -> SavedFrame {
        guard !isImporting else { throw FramedError.message("Wait for the frame import to finish.") }
        let frame = try FrameFileWorker.store(image, directory: directory, frames: frames)
        publish(frame)
        return frame
    }

    private func publish(_ frame: SavedFrame) {
        if !frames.contains(where: { $0.id == frame.id }) { frames = sorted(frames + [frame]) }
    }

    func matching(_ image: ImportedImage) throws -> SavedFrame? {
        let digest = FrameFileWorker.digest(try ProjectImage(image).png)
        return frames.first { $0.digest == digest }
    }

    func image(for frame: SavedFrame) throws -> ImportedImage {
        try FrameFileWorker.image(for: frame, directory: directory)
    }

    func rename(_ frame: SavedFrame, to proposedName: String) throws {
        guard !isImporting else { throw FramedError.message("Wait for the frame import to finish.") }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FramedError.message("Enter a name for this frame.") }
        guard frames.contains(where: { $0.id == frame.id }) else { return }
        let metadata = FrameMetadata(id: frame.id, name: name, width: frame.width, height: frame.height, digest: frame.digest)
        try JSONEncoder().encode(metadata).write(to: folder(frame.id).appendingPathComponent("metadata.json"), options: .atomic)
        frames = sorted(frames.map { $0.id == frame.id ? SavedFrame(id: frame.id, name: name, width: frame.width, height: frame.height, digest: frame.digest, thumbnail: frame.thumbnail) : $0 })
    }

    func remove(_ frame: SavedFrame) throws {
        guard !isImporting else { throw FramedError.message("Wait for the frame import to finish.") }
        // This removes only the reusable copy; each open/saved project owns its images.
        try FileManager.default.removeItem(at: folder(frame.id))
        frames.removeAll { $0.id == frame.id }
    }

    private func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func sorted(_ frames: [SavedFrame]) -> [SavedFrame] {
        frames.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

nonisolated struct FrameMetadata: Codable, Sendable {
    var version = 1
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    var digest: String
}

/// File and image work is independent of the observable, main-actor library.
nonisolated enum FrameFileWorker {
    @concurrent
    static func importSource(_ source: FrameImportSource, directory: URL, frames: [SavedFrame]) async throws -> SavedFrame {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image: ImportedImage
            switch source {
            case .file(let url): image = try ImportedImage(url: url)
            case .image(let existing): image = existing
            }
            return try store(image, directory: directory, frames: frames)
        }
    }

    @concurrent
    static func prepare(_ frame: SavedFrame, directory: URL) async throws -> (ImportedImage, ScreenOpening?) {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image = try image(for: frame, directory: directory)
            return (image, ScreenOpening.detect(in: image.image))
        }
    }

    static func store(_ image: ImportedImage, directory: URL, frames: [SavedFrame]) throws -> SavedFrame {
        func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
        try Task.checkCancellation()
        let data = try ProjectImage(image).png
        try Task.checkCancellation()
        let digest = Self.digest(data)
        if let existing = frames.first(where: { $0.digest == digest }) {
            // Repair a missing asset from the newly imported or project-embedded copy.
            let url = folder(existing.id).appendingPathComponent("frame.png")
            if (try? Data(contentsOf: url)).map({ Self.digest($0) }) != digest {
                try data.write(to: url, options: .atomic)
            }
            return existing
        }
        let id = frames.contains(where: { $0.id == image.id }) ? UUID() : image.id
        let metadata = FrameMetadata(id: id, name: image.name, width: image.image.width, height: image.image.height, digest: digest)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let thumbnail = Self.thumbnail(source) else {
            throw FramedError.message("Couldn’t create a preview for \(image.name).")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".importing-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging.appendingPathComponent("frame.png"), options: .atomic)
        try JSONEncoder().encode(metadata).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
        try ProjectImage(ImportedImage(id: id, name: image.name, image: thumbnail)).png
            .write(to: staging.appendingPathComponent("thumbnail.png"), options: .atomic)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: folder(id))
        let frame = SavedFrame(id: id, name: image.name, width: image.image.width,
                               height: image.image.height, digest: digest, thumbnail: thumbnail)
        return frame
    }

    static func image(for frame: SavedFrame, directory: URL) throws -> ImportedImage {
        let data = try Data(contentsOf: directory.appendingPathComponent(frame.id.uuidString).appendingPathComponent("frame.png"))
        guard Self.digest(data) == frame.digest else { throw FramedError.message("The stored frame ‘\(frame.name)’ is damaged. Import it again to repair it.") }
        return try ProjectImage(id: frame.id, name: frame.name, png: data).restored()
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func thumbnail(_ source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                                       kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary)
    }
}
