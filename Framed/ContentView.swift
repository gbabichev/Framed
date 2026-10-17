import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = EditorModel()
    @State private var inspectorPresented = true
    @State private var exportPresented = false

    var body: some View {
        NavigationSplitView {
            ScreenshotSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.importImages(mockups: false) } label: {
                            Label("Add screenshots", systemImage: "photo.badge.plus")
                        }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut("i", modifiers: .command)
                        .help("Add screenshots (Command-I)")
                    }
                }
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
        .environment(model)
        .background(ProjectWindowState(model: model, isEdited: model.isDirty, projectURL: model.projectURL).frame(width: 0, height: 0))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.openProject() } label: {
                    Label("Open Project", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Open Project (Command-O)")
                .disabled(model.isBusy || model.isPresentingProjectDialog)
                Button { model.saveProject() } label: {
                    Label("Save Project", systemImage: "tray.and.arrow.down")
                }
                .labelStyle(.iconOnly)
                .help("Save Project (Command-S)")
                .disabled(model.isBusy || model.isPresentingProjectDialog)
            }
            ToolbarItemGroup {
                Button { exportPresented = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!model.canExport && !model.canExportAll)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.right") {
                    inspectorPresented.toggle()
                }
                .help("Show or hide the inspector")
            }
        }
        .disabled(model.isBusy)
        .sheet(isPresented: $exportPresented) {
            ExportDialog(model: model)
                .environment(\.isEnabled, true)
        }
        .sheet(isPresented: $model.isShowingFrameLibrary) {
            FrameLibraryBrowser(model: model, library: model.frameLibrary)
        }
        .sheet(isPresented: Binding(get: { model.isPresentingFrameImport && !model.isShowingFrameLibrary }, set: { _ in })) {
            FrameImportProgress(model: model, library: model.frameLibrary)
                .environment(\.isEnabled, true)
        }
        .sheet(isPresented: Binding(get: { model.isOpeningProject }, set: { _ in })) {
            ProjectOpenProgress(model: model)
                .environment(\.isEnabled, true)
        }
        .alert("Couldn’t complete the operation", isPresented: Binding(get: { model.error != nil && !exportPresented }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private struct ProjectOpenProgress: View {
    let model: EditorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isCancellingProjectOpen ? "Stopping…" : "Opening Project")
                .font(.headline)
            Text(model.openingProjectName).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(model.projectOpenMessage).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelProjectOpen() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCancellingProjectOpen)
            }
        }
        .padding(24)
        .frame(width: 400)
        .interactiveDismissDisabled()
    }
}

