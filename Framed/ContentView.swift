import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = EditorModel()
    @State private var inspectorPresented = true
    @State private var exportPresented = false
    @State private var canvasZoom = CanvasZoom.fit
    @State private var panCanvas = false
    @State private var aboutPresented = false

    var body: some View {
        NavigationSplitView {
            ScreenshotSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 260, max: 360)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(ProjectDevice.allCases) { device in
                                Button(device.title, systemImage: device.symbol) { model.addDeviceSection(device) }
                            }
                        } label: { Label("Add Device", systemImage: "plus") }
                        .help("Add a device section")
                    }
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
                PreviewPane(model: model, zoom: canvasZoom, panEnabled: panCanvas)
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
        .focusedSceneValue(\.aboutPresented, $aboutPresented)
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
                Menu {
                    Picker("Canvas zoom", selection: $canvasZoom) {
                        ForEach(CanvasZoom.allCases) { zoom in Text(zoom.title).tag(zoom) }
                    }.pickerStyle(.inline)
                    Divider()
                    Button("Fit Canvas") { canvasZoom = .fit }
                        .keyboardShortcut("0", modifiers: .command)
                } label: {
                    Label(canvasZoom.title, systemImage: "magnifyingglass")
                }
                .labelStyle(.titleAndIcon)
                .help("Canvas zoom. 100% shows one image pixel per display pixel. Command-0 fits the canvas.")
                Toggle(isOn: $panCanvas) { Label("Pan Canvas", systemImage: "hand.draw") }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help(canvasZoom == .fit ? "Choose a zoom level to pan the canvas. Fit always shows the entire canvas."
                      : "Drag to pan the canvas. Turn off to move the device or headline. You can also scroll with a trackpad or the scroll bars.")
                .disabled(canvasZoom == .fit)
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
        .overlay {
            if aboutPresented {
                AboutOverlayView(isPresented: $aboutPresented)
            }
        }
        .onChange(of: canvasZoom) { _, value in
            if value == .fit { panCanvas = false }
        }
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
        let progress = model.projectOpenProgress
        VStack(alignment: .leading, spacing: 18) {
            Text(model.isCancellingProjectOpen ? "Stopping…" : "Opening Project")
                .font(.headline)
            Text(model.openingProjectName).lineLimit(1).truncationMode(.middle)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.projectOpenMessage).font(.callout)
                    Spacer(minLength: 8)
                    if progress.total > 0 {
                        Text("\(progress.completed) of \(progress.total)")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(progress.itemName ?? (progress.stage == .layouts ? "Restoring device sections and saved layouts…" : progress.stage == .finishing ? "Getting your canvas ready…" : "Reading project information…"))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelProjectOpen() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCancellingProjectOpen)
            }
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }
}

private enum SidebarRenameTarget {
    case device(DeviceSection)
    case screenshot(ImportedImage)

    var title: String {
        switch self {
        case .device: "Rename Device Section"
        case .screenshot: "Rename Screenshot"
        }
    }
}

private struct ScreenshotSidebar: View {
    @Bindable var model: EditorModel
    @State private var isDropTargeted = false
    @State private var pendingRemoval: DeviceSection?
    @State private var pendingApply: DeviceSection?
    @State private var pendingRename: SidebarRenameTarget?
    @State private var itemName = ""

