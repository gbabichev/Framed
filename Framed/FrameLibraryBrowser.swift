import SwiftUI

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
    @State private var selection: UUID?
    @State private var noFrame = false
    @State private var renameFrame: SavedFrame?
    @State private var renamedName = ""
    @State private var removeFrame: SavedFrame?

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
                    model.importImages(mockups: true, applyFrame: false) { id in
                        if let id { selection = id; noFrame = false }
                    }
                } label: {
                    Label("Import…", systemImage: "plus")
                }
            }.padding(20)
            Divider()
            HSplitView {
                FrameGrid(frames: filteredFrames, selection: selection, noFrame: noFrame,
                          select: { selection = $0; noFrame = $0 == nil },
                          rename: { renameFrame = $0; renamedName = $0.name },
                          remove: { removeFrame = $0 })
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                FrameDetails(frame: selectedFrame, noFrame: noFrame,
                             rename: { renameFrame = $0; renamedName = $0.name },
                             remove: { removeFrame = $0 })
                    .frame(width: 230)
            }
            Divider()
            HStack {
                Text("\(library.frames.count) frames").font(.caption).foregroundStyle(.secondary)
                if model.selectedMockup != nil && !model.selectedFrameIsInLibrary {
                    Button("Add Current Project Frame") {
                        model.saveSelectedFrameToLibraryInBackground { id in
                            if let id { selection = id; noFrame = false }
                        }
                    }.controlSize(.small)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(noFrame ? "Use No Frame" : "Use Frame") { applySelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!noFrame && selectedFrame == nil)
            }.padding(16)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 600)
        .disabled(model.isBusy || library.isImporting)
        .sheet(isPresented: Binding(get: { model.isPresentingFrameImport }, set: { _ in })) {
            FrameImportProgress(model: model, library: library)
                .environment(\.isEnabled, true)
        }
        .onAppear { selection = model.selectedLibraryFrameID; noFrame = model.selectedMockup == nil }
        .alert("Rename Frame", isPresented: Binding(get: { renameFrame != nil }, set: { if !$0 { renameFrame = nil } })) {
            TextField("Frame name", text: $renamedName)
            Button("Cancel", role: .cancel) { renameFrame = nil }
            Button("Rename") {
                guard let frame = renameFrame else { return }
                perform { try library.rename(frame, to: renamedName) }
                renameFrame = nil
            }
        }
        .confirmationDialog("Remove this frame from the library?", isPresented: Binding(get: { removeFrame != nil }, set: { if !$0 { removeFrame = nil } }), titleVisibility: .visible) {
            Button("Remove Frame", role: .destructive) {
                guard let frame = removeFrame else { return }
                perform { try library.remove(frame) }
                if selection == frame.id { selection = nil; noFrame = false }
                removeFrame = nil
            }
            Button("Cancel", role: .cancel) { removeFrame = nil }
        } message: {
            Text("Existing projects keep their own copies. You can import the frame again later.")
        }
        .alert("Frame Library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }

    private var filteredFrames: [SavedFrame] {
        search.isEmpty ? library.frames : library.frames.filter { $0.name.localizedStandardContains(search) }
    }
    private var selectedFrame: SavedFrame? { library.frames.first { $0.id == selection } }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { library.error = error.localizedDescription }
    }
    private func applySelection() {
        if noFrame { model.selectMockup(nil); dismiss() }
        else if let frame = selectedFrame {
            Task { @MainActor in
                if await model.useLibraryFrameInBackground(frame) { dismiss() }
                else { library.error = model.error; model.error = nil }
            }
        }
    }
}

private struct FrameGrid: View {
    let frames: [SavedFrame]
    let selection: UUID?
    let noFrame: Bool
    let select: (UUID?) -> Void
    let rename: (SavedFrame) -> Void
    let remove: (SavedFrame) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)], spacing: 16) {
                FrameTile(name: "No frame", image: nil, selected: noFrame) { select(nil) }
                ForEach(frames) { frame in
                    FrameTile(name: frame.name, image: frame.thumbnail, selected: selection == frame.id) { select(frame.id) }
                        .contextMenu {
                            Button("Rename…") { rename(frame) }
                            Button("Remove from Library…", role: .destructive) { remove(frame) }
                        }
                }
            }.padding(20)
            if frames.isEmpty {
                Text("Import PNG device frames to build your reusable library.")
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
