import SwiftUI
import AppKit

struct FrameThumbnail: View {
    let image: CGImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4))
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit().padding(8)
            } else {
                Image(systemName: "rectangle.dashed").font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

struct FrameLibraryBrowser: View {
    let model: EditorModel
    @Bindable var library: FrameLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var familyFilter: FrameDeviceFamily?
    @State private var selection = FrameSelection()
    @State private var multipleSelection = false
    @State private var noFrame = false
    @State private var renameFrame: SavedFrame?
    @State private var renamedName = ""
    @State private var pendingRemoval: Set<UUID>?
    @State private var removingAll = false
    @State private var preparationToken: UUID?
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame Library").font(.title2.bold())
                    Text("Import once. Use in any project.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search frames", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
                Button {
                    model.importImages(mockups: true) { id in
                        if let id { revealImportedFrame(id) }
                    }
                } label: {
                    Label("Import…", systemImage: "plus")
                }
            }.padding(20)
            Picker("Device family", selection: $familyFilter) {
                Text("All").tag(FrameDeviceFamily?.none)
                ForEach(FrameDeviceFamily.allCases) { family in
                    Text(family.title).tag(Optional(family))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.horizontal, 20).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            FrameManagementBar(multipleSelection: $multipleSelection, selectedCount: selection.ids.count,
                               hasFrames: !library.frames.isEmpty, hasVisibleFrames: !filteredFrames.isEmpty,
                               selectAll: { selection.selectAll(filteredFrames.map(\.id)); noFrame = false },
                               clear: { selection.clear(); noFrame = false },
                               removeSelected: { requestRemoval(selection.ids) },
                               removeAll: { requestRemoval(Set(library.frames.map(\.id)), all: true) })
            Divider()
            HSplitView {
                FrameGrid(frames: filteredFrames, hasLibraryFrames: !library.frames.isEmpty, selection: selection.ids, noFrame: noFrame,
                          select: selectFrame,
                          rename: { renameFrame = $0; renamedName = $0.name },
                          remove: { frame in
                              requestRemoval(selection.ids.contains(frame.id) ? selection.ids : [frame.id])
                          })
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                if selection.ids.count > 1 {
                    FrameBatchDetails(count: selection.ids.count) { requestRemoval(selection.ids) }
                        .frame(width: 230)
                } else {
                    FrameDetails(frame: selectedFrame, noFrame: noFrame,
                                 rename: { renameFrame = $0; renamedName = $0.name },
                                 remove: { requestRemoval([$0.id]) })
                        .frame(width: 230)
                }
            }
            Divider()
            HStack {
                Text(familyFilter != nil || !search.isEmpty ? "\(filteredFrames.count) of \(library.frames.count) frames" : "\(library.frames.count) frames")
                    .font(.caption).foregroundStyle(.secondary)
                if model.selectedMockup != nil && !model.selectedFrameIsInLibrary {
                    Button("Add Current Project Frame") {
                        model.saveSelectedFrameToLibraryInBackground { id in
                            if let id { revealImportedFrame(id) }
                        }
                    }.controlSize(.small)
                }
                Spacer()
                if preparationToken != nil && !isApplying {
                    ProgressView().controlSize(.small)
                        .help("Preparing the selected frame")
                        .accessibilityLabel("Preparing selected frame")
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(noFrame ? "Use No Frame" : "Use Frame") { applySelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!noFrame && selectedFrame == nil)
            }.padding(16)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 600)
        .disabled(model.isBusy || library.isImporting || library.isRemoving || isApplying)
        .overlay {
            if library.isRemoving {
                ProgressView("Removing frames…")
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if isApplying {
                ProgressView("Preparing frame…")
                    .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .interactiveDismissDisabled(library.isRemoving || isApplying)
        .sheet(isPresented: Binding(get: { model.isPresentingFrameImport }, set: { _ in })) {
            FrameImportProgress(model: model, library: library)
                .environment(\.isEnabled, true)
        }
        .onAppear {
            selection.selectAll(model.selectedLibraryFrameID.map { [$0] } ?? [])
            noFrame = model.selectedMockup == nil
        }
        .onChange(of: filteredFrames.map(\.id)) { _, ids in selection.retain(Set(ids)) }
        .task(id: selectedFrame) {
            guard let frame = selectedFrame else { preparationToken = nil; return }
            let token = UUID()
            preparationToken = token
            defer { if preparationToken == token { preparationToken = nil } }
            do {
                // Avoid decoding every frame while the user quickly browses thumbnails.
                try await Task.sleep(for: .milliseconds(120))
                try await model.prefetchLibraryFrame(frame)
            } catch { /* Cancellation and prefetch errors are handled by Use Frame if needed. */ }
        }
        .alert("Rename Frame", isPresented: Binding(get: { renameFrame != nil }, set: { if !$0 { renameFrame = nil } })) {
            TextField("Frame name", text: $renamedName)
            Button("Cancel", role: .cancel) { renameFrame = nil }
            Button("Rename") {
                guard let frame = renameFrame else { return }
                perform { try library.rename(frame, to: renamedName) }
                renameFrame = nil
            }
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button(removingAll ? "Remove All Frames" : removalButtonTitle, role: .destructive) {
                guard let ids = pendingRemoval else { return }
                pendingRemoval = nil
                Task { @MainActor in
                    await library.removeFrames(ids)
                    selection.retain(Set(library.frames.map(\.id)))
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(removingAll ? "This includes frames hidden by device or search filters. Existing projects keep their own copies. You can import frames again later." : "Existing projects keep their own copies. You can import these frames again later.")
        }
        .alert("Frame Library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }

    private var filteredFrames: [SavedFrame] {
        SavedFrame.filtered(library.frames, family: familyFilter, search: search)
    }
    private var selectedFrame: SavedFrame? {
        guard selection.ids.count == 1 else { return nil }
        return filteredFrames.first { selection.ids.contains($0.id) }
    }
    private func revealImportedFrame(_ id: UUID) {
        familyFilter = nil; search = ""
        selection.selectAll([id]); noFrame = false
    }
    private var removalTitle: String {
        let count = pendingRemoval?.count ?? 0
        if removingAll { return "Remove all \(count) frames from the library?" }
        return count == 1 ? "Remove this frame from the library?" : "Remove \(count) selected frames?"
    }
    private var removalButtonTitle: String {
        let count = pendingRemoval?.count ?? 0
        return count == 1 ? "Remove Frame" : "Remove \(count) Frames"
    }
    private func requestRemoval(_ ids: Set<UUID>, all: Bool = false) {
        guard !ids.isEmpty else { return }
        removingAll = all
        pendingRemoval = ids
    }
    private func selectFrame(_ id: UUID?) {
        guard let id else { selection.clear(); noFrame = true; return }
        let modifiers = NSEvent.modifierFlags
        selection.select(id, visible: filteredFrames.map(\.id),
                         toggle: multipleSelection || modifiers.contains(.command), extend: modifiers.contains(.shift))
        noFrame = false
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { library.error = error.localizedDescription }
    }
    private func applySelection() {
        guard !isApplying else { return }
        if noFrame { model.selectMockup(nil); dismiss() }
        else if let frame = selectedFrame {
            isApplying = true
            Task { @MainActor in
                defer { isApplying = false }
                if await model.useLibraryFrameInBackground(frame) { dismiss() }
                else { library.error = model.error; model.error = nil }
            }
        }
    }
}

private struct FrameManagementBar: View {
    @Binding var multipleSelection: Bool
    let selectedCount: Int
    let hasFrames: Bool
    let hasVisibleFrames: Bool
    let selectAll: () -> Void
    let clear: () -> Void
    let removeSelected: () -> Void
    let removeAll: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select Multiple", isOn: $multipleSelection).toggleStyle(.button)
                .help("Toggle selection by clicking thumbnails. Command-click toggles, Shift-click selects a range.")
            Button("Select All Shown", action: selectAll).disabled(!hasVisibleFrames)
            if selectedCount > 0 {
                Button("Deselect", action: clear)
            }
            Spacer(minLength: 0)
            Button("Remove Selected…", role: .destructive, action: removeSelected).disabled(selectedCount == 0)
            Menu {
                Button("Remove All Frames…", role: .destructive, action: removeAll)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(!hasFrames).help("More library actions")
        }
        .controlSize(.small)
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}

private struct FrameBatchDetails: View {
    let count: Int
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(.secondary)
            Text("\(count) frames selected").font(.headline)
            Text("Remove them together, or select one frame to preview and use it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Remove Selected…", role: .destructive, action: remove)
            Spacer()
        }.padding(20)
    }
}

private struct FrameGrid: View {
    let frames: [SavedFrame]
    let hasLibraryFrames: Bool
    let selection: Set<UUID>
    let noFrame: Bool
    let select: (UUID?) -> Void
    let rename: (SavedFrame) -> Void
    let remove: (SavedFrame) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)], spacing: 16) {
                FrameTile(name: "No frame", image: nil, selected: noFrame) { select(nil) }
                ForEach(frames) { frame in
                    FrameTile(name: frame.name, image: frame.thumbnail, selected: selection.contains(frame.id)) { select(frame.id) }
                        .contextMenu {
                            Button("Rename…") { rename(frame) }
                            Button(selection.contains(frame.id) && selection.count > 1 ? "Remove Selected Frames…" : "Remove from Library…", role: .destructive) { remove(frame) }
                        }
                }
            }.padding(20)
            if frames.isEmpty {
                Text(hasLibraryFrames ? "No matching frames. Try another device or search." : "Import PNG device frames to build your reusable library.")
                    .font(.callout).foregroundStyle(.secondary).padding(20)
            }
        }.background(.primary.opacity(0.025))
    }
}

private struct FrameTile: View {
    let name: String
    let image: CGImage?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                FrameThumbnail(image: image).frame(height: 130)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).padding(6)
                        }
                    }
                Text(name).font(.caption).lineLimit(3).multilineTextAlignment(.center)
                    .frame(height: 44, alignment: .top)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(name)
    }
}

private struct FrameDetails: View {
    let frame: SavedFrame?
    let noFrame: Bool
    let rename: (SavedFrame) -> Void
    let remove: (SavedFrame) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FrameThumbnail(image: frame?.thumbnail).frame(height: 240)
            if let frame {
                Text(frame.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text("\(frame.width) × \(frame.height) pixels").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Rename…") { rename(frame) }
                    Spacer()
                    Button(role: .destructive) { remove(frame) } label: { Image(systemName: "trash") }
                        .help("Remove from library")
                }.controlSize(.small)
            } else {
                Text(noFrame ? "No frame" : "Select a frame").font(.headline)
                Text(noFrame ? "Place the screenshot directly on your canvas." : "Click a thumbnail to inspect it before applying it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(16)
    }
}