    var body: some View {
        List(selection: $model.sidebarSelections) {
            Section {
                Label("Project Style", systemImage: "paintbrush.pointed")
                    .font(.callout)
                    .tag(SidebarSelection.projectStyle)
                    .help("Shared headline and effects across devices and screenshots")
            } header: {
                Text("Project")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(model.sidebarGroups) { group in
                DeviceSidebarSection(model: model, group: group,
                    requestRemoval: { pendingRemoval = $0 },
                    requestApply: { pendingApply = $0 },
                    requestRename: { section in
                        itemName = section.title; pendingRename = .device(section)
                    },
                    requestScreenshotRename: { shot in
                        itemName = shot.name; pendingRename = .screenshot(shot)
                    })
            }
        }
        .listStyle(.sidebar)
        .background(SidebarFocusRecovery())
        .overlay {
            if model.deviceSections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title).foregroundStyle(.tertiary)
                    Text("Add a device or screenshots").font(.callout)
                    Text("Drop screenshots here, or add a device to set up its default layout.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Menu("Add Device", systemImage: "plus") {
                        ForEach(ProjectDevice.allCases) { device in
                            Button(device.title, systemImage: device.symbol) { model.addDeviceSection(device) }
                        }
                    }
                    Button("Import screenshots…") { model.importImages(mockups: false) }
                }
                .padding(20)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { model.importDroppedScreenshots($0) }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4).allowsHitTesting(false)
            }
        }
        .confirmationDialog("Remove this device and its screenshots?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            if let section = pendingRemoval {
                Button("Remove Device", role: .destructive) {
                    pendingRemoval = nil
                    model.removeDeviceSection(section.id)
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Removes \(pendingRemoval?.title ?? "this device") and its screenshots. This can be undone.")
        }
        .confirmationDialog("Apply this device’s default layout?", isPresented: Binding(
            get: { pendingApply != nil }, set: { if !$0 { pendingApply = nil } })) {
            if let section = pendingApply {
                Button("Apply Layout") {
                    pendingApply = nil
                    model.applyDeviceLayout(section.id)
                }
            }
            Button("Cancel", role: .cancel) { pendingApply = nil }
        } message: {
            Text("Updates frames, canvas, appearance, headline styling, and effects in this section. Each screenshot’s headline text is kept.")
        }
        .alert(pendingRename?.title ?? "Rename", isPresented: Binding(
            get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })) {
            TextField("Name", text: $itemName)
            Button("Cancel", role: .cancel) { pendingRename = nil }
            if let target = pendingRename {
                Button("Rename") {
                    pendingRename = nil
                    switch target {
                    case .device(let section): model.renameDeviceSection(section.id, to: itemName)
                    case .screenshot(let shot): model.renameScreenshot(shot.id, to: itemName)
                    }
                }
                .disabled(itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct DeviceSidebarSection: View {
    @Bindable var model: EditorModel
    let group: DeviceSidebarGroup
    @State private var expanded = true
    let requestRemoval: (DeviceSection) -> Void
    let requestApply: (DeviceSection) -> Void
    let requestRename: (DeviceSection) -> Void
    let requestScreenshotRename: (ImportedImage) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        Section(isExpanded: $expanded) {
            Label {
                Text("Default Layout")
            } icon: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
                .font(.callout)
                .tag(SidebarSelection.device(group.id))
                .help("Edit the default layout for new screenshots in this device section")
                .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                    acceptDrop(providers)
                }
            ForEach(group.screenshots) { shot in
                DeviceScreenshotRow(model: model, shot: shot, sectionID: group.id, requestRename: requestScreenshotRename)
                    .tag(SidebarSelection.screenshot(shot.id))
            }
            .onMove { model.reorderScreenshots(in: group.id, from: $0, to: $1) }
            .onInsert(of: [.fileURL, .plainText]) { destination, providers in
                _ = acceptDrop(providers, at: destination)
            }
            if group.screenshots.isEmpty {
                Text("Drop screenshots here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                        acceptDrop(providers)
                    }
            }
        } header: {
            HStack {
                Button {
                    model.selectDeviceSection(group.id)
                } label: {
                    Label {
                        Text(group.section.title)
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: group.section.device.symbol)
                            .font(.system(size: 11, weight: .medium))
                    }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(group.section.title)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(group.screenshots.count, format: .number)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
            }
            .padding(.vertical, 4)
            .contextMenu {
                Button("Rename…") { requestRename(group.section) }
                Button("Duplicate Device Layout") { model.duplicateDeviceLayout(group.id) }
                Button("Import Screenshots…") {
                    model.selectDeviceSection(group.id); model.importImages(mockups: false)
                }
                Button("Apply Default Layout to Screenshots…") { requestApply(group.section) }
                    .disabled(group.screenshots.isEmpty)
                Divider()
                Button("Remove Device…", role: .destructive) { requestRemoval(group.section) }
            }
            .contentShape(Rectangle())
            .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .onDrop(of: [.fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
                acceptDrop(providers)
            }
        }

    }
    private func acceptDrop(_ providers: [NSItemProvider], at destination: Int? = nil) -> Bool {
        let accepted = model.handleSidebarDrop(providers, sectionID: group.id, at: destination)
        if accepted { expanded = true }
        return accepted
    }

}

private struct DeviceScreenshotRow: View {
    let model: EditorModel
    let shot: ImportedImage
    let sectionID: UUID
    let requestRename: (ImportedImage) -> Void

    var body: some View {
        let layout = model.layout(for: shot.id)
        let frame = model.mockups.first { $0.id == layout.mockupID }
        ScreenshotRow(name: shot.name, image: shot.image, frame: frame,
                      opening: model.screenOpening(for: layout.mockupID), settings: layout.settings,
                      remove: { model.removeScreenshot(shot.id) })
            .onDrag { model.screenshotDragProvider(for: shot.id) }
            .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
                let group = model.sidebarGroups.first { $0.id == sectionID }
                let index = group?.screenshots.firstIndex { $0.id == shot.id }
                return model.handleSidebarDrop(providers, sectionID: sectionID, at: index)
            }
            .contextMenu {
                Button("Rename…") { requestRename(shot) }
                Button("Duplicate") { model.duplicateScreenshot(shot.id) }
                Button("Move Up") { model.moveScreenshot(shot.id, by: -1) }
                Button("Move Down") { model.moveScreenshot(shot.id, by: 1) }
                Menu("Move to Device") {
                    ForEach(model.deviceSections) { section in
                        Button(section.title, systemImage: section.device.symbol) {
                            model.moveScreenshots(Set(model.screenshotIDsToMove(startingAt: shot.id)), toSection: section.id)
                        }
                    }
                }
                Divider()
                Button("Use as Device Default Layout") { model.useScreenshotAsDefault(shot.id) }
                Button("Copy Style") { model.copyStyle(from: shot.id) }
                Button("Paste Style") { model.pasteStyle(to: shot.id) }.disabled(!model.canPasteStyle)
                Divider()
                Button("Remove", role: .destructive) { model.removeScreenshotsFromContext(for: shot.id) }
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
    @State private var isHovered = false
    @FocusState private var isRemoveFocused: Bool

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
            .focused($isRemoveFocused)
            .opacity(isHovered || isRemoveFocused ? 1 : 0)
            .foregroundStyle(.secondary)
            .help("Remove screenshot from project")
            .accessibilityLabel(Text("Remove \(name)"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
    @Environment(\.displayScale) private var displayScale
    @Bindable var model: EditorModel
    let zoom: CanvasZoom
    let panEnabled: Bool
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                if model.selectedScreenshot != nil || model.selectedMockup != nil || model.activeSection != nil {
                    let size = zoom.size(canvas: model.settings.outputSize, viewport: geometry.size, displayScale: displayScale)
                    CanvasScroller(fit: zoom == .fit, panEnabled: panEnabled) {
                        CompositionPreview(screenshot: model.selectedScreenshot?.image, mockup: model.selectedMockup?.image,
                                           opening: model.opening, settings: $model.settings, forceOpaque: model.jpeg)
                            .frame(width: size.width, height: size.height)
                            .padding(.horizontal, 36).padding(.vertical, 24)
                            .frame(width: max(geometry.size.width, size.width + 72),
                                   height: max(geometry.size.height, size.height + 48))
                    }
                    .id("\(zoom.rawValue)-\(Int(model.settings.outputSize.width))x\(Int(model.settings.outputSize.height))")
                } else {
                    EmptyCanvas()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            HStack {
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(panEnabled ? "Drag to pan. Turn off the hand tool to edit the layout."
                     : model.selectedScreenshotID == nil && model.activeSection != nil
                        ? "Editing \(model.activeSection!.title) default layout · New screenshots inherit this layout." : model.status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()

            }.padding(14)
        }.background(.primary.opacity(0.035))
    }
}

private struct CanvasScroller<Content: View>: View {
    let fit: Bool
    let panEnabled: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if fit {
            // Fit is a fixed, centered view. No native scroll offset can survive here.
            content.clipped()
        } else {
            ScrollView([.horizontal, .vertical]) {
                content.overlay {
                    if panEnabled {
                        CanvasPanSurface()
                            .accessibilityLabel("Pan canvas")
                            .accessibilityHint("Drag to move the viewport without changing the layout")
                    }
                }
            }
            .defaultScrollAnchor(.center)
            .clipped()
        }
    }
}

private struct CanvasPanSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> CanvasPanView { CanvasPanView() }
    func updateNSView(_ view: CanvasPanView, context: Context) { }
}

private final class CanvasPanView: NSView {
    private var start: CGPoint?
    private var scrollOrigin = CGPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView else { return }
        start = event.locationInWindow
        scrollOrigin = scroll.contentView.bounds.origin
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        let delta = CGSize(width: event.locationInWindow.x - start.x, height: event.locationInWindow.y - start.y)
        let viewport = scroll.contentView
        let horizontal = document.frame.width > viewport.bounds.width + 0.5
        let vertical = document.frame.height > viewport.bounds.height + 0.5
        guard horizontal || vertical else { return }
        let proposed = CGRect(origin: CGPoint(
            x: horizontal ? scrollOrigin.x - delta.width : scrollOrigin.x,
            y: vertical ? scrollOrigin.y + (document.isFlipped ? delta.height : -delta.height) : scrollOrigin.y),
            size: viewport.bounds.size)
        // Hosting views can have nonzero origins. Let AppKit constrain its own
        // coordinates, and leave axes with no scrollable content exactly in place.
        var point = viewport.constrainBoundsRect(proposed).origin
        if !horizontal { point.x = scrollOrigin.x }
        if !vertical { point.y = scrollOrigin.y }
        viewport.scroll(to: point)
        scroll.reflectScrolledClipView(viewport)
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        NSCursor.openHand.set()
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
    @Environment(EditorModel.self) private var editor
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
                    if showCenterGuides && !(editor.isMovingDesktopWindow && settings.windowMode) {
                        CenterGuides()
                    }
                    if showCenterGuides && settings.windowMode && editor.isMovingDesktopWindow {
                        GeometryReader { guideGeometry in
                            if let screen = CompositionRenderer.screenRect(mockup: mockup, opening: opening,
                                canvas: guideGeometry.size, settings: settings) {
                                CenterGuides()
                                    .frame(width: screen.width, height: screen.height)
                                    .position(x: screen.midX, y: guideGeometry.size.height - screen.midY)
                            }
                        }
                        .allowsHitTesting(false)
                        .clipped()
                    }
                    if editor.isMovingDesktopWindow && settings.windowMode,
                       let screenshot {
                        DesktopWindowDragOverlay(screenshot: screenshot, mockup: mockup,
                                                 opening: opening, settings: $settings)
                    } else {
                        DeviceDragOverlay(screenshot: screenshot, mockup: mockup, settings: $settings)
                    }
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

private struct DesktopWindowDragOverlay: View {
    @Environment(EditorModel.self) private var editor
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    let screenshot: CGImage
    let mockup: CGImage?
    let opening: ScreenOpening?
    @Binding var settings: CompositionSettings
    @State private var dragOrigin: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            if let screen = CompositionRenderer.screenRect(mockup: mockup, opening: opening,
                                                           canvas: geometry.size, settings: settings) {
                let window = CompositionRenderer.desktopWindowRect(screenshot: screenshot, screen: screen,
                                                                    settings: settings.desktop)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .contentShape(Rectangle())
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: geometry.size.height - window.midY)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragOrigin == nil {
                                editor.beginEditing("Move Window")
                                dragOrigin = CGPoint(x: settings.desktop.windowX, y: settings.desktop.windowY)
                            }
                            guard let origin = dragOrigin else { return }
                            let travelX = screen.width - window.width
                            let travelY = screen.height - window.height
                            var desktop = settings.desktop
                            if travelX > 0.5 {
                                desktop.windowX = min(1, max(0, origin.x + value.translation.width / travelX))
                            }
                            if travelY > 0.5 {
                                desktop.windowY = min(1, max(0, origin.y + value.translation.height / travelY))
                            }
                            let snapped = CenterSnapping.position(
                                CGPoint(x: desktop.windowX, y: desktop.windowY),
                                canvas: CGSize(width: travelX, height: travelY), enabled: snapToCenter)
                            desktop.windowX = snapped.x; desktop.windowY = snapped.y
                            settings.desktop = desktop
                        }
                        .onEnded { _ in finishDrag() })
                    .help("Drag to move the window inside the device screen")
                    .accessibilityLabel("Move desktop window")
            }
        }
        .clipped()
        .onDisappear { finishDrag() }
    }

    private func finishDrag() {
        if dragOrigin != nil {
            dragOrigin = nil
            editor.endEditing()
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
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let rect = CompositionRenderer.foregroundRect(screenshot: screenshot, mockup: mockup,
                                                           canvas: geometry.size, settings: settings)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.blue.opacity(isDragging ? 0.8 : 0),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("deviceDragCanvas"))
                    .updating($isDragging) { _, dragging, _ in dragging = true }
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
                    .onEnded { _ in finishDrag() })
                .help("Drag to move the device and screenshot together")
                .accessibilityLabel("Drag to move the device; reset to center is available in Appearance")
                .position(x: rect.midX, y: geometry.size.height - rect.midY)
        }
        .coordinateSpace(name: "deviceDragCanvas")
        .clipped()
        .onChange(of: isDragging) { _, dragging in if !dragging { finishDrag() } }
        .onDisappear { finishDrag() }
    }

    private func finishDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        editor.endEditing()
    }
}