private struct ScreenshotSidebar: View {
    @Bindable var model: EditorModel
    @State private var applyStyleSource: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    Button("Import screenshots…") { model.importImages(mockups: false) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedScreenshotID) {
                    ForEach(model.screenshots) { shot in
                        let layout = model.layout(for: shot.id)
                        let frame = model.mockups.first { $0.id == layout.mockupID }
                        ScreenshotRow(name: shot.name, image: shot.image, frame: frame,
                                      opening: model.screenOpening(for: layout.mockupID), settings: layout.settings,
                                      remove: { model.removeScreenshot(shot.id) })
                            .tag(shot.id)
                            .listRowBackground(Color.clear)
                            .onDrag { NSItemProvider(object: shot.id.uuidString as NSString) }
                            .contextMenu {
                                Button("Duplicate") { model.duplicateScreenshot(shot.id) }
                                Button("Move Up") { model.moveScreenshot(shot.id, by: -1) }
                                    .disabled(model.screenshots.first?.id == shot.id)
                                Button("Move Down") { model.moveScreenshot(shot.id, by: 1) }
                                    .disabled(model.screenshots.last?.id == shot.id)
                                Divider()
                                Button("Copy Style") { model.copyStyle(from: shot.id) }
                                Button("Paste Style") { model.pasteStyle(to: shot.id) }.disabled(!model.canPasteStyle)
                                Button("Apply Style to All…") { applyStyleSource = shot.id }
                                    .disabled(model.screenshots.count < 2)
                                Divider()
                                Button("Remove", role: .destructive) { model.removeScreenshot(shot.id) }
                            }
                    }
                    .onMove(perform: model.moveScreenshots)
                    .onInsert(of: [.plainText]) { destination, providers in
                        guard let provider = providers.first else { return }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let value = value as? String, let id = UUID(uuidString: value) else { return }
                            Task { @MainActor in
                                guard let index = model.screenshots.firstIndex(where: { $0.id == id }) else { return }
                                model.moveScreenshots(from: IndexSet(integer: index), to: min(destination, model.screenshots.count))
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .confirmationDialog("Apply this style to all screenshots?", isPresented: Binding(get: { applyStyleSource != nil }, set: { if !$0 { applyStyleSource = nil } })) {
            Button("Apply Style to All") {
                if let id = applyStyleSource { model.applyStyleToAll(from: id) }
                applyStyleSource = nil
            }
            Button("Cancel", role: .cancel) { applyStyleSource = nil }
        } message: {
            Text("Replaces each screenshot’s frame, canvas, appearance, headline styling, and effects. Each headline’s text is kept.")
        }
    }
}

private struct ScreenshotRow: View {
    let name: String
    let image: CGImage
    let frame: ImportedImage?
    let opening: ScreenOpening?
    let settings: CompositionSettings
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ScreenshotThumbnail(screenshot: image, frame: frame, opening: opening, settings: settings)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1).help(name)
                Text("\(image.width) × \(image.height)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove screenshot from project")
            .accessibilityLabel(Text("Remove \(name)"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ScreenshotThumbnail: View {
    let screenshot: CGImage
    let frame: ImportedImage?
    let opening: ScreenOpening?
    let settings: CompositionSettings
    @State private var rendered: CGImage?

    private struct RenderKey: Equatable {
        let frameID: UUID?
        let settings: ProjectSettings
    }

    // Only screen fitting and calibration affect the device-only thumbnail.
    private var thumbnailSettings: CompositionSettings {
        var result = CompositionSettings()
        result.fillScreen = settings.fillScreen; result.manualScreen = settings.manualScreen
        result.screenX = settings.screenX; result.screenY = settings.screenY
        result.screenWidth = settings.screenWidth; result.screenHeight = settings.screenHeight
        result.cornerRadius = settings.cornerRadius
        return result
    }

    var body: some View {
        Group {
            if let frame {
                Image(decorative: rendered ?? frame.image, scale: 1).resizable().scaledToFit()
            } else {
                Image(decorative: screenshot, scale: 1).resizable().scaledToFill()
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: RenderKey(frameID: frame?.id, settings: ProjectSettings(thumbnailSettings))) {
            if let frame {
                rendered = try? CompositionRenderer.deviceThumbnail(screenshot: screenshot, mockup: frame.image,
                                                                    opening: opening, settings: thumbnailSettings)
            } else { rendered = nil }
        }
    }
}

private struct PreviewPane: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if model.selectedScreenshot != nil || model.selectedMockup != nil {
                    CompositionPreview(screenshot: model.selectedScreenshot?.image, mockup: model.selectedMockup?.image, opening: model.opening,
                                       settings: $model.settings, forceOpaque: model.jpeg)
                        .frame(width: max(1, geometry.size.width - 72), height: max(1, geometry.size.height - 48))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyCanvas()
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
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("Add a screenshot or device frame")
                .font(.headline).multilineTextAlignment(.center)
            Text("Import screenshots in the sidebar or choose a device frame in the inspector.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum EditorPreferences {
    static let centerGuides = "editor.showCenterGuides"
    static let centerSnapping = "editor.snapToCenter"
}

private struct CenterGuides: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.accentColor.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CompositionPreview: View {
    @Environment(\.displayScale) private var displayScale
    @AppStorage(EditorPreferences.centerGuides) private var showCenterGuides = false
    let screenshot: CGImage?
    let mockup: CGImage?
    let opening: ScreenOpening?
    @Binding var settings: CompositionSettings
    let forceOpaque: Bool
    var body: some View {
        GeometryReader { geometry in
            let resolution = PreviewResolution.maxDimension(canvas: settings.outputSize, viewport: geometry.size,
                                                             displayScale: displayScale)
            if let image = try? CompositionRenderer.render(screenshot: screenshot, mockup: mockup, opening: opening,
                                                           settings: settings, maxDimension: resolution, forceOpaque: forceOpaque) {
                ZStack {
                    if settings.transparentBackground && !forceOpaque { TransparencyGrid() }
                    Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
                    if showCenterGuides { CenterGuides() }
                    DeviceDragOverlay(screenshot: screenshot, mockup: mockup, settings: $settings)
                    if settings.manualScreen, let mockup {
                        ScreenCalibrationOutline(mockup: mockup, settings: settings)
                    }
                    if settings.headline.enabled {
                        HeadlineDragOverlay(headline: $settings.headline)
                    }
                }
                .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                .accessibilityLabel("Composed screenshot preview")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Set the screen area", systemImage: "viewfinder", description: Text("This mockup needs manual screen bounds. Enable Manual screen area in the inspector."))
            }
        }
    }
}

private struct DeviceDragOverlay: View {
    @Environment(EditorModel.self) private var editor
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    let screenshot: CGImage?
    let mockup: CGImage?
    @Binding var settings: CompositionSettings
    @State private var dragOrigin: CGPoint?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let rect = CompositionRenderer.foregroundRect(screenshot: screenshot, mockup: mockup,
                                                           canvas: geometry.size, settings: settings)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.blue.opacity(hovering || dragOrigin != nil ? 0.7 : 0),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: geometry.size.height - rect.midY)
                .onHover { hovering = $0 }
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragOrigin == nil {
                            editor.beginEditing("Move Device")
                            dragOrigin = CGPoint(x: settings.deviceX, y: settings.deviceY)
                        }
                        guard let origin = dragOrigin else { return }
                        let candidate = CGPoint(x: min(1, max(0, origin.x + value.translation.width / geometry.size.width)),
                                                y: min(1, max(0, origin.y + value.translation.height / geometry.size.height)))
                        let snapped = CenterSnapping.position(candidate, canvas: geometry.size, enabled: snapToCenter)
                        settings.deviceX = snapped.x; settings.deviceY = snapped.y
                    }
                    .onEnded { _ in dragOrigin = nil; editor.endEditing() })
                .help("Drag to move the device and screenshot together")
                .accessibilityLabel("Device position; use the position controls in Appearance for precise placement")
        }
        .clipped()
        .onDisappear { if dragOrigin != nil { dragOrigin = nil; editor.endEditing() } }
    }
}

private struct HeadlineDragOverlay: View {
    @Environment(EditorModel.self) private var editor
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    @Binding var headline: HeadlineSettings
    @State private var dragOrigin: CGPoint?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            if let layout = HeadlineRenderer.layout(headline, canvas: geometry.size) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.blue.opacity(hovering || dragOrigin != nil ? 0.9 : 0.25),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .contentShape(Rectangle())
                    .frame(width: layout.rect.width + 12, height: layout.rect.height + 12)
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                    .onHover { hovering = $0 }
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragOrigin == nil {
                                editor.beginEditing("Move Headline")
                                dragOrigin = CGPoint(x: layout.rect.midX, y: layout.rect.midY)
                            }
                            guard let origin = dragOrigin else { return }
                            let halfWidth = layout.rect.width / 2, halfHeight = layout.rect.height / 2
                            let candidate = CGPoint(x: min(geometry.size.width - halfWidth, max(halfWidth, origin.x + value.translation.width)) / geometry.size.width,
                                                    y: min(geometry.size.height - halfHeight, max(halfHeight, origin.y + value.translation.height)) / geometry.size.height)
                            let snapped = CenterSnapping.position(candidate, canvas: geometry.size, enabled: snapToCenter)
                            headline.x = snapped.x; headline.y = snapped.y
                        }
                        .onEnded { _ in dragOrigin = nil; editor.endEditing() })
                    .help("Drag to move the headline")
                    .accessibilityLabel("Move headline; position controls are also available in the inspector")
            }
        }
        .onDisappear { if dragOrigin != nil { dragOrigin = nil; editor.endEditing() } }
    }
}

