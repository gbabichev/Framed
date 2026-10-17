import AppKit
import CryptoKit
import ImageIO
import Observation
import UniformTypeIdentifiers

nonisolated enum FrameDeviceFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case watch, iPhone, iPad, mac
    var id: Self { self }
    var title: String {
        switch self {
        case .watch: "Watch"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }
    static func detect(in name: String) -> Self? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return nil }
        if first == "watch" || first == "aw" || (first == "apple" && words.dropFirst().first == "watch") { return .watch }
        if first == "iphone" { return .iPhone }
        if first == "ipad" { return .iPad }
        if ["mac", "macbook", "imac"].contains(first) { return .mac }
        return nil
    }
}

nonisolated struct SavedFrame: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let width: Int
    let height: Int
    let digest: String
    let thumbnail: CGImage
    let family: FrameDeviceFamily?

    init(id: UUID, name: String, width: Int, height: Int, digest: String, thumbnail: CGImage,
         family: FrameDeviceFamily? = nil) {
        self.id = id; self.name = name; self.width = width; self.height = height
        self.digest = digest; self.thumbnail = thumbnail
        self.family = family ?? FrameDeviceFamily.detect(in: name)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.digest == rhs.digest && lhs.family == rhs.family
    }

    static func filtered(_ frames: [Self], family: FrameDeviceFamily?, search: String) -> [Self] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return frames.filter { (family == nil || $0.family == family) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
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

nonisolated final class PreparedFrame: Sendable {
    let image: ImportedImage
    let opening: ScreenOpening?
    init(image: ImportedImage, opening: ScreenOpening?) { self.image = image; self.opening = opening }
    var memoryCost: Int {
        image.image.bytesPerRow * image.image.height + (opening.map { $0.mask.bytesPerRow * $0.mask.height } ?? 0)
    }
}

@Observable
final class FrameLibrary {
    static let shared = FrameLibrary()
    let directory: URL
    private(set) var frames: [SavedFrame] = []
    var error: String?

    private struct PreparationKey: Hashable, Sendable {
        let id: UUID
        let digest: String
        var cacheKey: NSString { "\(id.uuidString)-\(digest)" as NSString }
    }
    private struct PreparationJob {
        let token = UUID()
        let task: Task<PreparedFrame, Error>
        var clients: Set<UUID> = []
    }
    @ObservationIgnored private let preparedFrames = NSCache<NSString, PreparedFrame>()
    @ObservationIgnored private var preparationJobs: [PreparationKey: PreparationJob] = [:]


    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Framed/Frames", isDirectory: true)
        preparedFrames.countLimit = 3
        preparedFrames.totalCostLimit = 128 * 1024 * 1024
        reload()
    }

    func reload() {
        invalidatePreparation()
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
                                             height: metadata.height, digest: metadata.digest, thumbnail: thumbnail, family: metadata.family))
                } catch { failures += 1 }
            }
            frames = sorted(loaded)
            if failures > 0 { error = "Couldn’t load \(failures) frame(s). Their files remain in the frame library folder." }
        } catch { self.error = "Couldn’t read the frame library. \(error.localizedDescription)" }
    }

    private(set) var isRemoving = false
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
        guard !isImporting, !isRemoving else { return [] }
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
        guard !isImporting, !isRemoving else { throw FramedError.message("Wait for the current library operation to finish.") }
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

    /// Selection prefetch and Use Frame share one decode/mask job, without editing a project.
    func preparedFrame(for frame: SavedFrame) async throws -> PreparedFrame {
        try Task.checkCancellation()
        guard frames.contains(where: { $0.id == frame.id && $0.digest == frame.digest }) else {
            throw FramedError.message("This frame is no longer in the library.")
        }
        let key = PreparationKey(id: frame.id, digest: frame.digest)
        if let ready = preparedFrames.object(forKey: key.cacheKey) { return ready }
        let client = UUID()
        var job: PreparationJob
        if let existing = preparationJobs[key] { job = existing }
        else {
            let directory = directory
            job = PreparationJob(task: Task {
                let (image, opening) = try await FrameFileWorker.prepare(frame, directory: directory)
                return PreparedFrame(image: image, opening: opening)
            })
        }
        job.clients.insert(client)
        preparationJobs[key] = job
        let token = job.token, task = job.task
        defer { releasePreparation(key, token: token, client: client) }
        return try await withTaskCancellationHandler {
            let ready = try await task.value
            try Task.checkCancellation()
            guard preparationJobs[key]?.token == token,
                  frames.contains(where: { $0.id == frame.id && $0.digest == frame.digest }) else {
                throw CancellationError()
            }
            preparedFrames.setObject(ready, forKey: key.cacheKey, cost: ready.memoryCost)
            return ready
        } onCancel: {
            Task { @MainActor [weak self] in self?.releasePreparation(key, token: token, client: client) }
        }
    }

    private func releasePreparation(_ key: PreparationKey, token: UUID, client: UUID) {
        guard var job = preparationJobs[key], job.token == token else { return }
        job.clients.remove(client)
        if job.clients.isEmpty {
            preparationJobs[key] = nil
            job.task.cancel()
        } else { preparationJobs[key] = job }
    }

    private func invalidatePreparation() {
        preparedFrames.removeAllObjects()
        for job in preparationJobs.values { job.task.cancel() }
        preparationJobs.removeAll()
    }

    func rename(_ frame: SavedFrame, to proposedName: String) throws {
        guard !isImporting, !isRemoving else { throw FramedError.message("Wait for the current library operation to finish.") }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FramedError.message("Enter a name for this frame.") }
        guard frames.contains(where: { $0.id == frame.id }) else { return }
        let metadata = FrameMetadata(id: frame.id, name: name, width: frame.width, height: frame.height, digest: frame.digest, family: frame.family)
        try JSONEncoder().encode(metadata).write(to: folder(frame.id).appendingPathComponent("metadata.json"), options: .atomic)
        frames = sorted(frames.map { $0.id == frame.id ? SavedFrame(id: frame.id, name: name, width: frame.width, height: frame.height, digest: frame.digest, thumbnail: frame.thumbnail, family: frame.family) : $0 })
    }

    func remove(_ frame: SavedFrame) throws {
        guard !isImporting, !isRemoving else { throw FramedError.message("Wait for the current library operation to finish.") }
        // This removes only the reusable copy; each open/saved project owns its images.
        try FileManager.default.removeItem(at: folder(frame.id))
        frames.removeAll { $0.id == frame.id }
        invalidatePreparation()
    }

    func removeFrames(_ ids: Set<UUID>) async {
        guard !isImporting, !isRemoving, !ids.isEmpty else { return }
        isRemoving = true
        defer { isRemoving = false }
        let targets = frames.filter { ids.contains($0.id) }
        let result = await FrameFileWorker.removeFrames(targets, directory: directory)
        frames.removeAll { result.removed.contains($0.id) }
        if !result.removed.isEmpty { invalidatePreparation() }
        if !result.failures.isEmpty { error = result.failures.joined(separator: "\n") }
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
    var family: FrameDeviceFamily? = nil
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
            try Task.checkCancellation()
            let opening = ScreenOpening.detect(in: image.image)
            try Task.checkCancellation()
            return (image, opening)
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
        let metadata = FrameMetadata(id: id, name: image.name, width: image.image.width, height: image.image.height,
                                     digest: digest, family: FrameDeviceFamily.detect(in: image.name))
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

    @concurrent
    static func removeFrames(_ frames: [SavedFrame], directory: URL) async -> FrameRemovalResult {
        var result = FrameRemovalResult()
        for frame in frames {
            let folder = directory.appendingPathComponent(frame.id.uuidString, isDirectory: true)
            do {
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
                result.removed.insert(frame.id)
            } catch { result.failures.append("\(frame.name): \(error.localizedDescription)") }
        }
        return result
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

nonisolated struct FrameRemovalResult: Sendable {
    var removed: Set<UUID> = []
    var failures: [String] = []
}