private struct HeadlineDragOverlay: View {
    @Environment(EditorModel.self) private var editor
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    @Binding var headline: HeadlineSettings
    @State private var dragOrigin: CGPoint?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            if let layout = HeadlineRenderer.layout(headline, canvas: geometry.size) {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.blue.opacity(isDragging ? 0.8 : 0),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: layout.rect.width + 12, height: layout.rect.height + 12)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("headlineDragCanvas"))
                        .updating($isDragging) { _, dragging, _ in dragging = true }
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
                        .onEnded { _ in finishDrag() })
                    .help("Drag to move the headline")
                    .accessibilityLabel("Drag to move the headline; reset position is available in the inspector")
                    .position(x: layout.rect.midX, y: layout.rect.midY)
            }
        }
        .coordinateSpace(name: "headlineDragCanvas")
        .clipped()
        .onChange(of: isDragging) { _, dragging in if !dragging { finishDrag() } }
        .onDisappear { finishDrag() }
    }

    private func finishDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        editor.endEditing()
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
    let info: String?
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, info: String? = nil) {
        self.title = title; _isOn = isOn; self.info = info
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                if let info {
                    Spacer(minLength: 4)
                    InspectorInfo(text: info)
                }
            }
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorInfo: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(text)
            .accessibilityLabel(text)
    }
}

