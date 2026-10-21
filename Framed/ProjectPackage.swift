import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A package keeps the JSON lightweight while original image bytes remain files.
nonisolated enum ProjectPackage {
    private struct Manifest: Codable {
        var format = "com.georgebabichev.framed.package"
        var version = 1
        var project: FramedProject
    }

    static func read(from url: URL, progress: (ProjectLoadingProgress) -> Void = { _ in }) throws -> FramedProject {
        try coordinatedRead(url) { root in
            let manifestURL = root.appendingPathComponent("project.json")
            try requireRegularFile(manifestURL)
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.format == "com.georgebabichev.framed.package", manifest.version == 1 else {
                throw FramedError.message("This project package uses an unsupported format.")
            }
            var project = manifest.project
            let total = project.screenshots.count + project.mockups.count
            var completed = 0
            func hydrate(_ record: ProjectImage, folder: String) throws -> ProjectImage {
                try Task.checkCancellation()
                guard let path = record.file else { throw FramedError.message("A project image is missing its file reference.") }
                let asset = try assetURL(path, folder: folder, root: root)
                try requireRegularFile(asset)
                progress(ProjectLoadingProgress(stage: .readingImages, completed: completed, total: total, itemName: record.name))
                var record = record
                record.png = try Data(contentsOf: asset)
                let digest = asset.lastPathComponent.split(separator: "-", maxSplits: 1).first.map(String.init)
                guard digest == FrameFileWorker.digest(record.png) else {
                    throw FramedError.message("The project image ‘\(record.name)’ is damaged.")
                }
                record.file = nil
                completed += 1
                progress(ProjectLoadingProgress(stage: .readingImages, completed: completed, total: total, itemName: record.name))
                return record
            }
            project.screenshots = try project.screenshots.map { try hydrate($0, folder: "Screenshots") }
            project.mockups = try project.mockups.map { try hydrate($0, folder: "Frames") }
            return project
        }
    }

    static func write(_ project: FramedProject, to url: URL) throws {
        try coordinatedWrite(url) { destination in
            let manager = FileManager.default
            let parent = destination.deletingLastPathComponent()
            var parentIsDirectory: ObjCBool = false
            guard manager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
                throw FramedError.message("The project’s save folder no longer exists.")
            }
            // Build a complete replacement first. Existing assets are immutable and
            // hard-linked when unchanged, so layout saves need not rewrite images.
            // Use Foundation's replacement directory so sandboxed Save As can
            // stage safely without requiring access to unrelated sibling paths.
            let replacement = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                              appropriateFor: destination, create: true)
            defer { try? manager.removeItem(at: replacement) }
            let staging = replacement.appendingPathComponent("Project.framed", isDirectory: true)
            try manager.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: staging) }
            for name in ["Screenshots", "Frames"] {
                try manager.createDirectory(at: staging.appendingPathComponent(name), withIntermediateDirectories: false)
            }
            var snapshot = project
            var files: Set<String> = []
            var paths: [String: String] = [:]
            func store(_ record: ProjectImage, folder: String) throws -> ProjectImage {
                guard !record.png.isEmpty else { throw FramedError.message("The image ‘\(record.name)’ has no source data.") }
                let digest = FrameFileWorker.digest(record.png)
                let key = folder + "/" + digest
                let path: String
                if let existing = paths[key] { path = existing }
                else {
                    let type = CGImageSourceCreateWithData(record.png as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
                    let detectedType = type.flatMap { UTType($0) }
                    let sourceSuffix = record.sourceFilename.map { URL(fileURLWithPath: $0).pathExtension }
                    let sourceType = sourceSuffix.flatMap { UTType(filenameExtension: $0) }
                    let suffix = sourceType == detectedType && sourceType != nil
                        ? sourceSuffix! : detectedType?.preferredFilenameExtension ?? "png"
                    let original = record.sourceFilename ?? record.name + "." + suffix
                    let stem = String(URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent.prefix(24))
                        .replacingOccurrences(of: ":", with: "-")
                        .components(separatedBy: .controlCharacters).joined()
                    path = "\(folder)/\(digest)-\(stem.isEmpty ? "image" : stem).\(suffix)"
                    paths[key] = path
                }
                if files.insert(path).inserted {
                    let asset = try assetURL(path, folder: folder, root: staging)
                    let previous = try assetURL(path, folder: folder, root: destination)
                    var linked = false
                    if (try? requireRegularFile(previous)) != nil,
                       (try? Data(contentsOf: previous)) == record.png {
                        do { try manager.linkItem(at: previous, to: asset); linked = true } catch { }
                    }
                    if !linked { try record.png.write(to: asset, options: .withoutOverwriting) }
                }
                var metadata = record
                metadata.png = Data()
                metadata.file = path
                metadata.sourceFilename = record.sourceFilename ?? record.name + "." + URL(fileURLWithPath: path).pathExtension
                return metadata
            }
            snapshot.screenshots = try snapshot.screenshots.map { try store($0, folder: "Screenshots") }
            snapshot.mockups = try snapshot.mockups.map { try store($0, folder: "Frames") }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(Manifest(project: snapshot)).write(to: staging.appendingPathComponent("project.json"))
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staging, options: .usingNewMetadataOnly)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
        }
    }

    private static func assetURL(_ path: String, folder: String, root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == folder, !parts[1].isEmpty,
              parts[1] != ".", parts[1] != ".." else {
            throw FramedError.message("This project contains an invalid image path.")
        }
        let asset = root.appendingPathComponent(path)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard asset.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRoot) else {
            throw FramedError.message("A project image points outside the project package.")
        }
        return asset
    }

    private static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw FramedError.message("The project contains a missing or invalid image file.")
        }
    }

    private static func coordinatedRead<T>(_ url: URL, operation: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { resolved in
            result = Result { try operation(resolved) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FramedError.message("Couldn’t access the project package.") }
        return try result.get()
    }

    private static func coordinatedWrite(_ url: URL, operation: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { resolved in
            result = Result { try operation(resolved) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FramedError.message("Couldn’t save the project package.") }
        try result.get()
    }
}