private struct ScreenCalibrationOutline: View {
    let mockup: CGImage
    let settings: CompositionSettings

    var body: some View {
        GeometryReader { geometry in
            let cgDevice = CompositionRenderer.deviceRect(image: mockup, canvas: geometry.size, settings: settings)
            let device = CGRect(x: cgDevice.minX, y: geometry.size.height - cgDevice.maxY,
                                width: cgDevice.width, height: cgDevice.height)
            let bounds = settings.manualBounds
            let width = device.width * bounds.width
            let height = device.height * bounds.height
            RoundedRectangle(cornerRadius: min(width, height) * settings.cornerRadius)
                .strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: min(width, height) * settings.cornerRadius))
                .frame(width: width, height: height)
                .position(x: device.minX + bounds.midX * device.width,
                          y: device.minY + bounds.midY * device.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

// Matches Simple Layout's ToolSection and SettingsRow styling, using native switches.
private struct InspectorCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let headerAction: (() -> Void)?
    let content: Content

    init(_ title: LocalizedStringKey, systemImage: String, headerAction: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title; self.systemImage = systemImage
        self.headerAction = headerAction; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).font(.headline)
                Spacer(minLength: 0)
                if let headerAction {
                    Button(action: headerAction) { Image(systemName: "plus") }
                        .help("Import PNG mockups")
                        .accessibilityLabel("Import PNG mockups")
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

private struct InspectorSwitch: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title; _isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorPane: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    InspectorCard("Device Frame", systemImage: "iphone", headerAction: { model.importImages(mockups: true) }) {
                        MockupSettings(model: model)
                    }
                    InspectorCard("Appearance", systemImage: "paintpalette") {
                        LayoutSettings(hasFrame: model.selectedMockup != nil, settings: $model.settings)
                    }
                    InspectorCard("Headline", systemImage: "textformat") {
                        HeadlineSettingsView(settings: $model.settings)
                    }
                    InspectorCard("Effects", systemImage: "sparkles") {
                        EffectsSettings(effects: $model.settings.effects)
                    }
                    InspectorCard("Export Canvas", systemImage: "rectangle") {
                        OutputSettings(settings: $model.settings, suggestion: model.suggestedCanvas)
                    }
                    if !model.warnings.isEmpty {
                        InspectorCard("Checks", systemImage: "exclamationmark.triangle") {
                            ForEach(model.warnings, id: \.self) { warning in
                                Text(warning).font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            Picker("Orientation", selection: Binding(
                get: { settings.outputSize.width > settings.outputSize.height },
                set: { settings.landscape = $0 })) {
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
    @Environment(EditorModel.self) private var editor
    @Binding var settings: CompositionSettings
    let suggestion: ScreenshotPreset.Suggestion

    private var matches: Bool { settings.outputSize == suggestion.size }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(matches ? "Canvas matched to device frame" : "Suggested for this frame",
                  systemImage: matches ? "checkmark.circle" : "sparkles")
                .font(.caption).foregroundStyle(.secondary)
            if !matches {
                Text(suggestion.preset.name).font(.caption)
                Text("\(Int(suggestion.size.width)) × \(Int(suggestion.size.height)) pixels")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use Suggested Canvas") {
                    editor.beginEditing("Change Canvas")
                    defer { editor.endEditing() }
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
            Button { model.isShowingFrameLibrary = true } label: {
                HStack(spacing: 12) {
                    FrameThumbnail(image: model.selectedMockup?.image)
                        .frame(width: 72, height: 64)
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
                ScreenCalibrationSettings(model: model)
                Divider()
                DesktopBackdropSettings(desktop: $model.settings.desktop)
            } else {
                Text("Import a front-facing PNG with a transparent screen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DesktopBackdropSettings: View {
    @Binding var desktop: DesktopSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSwitch("Desktop backdrop", isOn: $desktop.enabled)
            Text("Place a window screenshot on a gradient desktop inside the frame. Works best with transparent window captures.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if desktop.enabled {
                ColorPicker("Wallpaper start", selection: Binding(
                    get: { Color(nsColor: desktop.topColor) },
                    set: { desktop.topColor = NSColor($0) }), supportsOpacity: false)
                ColorPicker("Wallpaper end", selection: Binding(
                    get: { Color(nsColor: desktop.bottomColor) },
                    set: { desktop.bottomColor = NSColor($0) }), supportsOpacity: false)
                ValueSlider(title: "Window size", value: $desktop.windowScale, range: 0.2...1)
                ValueSlider(title: "Window horizontal position", value: $desktop.windowX, range: 0...1)
                ValueSlider(title: "Window vertical position", value: $desktop.windowY, range: 0...1)
                InspectorSwitch("Window shadow", isOn: $desktop.shadow)
                Button("Center Window") { desktop.windowX = 0.5; desktop.windowY = 0.5 }
            }
        }
    }
}

private struct ScreenCalibrationSettings: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Automatic detection is recommended.")
                .foregroundStyle(.secondary)
            InspectorSwitch("Adjust screen edges manually", isOn: $model.manualCalibrationEnabled)
            if model.settings.manualScreen {
                if model.opening != nil {
                    Button("Reset to Detected Screen") { model.resetScreenCalibration() }
                }
                Text("Adjust the blue outline to match the screen opening. Edges are percentages of the frame image.")
                    .foregroundStyle(.secondary)
                ValueSlider(title: "Left edge", value: $model.settings.screenLeft,
                            range: 0...max(0.001, model.settings.screenRight - 0.1))
                ValueSlider(title: "Right edge", value: $model.settings.screenRight,
                            range: min(0.999, model.settings.screenLeft + 0.1)...1)
                ValueSlider(title: "Top edge", value: $model.settings.screenTop,
                            range: 0...max(0.001, model.settings.screenBottom - 0.1))
                ValueSlider(title: "Bottom edge", value: $model.settings.screenBottom,
                            range: min(0.999, model.settings.screenTop + 0.1)...1)
                ValueSlider(title: "Corner rounding", value: $model.settings.cornerRadius, range: 0...0.25)
                Text("Manual calibration uses rounded corners. Automatic detection also preserves camera cutouts.")
                    .foregroundStyle(.secondary)
            }
        }.font(.caption)
    }
}

private struct LayoutSettings: View {
    let hasFrame: Bool
    @AppStorage(EditorPreferences.centerGuides) private var showCenterGuides = false
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    @Binding var settings: CompositionSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSwitch("Transparent background", isOn: $settings.transparentBackground)
            ColorPicker(settings.transparentBackground ? "JPEG background" : "Background", selection: Binding(get: { Color(nsColor: settings.background) }, set: { settings.background = NSColor($0) }), supportsOpacity: false)
            ValueSlider(title: "Device scale", value: $settings.deviceScale, range: 0.4...1)
            DevicePositionSettings(settings: $settings)
            InspectorSwitch("Show center guides", isOn: $showCenterGuides)
            InspectorSwitch("Snap to center", isOn: $snapToCenter)
            Text("Guides and snapping are editing aids. Drag near either center line to align the device or headline.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Screenshot", selection: $settings.fillScreen) {
                Text("Fit").tag(false)
                Text("Fill").tag(true)
            }.pickerStyle(.segmented)
            .help("Fit keeps the whole screenshot. Fill crops to cover the screen.")
            .disabled(hasFrame && settings.desktop.enabled)
            Text(hasFrame && settings.desktop.enabled ? "Desktop backdrop keeps the window’s proportions. Use Window size in Device Frame to resize it."
                 : settings.fillScreen ? "Fill covers the screen, cropping the screenshot if needed."
                 : "Fit shows the whole screenshot. Different proportions leave black bars inside the device.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DevicePositionSettings: View {
    @Binding var settings: CompositionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag the device in the preview to move it with its screenshot.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Device position") {
                VStack(alignment: .leading, spacing: 10) {
                    ValueSlider(title: "Device horizontal position", value: $settings.deviceX, range: 0...1)
                    ValueSlider(title: "Device vertical position", value: $settings.deviceY, range: 0...1)
                    Button("Reset Device Position") { settings.resetDevicePosition() }
                    Text("The center is positioned within the canvas. Device edges can extend beyond it.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.caption)
        }
    }
}

private extension CompositionEffects {
    var pickerColor: Color {
        get { Color(nsColor: glowColor) }
        set { glowColor = NSColor(newValue) }
    }
}

private struct EffectsSettings: View {
    @Binding var effects: CompositionEffects

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSwitch("Corner glow", isOn: $effects.cornerGlow)
            if effects.cornerGlow {
                ColorPicker("Glow color", selection: $effects.pickerColor, supportsOpacity: false)
                Picker("Corner", selection: $effects.glowCorner) {
                    ForEach(GlowCorner.allCases) { Text($0.title).tag($0) }
                }
                ValueSlider(title: "Glow strength", value: $effects.glowStrength, range: 0...1)
                ValueSlider(title: "Glow size", value: $effects.glowSpread, range: 0.2...1.5)
            }
            InspectorSwitch("Device fade", isOn: $effects.deviceFade)
            if effects.deviceFade {
                Picker("Fade edge", selection: $effects.fadeEdge) {
                    ForEach(DeviceFadeEdge.allCases) { Text($0.title).tag($0) }
                }
                ValueSlider(title: "Fade depth", value: $effects.fadeDepth, range: 0.1...0.8)
                ValueSlider(title: "Fade strength", value: $effects.fadeStrength, range: 0...1)
                Text("Fades the screenshot and frame together into the background, or into transparency for transparent PNGs.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension HeadlineSettings {
    var pickerColor: Color {
        get { Color(nsColor: color) }
        set { color = NSColor(newValue) }
    }
}

private enum HeadlineFontCatalog {
    static let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

private struct HeadlineSettingsView: View {
    @Environment(EditorModel.self) private var editor
    @Binding var settings: CompositionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSwitch("Show headline", isOn: $settings.showHeadline)
            if settings.headline.enabled {
                TextField("First line", text: $settings.headline.firstLineInput)
                    .textFieldStyle(.roundedBorder)
                TextField("Second line (optional)", text: $settings.headline.secondLineInput)
                    .textFieldStyle(.roundedBorder)
                Picker("Font", selection: $settings.headline.fontFamily) {
                    Text("System").tag("")
                    ForEach(HeadlineFontCatalog.families, id: \.self) { Text($0).tag($0) }
                }
                Picker("Weight", selection: $settings.headline.weight) {
                    ForEach(HeadlineWeight.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    Text("Size (pixels)")
                    Spacer()
                    TextField("Font size", value: $settings.headlineFontSize, format: .number.precision(.fractionLength(0)))
                        .frame(width: 55).textFieldStyle(.roundedBorder)
                    Stepper("Font size", value: $settings.headlineFontSize,
                            in: settings.outputSize.width * 0.01...settings.outputSize.width * 0.15, step: 1)
                        .labelsHidden()
                }
                ColorPicker("Text color", selection: $settings.headline.pickerColor, supportsOpacity: false)
                Text("Drag the headline or device in the preview, or use their position controls. Reduce device scale for more space.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ValueSlider(title: "Horizontal position", value: $settings.headline.x, range: 0...1)
                ValueSlider(title: "Vertical position", value: $settings.headline.y, range: 0...1)
                Button("Reset Position") {
                    editor.beginEditing("Reset Headline Position")
                    defer { editor.endEditing() }
                    settings.headline.x = 0.5; settings.headline.y = 0.055
                }
            }
        }
    }
}

private struct ValueSlider: View {
    @Environment(EditorModel.self) private var editor
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
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if editing { editor.beginEditing("Adjust Layout") } else { editor.endEditing() }
            }).accessibilityLabel(Text(title))
        }
    }
}

private struct ExportDialog: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportAll = false
    @State private var showsStatus = false
    @State private var exportOptions = ExportOptions()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Screenshots").font(.title2.bold())
                    Text("Choose your settings, then select where to save.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(20)
            Divider()
            HStack(alignment: .top, spacing: 24) {
                ExportPreview(model: model, options: exportOptions)
                    .frame(width: 260).frame(maxHeight: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        InspectorCard("Export settings", systemImage: "square.and.arrow.up") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Format")
                                Picker("Format", selection: $model.jpeg) {
                                    Text("PNG").tag(false)
                                    Text("JPEG").tag(true)
                                }.pickerStyle(.segmented).labelsHidden()
                                if model.jpeg {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("JPEG quality")
                                            Spacer()
                                            Text(exportOptions.jpegQuality, format: .percent.precision(.fractionLength(0)))
                                                .foregroundStyle(.secondary).monospacedDigit()
                                        }
                                        Slider(value: $exportOptions.jpegQuality, in: 0.1...1, step: 0.05)
                                            .accessibilityLabel("JPEG quality")
                                        Text("Lower quality produces smaller files. Higher quality preserves more detail.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    LabeledContent("Compression", value: "Lossless")
                                    Text("PNG preserves image quality. Reduce output size below to make smaller PNG files.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if exportAll {
                                    Text(model.jpeg ? "JPEG uses each screenshot’s own background color."
                                         : "Each screenshot keeps its own background and transparency settings.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    InspectorSwitch("Transparent PNG background", isOn: $model.settings.transparentBackground)
                                        .disabled(model.jpeg)
                                    Text(model.jpeg ? "JPEG uses the background color selected in Appearance."
                                         : model.settings.transparentBackground ? "Transparency is preserved. App Store uploads require an opaque background."
                                         : "Opaque sRGB PNG at the selected canvas dimensions.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        ExportSizeSettings(options: $exportOptions, exportAll: exportAll)
                        InspectorCard("Screenshots", systemImage: "photo.on.rectangle") {
                            Picker("Screenshots to export", selection: $exportAll) {
                                Text("Selected screenshot").tag(false)
                                Text("All screenshots (\(model.screenshots.count))").tag(true)
                            }.pickerStyle(.radioGroup).labelsHidden()
                            Text(exportAll ? "Each screenshot uses its own frame, headline, canvas, and effects. Files follow the sidebar order in the folder you choose."
                                 : model.selectedScreenshot?.name ?? "No screenshot selected")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        LabeledContent(exportAll ? "Preview canvas" : "Canvas", value: "\(Int(exportOptions.pixelSize(for: model.settings).width)) × \(Int(exportOptions.pixelSize(for: model.settings).height)) px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(model.isBusy)
                }
            }.padding(20)
            Divider()
            HStack(spacing: 12) {
                if model.isBusy { ProgressView().controlSize(.small) }
                if showsStatus {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(showsStatus ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isBusy)
                Button(exportAll ? "Export All…" : "Export…") {
                    let started = exportAll ? model.exportAll(options: exportOptions) : model.exportSelected(options: exportOptions)
                    if started { showsStatus = true }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(exportAll ? !model.canExportAll : !model.canExport)
            }.padding(16)
        }
        .frame(width: 760, height: 680)
        .interactiveDismissDisabled(model.isBusy)
        .alert("Export failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private struct ExportSizeSettings: View {
    @Binding var options: ExportOptions
    let exportAll: Bool

    var body: some View {
        InspectorCard("Output size", systemImage: "arrow.up.left.and.arrow.down.right") {
            Picker("Canvas", selection: $options.preset) {
                Text(exportAll ? "Each screenshot’s canvas" : "Current canvas").tag(ScreenshotPreset?.none)
                ForEach(ScreenshotPreset.all) { preset in
                    Text(preset.label).tag(Optional(preset))
                }
            }
            Picker("Scale", selection: $options.scale) {
                Text("100% · Full size").tag(1.0)
                Text("75%").tag(0.75)
                Text("50%").tag(0.5)
                Text("25%").tag(0.25)
            }
            Text(options.preset == nil
                 ? "Uses each screenshot’s saved canvas. Export sizing does not change your layouts."
                 : "Uses this canvas size for every exported screenshot, keeping each layout’s orientation.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if options.scale < 1 {
                Text("Scaling reduces pixel dimensions. Use 100% to keep the selected App Store size.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ExportPreview: View {
    let model: EditorModel
    let options: ExportOptions
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let settings = options.settings(for: model.settings)
                let pixels = options.pixelSize(for: model.settings)
                let resolution = min(max(pixels.width, pixels.height),
                    PreviewResolution.maxDimension(canvas: settings.outputSize, viewport: geometry.size, displayScale: displayScale))
                if let shot = model.selectedScreenshot,
                   let image = try? CompositionRenderer.render(screenshot: shot.image, mockup: model.selectedMockup?.image,
                                                               opening: model.opening, settings: settings,
                                                               maxDimension: resolution, forceOpaque: model.jpeg) {
                    ZStack {
                        if model.settings.transparentBackground && !model.jpeg { TransparencyGrid() }
                        Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
                    }
                    .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                    .accessibilityLabel("Export preview")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("Preview").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