private struct InspectorPane: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if model.isEditingProjectStyle {
                        InspectorCard("Project Style", systemImage: "paintbrush.pointed") {
                            HStack {
                                Button("Apply to All") { model.applyProjectStyleToAll() }
                                    .help("Link headline and effects for every device and screenshot. Frames, canvases, appearance, and headline positions stay unchanged. This can be undone.")
                                Spacer()
                                InspectorInfo(text: "Shared headline content, typography, and effects. Linked devices and screenshots update immediately. Headline size scales with each canvas; position stays local.")
                            }
                        }
                        InspectorCard("Headline", systemImage: "textformat") {
                            HeadlineSettingsView(settings: $model.projectStyleSettings, showsPosition: false)
                        }
                        InspectorCard("Effects", systemImage: "sparkles") {
                            EffectsSettings(effects: $model.projectStyleSettings.effects)
                        }
                    } else {
                        if model.selectedScreenshot == nil, let section = model.activeSection {
                            DeviceDefaultLayoutActions(model: model, section: section,
                                                       screenshotCount: model.screenshotsForExport(.device).count)
                                .id(section.id)
                        }
                        InspectorCard("Device & Canvas", systemImage: "iphone") {
                            MockupSettings(model: model)
                            Divider()
                            OutputSettings(settings: $model.settings, suggestion: model.suggestedCanvas)
                        }
                        InspectorCard("Appearance", systemImage: "paintpalette") {
                            LayoutSettings(settings: $model.settings)
                        }
                        InspectorCard("Headline", systemImage: "textformat") {
                            if model.activeSection != nil {
                                StyleInheritanceControl(model: model, component: .headline)
                                Divider()
                            }
                            HeadlineSettingsView(settings: $model.settings, styleEditable: model.activeSection == nil || !model.followsParentStyle(.headline))
                        }
                        InspectorCard("Effects", systemImage: "sparkles") {
                            if model.activeSection != nil {
                                StyleInheritanceControl(model: model, component: .effects)
                                Divider()
                            }
                            EffectsSettings(effects: $model.settings.effects)
                                .disabled(model.activeSection != nil && model.followsParentStyle(.effects))
                        }
                    }
                    if !model.warnings.isEmpty && !model.isEditingProjectStyle {
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

private struct StyleInheritanceControl: View {
    let model: EditorModel
    let component: StyleComponent

    var body: some View {
        InspectorSwitch("Use \(model.parentStyleName)", isOn: Binding(
            get: { model.followsParentStyle(component) },
            set: { model.setFollowsParentStyle($0, component: component) }),
            info: "Turn off to customize this card. Turn on to follow the shared style again.")
    }
}

private struct DeviceDefaultLayoutActions: View {
    let model: EditorModel
    let section: DeviceSection
    let screenshotCount: Int
    @State private var confirmApply = false

    var body: some View {
        InspectorCard("Default Layout", systemImage: "slider.horizontal.3") {
            HStack {
                Text(section.title).font(.subheadline.weight(.semibold))
                Spacer()
                InspectorInfo(text: "Changes here become the default for new screenshots. Apply the layout to update existing screenshots in this device section, keeping their individual headline text.")
            }
            Button("Apply to Existing Screenshots…") { confirmApply = true }
                .disabled(screenshotCount == 0)
                .help("Apply this layout to \(screenshotCount) screenshots in \(section.title)")
        }
        .confirmationDialog("Apply layout to \(screenshotCount) screenshots?", isPresented: $confirmApply) {
            Button("Apply Layout") { model.applyDeviceLayout(section.id) }
        } message: {
            Text("Updates the frame, canvas, appearance, headline styling, position, and effects for this device’s screenshots. Each screenshot’s headline text is kept. You can undo this change.")
        }
    }
}

private struct OutputSettings: View {
    @Binding var settings: CompositionSettings
    let suggestion: ScreenshotPreset.Suggestion?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Canvas", systemImage: "rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                InspectorInfo(text: "The final image size, including the frame and background."
                              + (suggestion?.size == settings.outputSize ? " Canvas matched to device frame." : ""))
            }
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
            if settings.preset.width < settings.preset.height {
                Picker("Orientation", selection: Binding(
                    get: { settings.outputSize.width > settings.outputSize.height },
                    set: { settings.landscape = $0 })) {
                    Text("Portrait").tag(false)
                    Text("Landscape").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if let suggestion, suggestion.size != settings.outputSize {
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
                HStack(spacing: 10) {
                    FrameThumbnail(image: model.selectedMockup?.image, imagePadding: 3)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.selectedMockup == nil ? "Choose Frame…" : "Change Frame…")
                            .font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.selectedFrameDisplayName ?? model.selectedMockup?.name
                             ?? "\(model.frameLibrary.frames.count) saved frames")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .help("Choose a device frame from your Frame Library")
            if model.selectedMockup != nil {
                if !model.selectedFrameIsInLibrary {
                    Button("Save this frame to library") { model.saveSelectedFrameToLibraryInBackground() }
                        .font(.caption)
                }
                ScreenCalibrationSettings(model: model)
            }
        }
    }
}

