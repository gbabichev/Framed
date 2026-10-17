import SwiftUI

struct ContentView: View {
    @State private var model = EditorModel()
    @State private var inspectorPresented = true

    var body: some View {
        NavigationSplitView {
            ScreenshotSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            HSplitView {
                PreviewPane(model: model)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                if inspectorPresented {
                    InspectorPane(model: model)
                        .frame(width: 280)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .navigationTitle(model.projectTitle)
        .focusedSceneValue(\.projectModel, model)
        .background(ProjectWindowState(model: model, isEdited: model.isDirty, projectURL: model.projectURL).frame(width: 0, height: 0))
        .toolbar {
            ToolbarItemGroup {
                Button { model.importImages(mockups: false) } label: { Label("Add screenshots", systemImage: "photo.badge.plus") }
                    .keyboardShortcut("i", modifiers: .command)
                Button { model.importImages(mockups: true) } label: { Label("Add mockups", systemImage: "iphone") }
                Button { model.exportSelected() } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!model.canExport)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.right") {
                    inspectorPresented.toggle()
                }
                .help("Show or hide the inspector")
            }
        }
        .disabled(model.isBusy)
        .sheet(isPresented: $model.isShowingFrameLibrary) {
            FrameLibraryBrowser(model: model, library: model.frameLibrary)
        }
        .sheet(isPresented: Binding(get: { model.isPresentingFrameImport && !model.isShowingFrameLibrary }, set: { _ in })) {
            FrameImportProgress(model: model, library: model.frameLibrary)
                .environment(\.isEnabled, true)
        }
        .alert("Couldn’t complete the operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private struct ScreenshotSidebar: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Screenshots").font(.headline).lineLimit(1)
                Spacer()
                Text("\(model.screenshots.count)").foregroundStyle(.secondary).monospacedDigit()
            }.padding()
            if model.screenshots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title).foregroundStyle(.tertiary)
                    Text("No screenshots")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Add images from your device or simulator.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedScreenshotID) {
                    ForEach(model.screenshots) { shot in
                        ScreenshotRow(name: shot.name, image: shot.image)
                            .tag(shot.id)
                            .contextMenu {
                                Button("Remove", role: .destructive) { model.removeScreenshot(shot.id) }
                            }
                    }
                }.listStyle(.sidebar)
            }
            Divider()
            Button { model.importImages(mockups: false) } label: {
                Label("Add…", systemImage: "plus").frame(maxWidth: .infinity)
            }.padding()
        }
    }
}

private struct ScreenshotRow: View {
    let name: String
    let image: CGImage
    var body: some View {
        HStack(spacing: 10) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
                .frame(width: 38, height: 52).background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).lineLimit(2).font(.callout)
                Text("\(image.width) × \(image.height)").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}

private struct PreviewPane: View {
    let model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Canvas", systemImage: "rectangle.inset.filled").font(.headline)
                Spacer()
                Text("\(Int(model.settings.outputSize.width)) × \(Int(model.settings.outputSize.height)) px")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(20)
            GeometryReader { geometry in
                if let shot = model.selectedScreenshot {
                    CompositionPreview(screenshot: shot.image, mockup: model.selectedMockup?.image, opening: model.opening,
                                       settings: model.settings, forceOpaque: model.jpeg)
                        .frame(width: max(1, geometry.size.width - 72), height: max(1, geometry.size.height - 48))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyCanvas { model.importImages(mockups: false) }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()

            }.padding(14)
        }.background(.primary.opacity(0.035))
    }
}

private struct EmptyCanvas: View {
    let importScreenshots: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("Add your first screenshot")
                .font(.headline).multilineTextAlignment(.center)
            Text("Choose an image from your device or simulator.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Import screenshots…", action: importScreenshots)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompositionPreview: View {
    let screenshot: CGImage
    let mockup: CGImage?
    let opening: ScreenOpening?
    let settings: CompositionSettings
    let forceOpaque: Bool
    var body: some View {
        if let image = try? CompositionRenderer.render(screenshot: screenshot, mockup: mockup, opening: opening,
                                                       settings: settings, maxDimension: 1000, forceOpaque: forceOpaque) {
            ZStack {
                if settings.transparentBackground && !forceOpaque { TransparencyGrid() }
                Image(decorative: image, scale: 1).resizable()
            }
                .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                .accessibilityLabel("Composed screenshot preview")
        } else {
            ContentUnavailableView("Set the screen area", systemImage: "viewfinder", description: Text("This mockup needs manual screen bounds. Enable Manual screen area in the inspector."))
        }
    }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in 0..<Int(ceil(size.width / tile)) where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                                      width: tile, height: tile)
                    context.fill(Path(rect), with: .color(.gray.opacity(0.2)))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct InspectorPane: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    OutputSettings(settings: $model.settings, suggestion: model.suggestedCanvas)
                    Divider()
                    MockupSettings(model: model)
                    Divider()
                    LayoutSettings(settings: $model.settings)
                    if !model.warnings.isEmpty {
                        ForEach(model.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ExportSettings(model: model)
                .padding(16)
        }
        .controlSize(.small)
        .background(.background)
    }
}

