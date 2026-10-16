import AppKit
import Observation
import UniformTypeIdentifiers

@Observable
final class EditorModel {
    var screenshots: [ImportedImage] = []
    var mockups: [ImportedImage] = []
    var selectedScreenshotID: UUID?
    var selectedMockupID: UUID?
    var settings = CompositionSettings()
    var jpeg = false
    var error: String?
    var status = "Import screenshots to get started."
    var isBusy = false
    private var openings: [UUID: ScreenOpening] = [:]

    var selectedScreenshot: ImportedImage? { screenshots.first { $0.id == selectedScreenshotID } }
    var selectedMockup: ImportedImage? { mockups.first { $0.id == selectedMockupID } }
    var opening: ScreenOpening? { selectedMockupID.flatMap { openings[$0] } }
    var canExport: Bool { selectedScreenshot != nil && (selectedMockup == nil || opening != nil || settings.manualScreen) && !isBusy }

    var warnings: [String] {
        guard let shot = selectedScreenshot else { return [] }
        var messages: [String] = []
        var target = settings.outputSize
        if let mockup = selectedMockup {
            guard let bounds = settings.manualScreen ? settings.manualBounds : opening?.bounds else {
                return ["No enclosed transparent screen found. Enable manual screen area, or choose another transparent PNG frame."]
            }
            let device = CompositionRenderer.deviceRect(image: mockup.image, canvas: target, scale: settings.deviceScale)
            target = CGSize(width: device.width * bounds.width, height: device.height * bounds.height)
            let screenAspect = target.width / target.height
            let shotAspect = Double(shot.image.width) / Double(shot.image.height)
            if abs(screenAspect / shotAspect - 1) > 0.025 {
                messages.append(settings.fillScreen ? "Aspect ratios differ. Fill crops the screenshot; check the preview." : "Aspect ratios differ. Fit keeps all content with black bars inside the screen.")
            }
        } else {
            target.width *= settings.deviceScale; target.height *= settings.deviceScale
        }
        let sx = target.width / Double(shot.image.width), sy = target.height / Double(shot.image.height)
        if (settings.fillScreen ? max(sx, sy) : min(sx, sy)) > 1.05 {
            messages.append("The screenshot will be enlarged. A higher-resolution source will look sharper.")
        }
        return messages
    }

    func importImages(mockups importingMockups: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = importingMockups ? [.png] : [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.message = importingMockups ? "Choose front-facing PNG mockups with transparent screen openings." : "Choose screenshots from a device or simulator."
        guard panel.runModal() == .OK else { return }
        load(panel.urls, asMockups: importingMockups)
    }

    func load(_ urls: [URL], asMockups: Bool) {
        var failures: [String] = []
        for url in urls {
            do {
                let imported = try ImportedImage(url: url)
                if asMockups {
                    mockups.append(imported)
                    if let opening = ScreenOpening.detect(in: imported.image) { openings[imported.id] = opening }
                    selectMockup(imported.id)
                } else {
                    screenshots.append(imported)
                    selectedScreenshotID = imported.id
                    if screenshots.count == 1 {
                        let w = imported.image.width, h = imported.image.height
                        if let preset = ScreenshotPreset.all.first(where: { ($0.width == w && $0.height == h) || ($0.width == h && $0.height == w) }) {
                            settings.preset = preset
                            settings.landscape = w > h && preset.width < preset.height
                        }
                    }
                }
            } catch { failures.append(error.localizedDescription) }
        }
        status = "Imported \(urls.count - failures.count) image(s)."
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func selectMockup(_ id: UUID?) {
        selectedMockupID = id
        settings.manualScreen = false
        if let bounds = opening?.bounds {
            settings.screenX = bounds.minX; settings.screenY = bounds.minY
            settings.screenWidth = bounds.width; settings.screenHeight = bounds.height
        }
    }

    func removeScreenshot(_ id: UUID) {
        screenshots.removeAll { $0.id == id }
        if selectedScreenshotID == id { selectedScreenshotID = screenshots.first?.id }
    }

    func exportSelected() {
        guard let screenshot = selectedScreenshot, canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [jpeg ? .jpeg : .png]
        panel.nameFieldStringValue = "\(screenshot.name)-framed.\(jpeg ? "jpg" : "png")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let image = try CompositionRenderer.render(screenshot: screenshot.image, mockup: selectedMockup?.image, opening: opening, settings: settings)
            try CompositionRenderer.encode(image, jpeg: jpeg).write(to: url, options: .atomic)
            status = "Saved \(url.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }

    func exportAll() {
        guard canExport else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Export here"
        panel.message = "A new folder will be created for this export. Every screenshot uses the current frame and layout."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        isBusy = true
        // Yield between images so progress and window events remain responsive.
        Task { @MainActor in
            let folder = directory.appendingPathComponent("Framed-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let images = screenshots, configuration = settings, mockup = selectedMockup?.image, mask = opening, useJPEG = jpeg
            var count = 0
            defer { isBusy = false }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                for (index, shot) in images.enumerated() {
                    let image = try CompositionRenderer.render(screenshot: shot.image, mockup: mockup, opening: mask, settings: configuration)
                    let safeName = shot.name.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
                    let url = folder.appendingPathComponent(String(format: "%02d-", index + 1) + safeName + (useJPEG ? ".jpg" : ".png"))
                    try CompositionRenderer.encode(image, jpeg: useJPEG).write(to: url, options: .atomic)
                    count += 1
                    status = "Exported \(count) of \(images.count)…"
                    await Task.yield()
                }
                status = "Saved \(count) screenshots in \(folder.lastPathComponent)."
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch { self.error = "Export stopped after \(count) files. \(error.localizedDescription)" }
        }
    }
}