private struct DesktopBackdropSettings: View {
    @Binding var desktop: DesktopSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Desktop backdrop").font(.subheadline.weight(.semibold))
                    Spacer()
                    InspectorInfo(text: "Place a window screenshot on a gradient desktop inside the frame. Works best with transparent window captures.")
                }
                HStack {
                    Toggle("Desktop backdrop", isOn: $desktop.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    Spacer()
                    if desktop.enabled {
                        ColorPicker("Wallpaper start", selection: Binding(
                            get: { Color(nsColor: desktop.topColor) },
                            set: { desktop.topColor = NSColor($0) }), supportsOpacity: false)
                            .labelsHidden().help("Wallpaper start color")
                        ColorPicker("Wallpaper end", selection: Binding(
                            get: { Color(nsColor: desktop.bottomColor) },
                            set: { desktop.bottomColor = NSColor($0) }), supportsOpacity: false)
                            .labelsHidden().help("Wallpaper end color")
                    }
                }
            }

        }
    }
}

private struct ScreenshotPlacementSettings: View {
    @Environment(EditorModel.self) private var editor
    @Binding var settings: CompositionSettings

    var body: some View {
        @Bindable var editor = editor
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screenshot placement").font(.subheadline.weight(.semibold))
                Spacer()
                InspectorInfo(text: "Fit shows the whole screenshot. Fill crops to cover the screen. Window lets you resize and move the screenshot independently of the desktop backdrop.")
            }
            Picker("Screenshot placement", selection: $settings.screenshotPlacement) {
                ForEach(ScreenshotPlacement.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if settings.windowMode {
                ValueSlider(title: "Window size", value: $settings.desktop.windowScale, range: 0.2...1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Move Screenshot").font(.subheadline.weight(.semibold))
                        Spacer()
                        InspectorInfo(text: "Drag the screenshot inside the device screen. Turn off to move the full device. Turn off the hand tool before editing.")
                    }
                    HStack {
                        Toggle("Move Screenshot", isOn: $editor.isMovingDesktopWindow)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                        Spacer()
                        Button("Center Screenshot", systemImage: "arrow.counterclockwise") {
                            editor.beginEditing("Center Screenshot")
                            defer { editor.endEditing() }
                            settings.desktop.windowX = 0.5; settings.desktop.windowY = 0.5
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset screenshot position to center")
                    }
                }
                .disabled(editor.selectedScreenshot == nil)
                InspectorSwitch("Window shadow", isOn: $settings.desktop.shadow)
            }
        }
    }
}

