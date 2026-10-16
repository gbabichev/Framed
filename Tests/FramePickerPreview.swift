// Visual QA fixture. Set FRAMED_PREVIEW_FRAMES to a directory of PNG mockups.
// All reusable copies are written to a fresh temporary folder, never the user's library.
import AppKit
import SwiftUI

@MainActor
private let previewLibrary: FrameLibrary = {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("FramedPickerPreview-\(UUID())")
    let library = FrameLibrary(directory: root)
    if let path = ProcessInfo.processInfo.environment["FRAMED_PREVIEW_FRAMES"],
       let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) {
        for url in urls where url.pathExtension.lowercased() == "png" && ProcessInfo.processInfo.environment["FRAMED_PREVIEW_IMPORT"] != "1" {
            do { try library.store(ImportedImage(url: url)) }
            catch { library.error = error.localizedDescription }
        }
    }
    return library
}()

@MainActor
private let previewModel = EditorModel(frameLibrary: previewLibrary)

@main
struct FramePickerPreview: App {
    var body: some Scene {
        WindowGroup("Frame Library Preview") {
            FrameLibraryBrowser(model: previewModel, library: previewLibrary)
                .onAppear {
                    guard ProcessInfo.processInfo.environment["FRAMED_PREVIEW_IMPORT"] == "1",
                          let path = ProcessInfo.processInfo.environment["FRAMED_PREVIEW_FRAMES"],
                          let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) else { return }
                    previewModel.isShowingFrameLibrary = true
                    let frames = urls.filter { $0.pathExtension.lowercased() == "png" }
                    previewModel.startFrameImport(Array(repeating: frames, count: 20).flatMap { $0 }, applyLastFrame: false)
                }
        }.defaultSize(width: 820, height: 600)
    }
}