private struct OutputSettings: View {
    @Binding var settings: CompositionSettings
    let suggestion: ScreenshotPreset.Suggestion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Canvas").font(.headline)
            Text("The final image size, including the frame and background.")
                .font(.caption).foregroundStyle(.secondary)
            Text(settings.preset.name)
                .font(.callout).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(ScreenshotPreset.all) { preset in
                    Button(preset.label) { settings.preset = preset }
                }
            } label: {
                Text("\(Int(settings.outputSize.width)) × \(Int(settings.outputSize.height)) pixels")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderedButton)
            .help("Choose an App Store screenshot size")
            Picker("Orientation", selection: $settings.landscape) {
                Text("Portrait").tag(false)
                Text("Landscape").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(settings.preset.width >= settings.preset.height)
            if let suggestion {
                CanvasSuggestion(settings: $settings, suggestion: suggestion)
            }
            Link("App Store size requirements", destination: ScreenshotPreset.source)
                .font(.caption)
        }
    }
}

private struct CanvasSuggestion: View {
    @Binding var settings: CompositionSettings
    let suggestion: ScreenshotPreset.Suggestion

    private var matches: Bool { settings.outputSize == suggestion.size }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(matches ? "Matches frame proportions" : "Suggested for this frame",
                  systemImage: matches ? "checkmark.circle" : "sparkles")
                .font(.caption).foregroundStyle(.secondary)
            if !matches {
                Text(suggestion.preset.name).font(.caption)
                Text("\(Int(suggestion.size.width)) × \(Int(suggestion.size.height)) pixels")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use Suggested Canvas") {
                    settings.preset = suggestion.preset
                    settings.landscape = suggestion.landscape
                }
                .help("Choose an accepted export size with similar screen proportions. The frame keeps its orientation.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MockupSettings: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Device frame").font(.headline)
                Spacer()
                Button { model.importImages(mockups: true) } label: {
                    Image(systemName: "plus")
                }.help("Import PNG mockups")
            }
            Button { model.isShowingFrameLibrary = true } label: {
                HStack(spacing: 12) {
                    FrameThumbnail(image: model.selectedMockup?.image)
                        .frame(width: 48, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.selectedMockup == nil ? "Choose a frame…" : "Change frame…")
                        Text("\(model.frameLibrary.frames.count) saved frames")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            .buttonStyle(.bordered)
            if let mockup = model.selectedMockup {
                Text(model.selectedFrameDisplayName ?? mockup.name).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !model.selectedFrameIsInLibrary {
                    Button("Save this frame to library") { model.saveSelectedFrameToLibraryInBackground() }
                        .font(.caption)
                }
                if model.opening != nil && !model.settings.manualScreen {
                    Label("Screen detected", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Screen calibration") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Adjust manually", isOn: $model.settings.manualScreen)
                        if model.settings.manualScreen {
                            ValueSlider(title: "Left", value: $model.settings.screenX, range: 0...0.8)
                            ValueSlider(title: "Top", value: $model.settings.screenY, range: 0...0.8)
                            ValueSlider(title: "Width", value: $model.settings.screenWidth, range: 0.1...1)
                            ValueSlider(title: "Height", value: $model.settings.screenHeight, range: 0.1...1)
                            ValueSlider(title: "Corners", value: $model.settings.cornerRadius, range: 0...0.25)
                        }
                    }.padding(.top, 8)
                }.font(.caption)
            } else {
                Text("Import a front-facing PNG with a transparent screen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LayoutSettings: View {
    @Binding var settings: CompositionSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance").font(.headline)
            Toggle("Transparent background", isOn: $settings.transparentBackground)
            ColorPicker(settings.transparentBackground ? "JPEG background" : "Background", selection: Binding(get: { Color(nsColor: settings.background) }, set: { settings.background = NSColor($0) }), supportsOpacity: false)
            ValueSlider(title: "Device scale", value: $settings.deviceScale, range: 0.4...1)
            Picker("Screenshot", selection: $settings.fillScreen) {
                Text("Fit").tag(false)
                Text("Fill").tag(true)
            }.pickerStyle(.segmented)
            .help("Fit keeps the whole screenshot. Fill crops to cover the screen.")
        }
    }
}

private struct ValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(1)))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.font(.caption)
            Slider(value: $value, in: range).accessibilityLabel(Text(title))
        }
    }
}

private struct ExportSettings: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Format", selection: $model.jpeg) {
                Text("PNG").tag(false)
                Text("JPEG").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                Button("Export…") { model.exportSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canExport)
                Spacer()
                Button("Export all…") { model.exportAll() }
                    .disabled(!model.canExport || model.screenshots.isEmpty)
            }
            Text(model.settings.transparentBackground
                 ? (model.jpeg ? "JPEG uses the background color; transparency requires PNG."
                    : "Transparent PNG · For editing; App Store uploads require an opaque background.")
                 : "Opaque sRGB · App Store dimensions")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