private struct ScreenCalibrationSettings: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Adjust screen edges manually").font(.subheadline.weight(.semibold))
                    Spacer()
                    InspectorInfo(text: (model.opening != nil ? "Screen detected. " : "")
                        + "Automatic detection is recommended and preserves camera cutouts. Manual adjustment changes the blue outline’s width and height, moving opposite edges together around its current center. Corner rounding controls the manual screen’s rounded corners.")
                }
                HStack {
                    Toggle("Adjust screen edges manually", isOn: $model.manualCalibrationEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    Spacer()
                    if model.settings.manualScreen && model.opening != nil {
                        Button("Reset to Detected Screen", systemImage: "arrow.counterclockwise") {
                            model.resetScreenCalibration()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reset to the automatically detected screen")
                    }
                }
            }
            if model.settings.manualScreen {
                ValueSlider(title: "Width", value: screenSize(horizontal: true),
                            range: 0.1...maximumScreenSize(horizontal: true))
                ValueSlider(title: "Height", value: screenSize(horizontal: false),
                            range: 0.1...maximumScreenSize(horizontal: false))
                ValueSlider(title: "Corner rounding", value: $model.settings.cornerRadius, range: 0...0.25)
            }
        }.font(.caption)
    }

    private func maximumScreenSize(horizontal: Bool) -> Double {
        let center = horizontal
            ? (model.settings.screenLeft + model.settings.screenRight) / 2
            : (model.settings.screenTop + model.settings.screenBottom) / 2
        return max(0.1, 2 * min(center, 1 - center))
    }

    private func screenSize(horizontal: Bool) -> Binding<Double> {
        Binding {
            horizontal ? model.settings.screenRight - model.settings.screenLeft
                : model.settings.screenBottom - model.settings.screenTop
        } set: { value in
            var settings = model.settings
            let half = min(max(value, 0.1), maximumScreenSize(horizontal: horizontal)) / 2
            if horizontal {
                let center = (settings.screenLeft + settings.screenRight) / 2
                settings.screenLeft = center - half
                settings.screenRight = center + half
            } else {
                let center = (settings.screenTop + settings.screenBottom) / 2
                settings.screenTop = center - half
                settings.screenBottom = center + half
            }
            model.settings = settings
        }
    }
}

private struct LayoutSettings: View {
    @AppStorage(EditorPreferences.centerGuides) private var showCenterGuides = false
    @AppStorage(EditorPreferences.centerSnapping) private var snapToCenter = true
    @Binding var settings: CompositionSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Transparent background").font(.subheadline.weight(.semibold))
                HStack {
                    Toggle("Transparent background", isOn: $settings.transparentBackground)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    Spacer()
                    if !settings.transparentBackground {
                        ColorPicker("Background", selection: Binding(get: { Color(nsColor: settings.background) }, set: { settings.background = NSColor($0) }), supportsOpacity: false)
                            .labelsHidden()
                            .help("Background color")
                    }
                }
            }
            Divider()
            DesktopBackdropSettings(desktop: $settings.desktop)
            Divider()
            ScreenshotPlacementSettings(settings: $settings)
            Divider()
            ValueSlider(title: "Device scale", value: $settings.deviceScale, range: 0.4...1)
            DevicePositionSettings(settings: $settings)
            InspectorSwitch("Show center guides", isOn: $showCenterGuides)
            InspectorSwitch("Snap to center", isOn: $snapToCenter,
                            info: "Guides and snapping are editing aids. Align the device or headline on the canvas, or a window screenshot inside the device screen.")

        }
    }
}

private struct DevicePositionSettings: View {
    @Environment(EditorModel.self) private var editor
    @Binding var settings: CompositionSettings

    var body: some View {
        HStack {
            Text("Device position").font(.subheadline.weight(.semibold))
            Spacer()
            Button("Reset Device to Center", systemImage: "arrow.counterclockwise") {
                editor.beginEditing("Center Device")
                defer { editor.endEditing() }
                var centered = settings
                centered.deviceX = 0.5; centered.deviceY = 0.5
                settings = centered
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Reset device position to the center of the canvas")
            InspectorInfo(text: "Drag the device in the preview to move it with its screenshot. Use reset to center it on the canvas.")
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Corner glow").font(.subheadline.weight(.semibold))
                    Spacer()
                    InspectorInfo(text: "Add a soft glow from a corner of the canvas. Strength controls its opacity; size controls how far it spreads.")
                }
                HStack {
                    Toggle("Corner glow", isOn: $effects.cornerGlow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                    Spacer()
                    if effects.cornerGlow {
                        ColorPicker("Glow color", selection: $effects.pickerColor, supportsOpacity: false)
                            .labelsHidden()
                            .help("Glow color")
                    }
                }
            }
            if effects.cornerGlow {
                HStack {
                    Text("Corner").font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("Corner", selection: $effects.glowCorner) {
                        ForEach(GlowCorner.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                ValueSlider(title: "Glow strength", value: $effects.glowStrength, range: 0...1)
                ValueSlider(title: "Glow size", value: $effects.glowSpread, range: 0.2...1.5)
            }
            Divider()
            InspectorSwitch("Device fade", isOn: $effects.deviceFade,
                            info: "Fades the screenshot and frame together into the background, or into transparency for transparent PNGs. Depth controls how far the fade reaches; strength controls its intensity.")
            if effects.deviceFade {
                HStack {
                    Text("Fade edge").font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("Fade edge", selection: $effects.fadeEdge) {
                        ForEach(DeviceFadeEdge.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                ValueSlider(title: "Fade depth", value: $effects.fadeDepth, range: 0.1...0.8)
                ValueSlider(title: "Fade strength", value: $effects.fadeStrength, range: 0...1)
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

private struct HeadlineSettingsView: View {
    @Environment(EditorModel.self) private var editor
    @Binding var settings: CompositionSettings
    var showsPosition = true
    var styleEditable = true
    @State private var showsFontBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Show headline").font(.subheadline.weight(.semibold))
                        Spacer()
                        InspectorInfo(text: "Add up to two lines of text. Drag the headline in the preview to move it. Reduce device scale to leave more room above the device.")
                    }
                    HStack {
                        Toggle("Show headline", isOn: $settings.showHeadline)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                        Spacer()
                        if settings.headline.enabled {
                            ColorPicker("Headline color", selection: $settings.headline.pickerColor, supportsOpacity: false)
                                .labelsHidden()
                                .help("Headline text color")
                        }
                    }
                }
                if settings.headline.enabled {
                    TextField("First line", text: $settings.headline.firstLineInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("Subheadline (optional)", text: $settings.headline.secondLineInput)
                        .textFieldStyle(.roundedBorder)
                        .help("Subheadline text is always 75% of the main headline size.")
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                        GridRow {
                            Text("Font").font(.subheadline.weight(.semibold))
                            Button { showsFontBrowser = true } label: {
                                HStack {
                                    Text(settings.headline.fontFamily.isEmpty ? "System" : settings.headline.fontFamily)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .help("Browse fonts with your headline text")
                            .accessibilityLabel("Choose headline font")
                        }
                        GridRow {
                            Text("Weight").font(.subheadline.weight(.semibold))
                            Picker("Weight", selection: $settings.headline.weight) {
                                ForEach(HeadlineWeight.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Text("Size").font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                TextField("Font size in pixels", value: $settings.headlineFontSize,
                                          format: .number.precision(.fractionLength(0)))
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                Text("px").font(.caption).foregroundStyle(.secondary)
                                Stepper("Font size in pixels", value: $settings.headlineFontSize,
                                        in: settings.outputSize.width * 0.01...settings.outputSize.width * 0.15, step: 1)
                                    .labelsHidden()
                            }
                            .help("Text size in export pixels. Scales proportionally when the canvas size changes.")
                        }
                    }

                }
            }
            .disabled(!styleEditable)
            if showsPosition && settings.headline.enabled {
                Divider()
                HStack {
                    Text("Headline position").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Reset Headline Position", systemImage: "arrow.counterclockwise") {
                        editor.beginEditing("Reset Headline Position")
                        defer { editor.endEditing() }
                        var headline = settings.headline
                        headline.x = 0.5; headline.y = 0.055
                        settings.headline = headline
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Reset headline to the top center")
                    InspectorInfo(text: "Drag the headline in the preview to position it. Reset returns it to the top center of the canvas. Center guides and snapping also apply to the headline.")
                }
            }
        }
        .sheet(isPresented: $showsFontBrowser) {
            HeadlineFontBrowser(headline: settings.headline) { family in
                guard styleEditable else { return }
                editor.beginEditing("Change Headline Font")
                settings.headline.fontFamily = family
                editor.endEditing()
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
                Text(title).font(.subheadline.weight(.semibold))
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
    @State private var scope = ScreenshotExportScope.selected
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
                ExportPreview(model: model, options: exportOptions, scope: scope)
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    ExportFormatSettings(model: model, options: $exportOptions, exportAll: scope != .selected)
                    ExportSizeSettings(options: $exportOptions, exportAll: scope != .selected)
                    ExportScreenshotSettings(model: model, scope: $scope)
                }
                .disabled(model.isBusy || model.isChoosingExportLocation)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
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
                    .disabled(model.isBusy || model.isChoosingExportLocation)
                Button("Export…") {
                    if scope != .selected {
                        model.exportAll(options: exportOptions, scope: scope) { showsStatus = true }
                    } else {
                        model.exportSelected(options: exportOptions) { showsStatus = true }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport(scope))
            }.padding(16)
        }
        .onAppear { if model.selectedScreenshot == nil { scope = .device } }
        .frame(width: 760, height: 620)
        .interactiveDismissDisabled(model.isBusy || model.isChoosingExportLocation)
        .alert("Export failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

private struct ExportFormatSettings: View {
    @Bindable var model: EditorModel
    @Binding var options: ExportOptions
    let exportAll: Bool

    var body: some View {
        InspectorCard("Export settings", systemImage: "square.and.arrow.up") {
            HStack {
                Text("Format")
                Spacer()
                Picker("Format", selection: $model.jpeg) {
                    Text("PNG").tag(false)
                    Text("JPEG").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            if model.jpeg {
                HStack(spacing: 10) {
                    Text("Quality")
                    Slider(value: $options.jpegQuality, in: 0.1...1, step: 0.05)
                        .accessibilityLabel("JPEG quality")
                        .help("Lower quality produces smaller files; higher quality preserves more detail.")
                    Text(options.jpegQuality, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(.secondary).monospacedDigit().frame(width: 38, alignment: .trailing)
                }
            }
            if !exportAll && !model.jpeg {
                Toggle("Transparent background", isOn: $model.settings.transparentBackground)
                    .toggleStyle(.switch).controlSize(.small)
            }
            Text(exportAll ? "Uses each screenshot’s background settings."
                 : model.jpeg ? "JPEG uses the background color from Appearance."
                 : model.settings.transparentBackground ? "Transparent PNG. App Store uploads need an opaque background."
                 : "Opaque sRGB PNG with lossless compression.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            Text(options.scale < 1 ? "Use 100% to keep the selected App Store dimensions."
                 : "Export sizing leaves your saved layouts unchanged.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExportScreenshotSettings: View {
    let model: EditorModel
    @Binding var scope: ScreenshotExportScope

    var body: some View {
        InspectorCard("Screenshots", systemImage: "photo.on.rectangle") {
            Picker("Screenshots to export", selection: $scope) {
                Text("Selected Screenshot").tag(ScreenshotExportScope.selected)
                    .disabled(model.selectedScreenshot == nil)
                Text("Current Device (\(model.screenshotsForExport(.device).count))").tag(ScreenshotExportScope.device)
                Text("Entire Project (\(model.screenshots.count))").tag(ScreenshotExportScope.project)
            }
            .labelsHidden()
            Text(scope == .project ? "Organized into device folders in the folder you choose."
                 : scope == .device ? "\(model.activeSection?.title ?? "Device") screenshots, in sidebar order."
                 : model.selectedScreenshot?.name ?? "No screenshot selected")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct ExportPreview: View {
    let model: EditorModel
    let options: ExportOptions
    let scope: ScreenshotExportScope
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let sourceSettings = model.screenshotsForExport(scope).first.map { model.layout(for: $0.id).settings } ?? model.settings
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let shot = model.screenshotsForExport(scope).first
                let layout = shot.map { model.layout(for: $0.id) }
                let settings = options.settings(for: sourceSettings)
                let pixels = options.pixelSize(for: sourceSettings)
                let resolution = min(max(pixels.width, pixels.height),
                    PreviewResolution.maxDimension(canvas: settings.outputSize, viewport: geometry.size, displayScale: displayScale))
                if let shot,
                   let image = try? CompositionRenderer.render(screenshot: shot.image, mockup: model.mockups.first { $0.id == layout?.mockupID }?.image,
                                                               opening: model.screenOpening(for: layout?.mockupID), settings: settings,
                                                               maxDimension: resolution, forceOpaque: model.jpeg) {
                    ZStack {
                        if sourceSettings.transparentBackground && !model.jpeg { TransparencyGrid() }
                        Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
                    }
                    .aspectRatio(CGFloat(image.width) / CGFloat(image.height), contentMode: .fit)
                    .accessibilityLabel("Export preview")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("\(Int(options.pixelSize(for: sourceSettings).width)) × \(Int(options.pixelSize(for: sourceSettings).height)) px")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
