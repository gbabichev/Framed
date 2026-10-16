import SwiftUI

struct FrameImportProgress: View {
    let model: EditorModel
    let library: FrameLibrary
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(library.isCancellingImport ? "Stopping import…" : "Importing Frames")
                .font(.headline)
            if library.isImporting {
                ProgressView(value: Double(library.importCompleted), total: Double(max(1, library.importTotal)))
                Text("\(library.importCompleted) of \(library.importTotal) processed")
                    .font(.callout).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
            }
            Text(library.isCancellingImport ? "Finishing the current operation. Completed frames will stay in your library." :
                    (library.importFilename.isEmpty ? "Preparing frame preview…" : library.importFilename))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel Import") { model.cancelFrameImport() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(library.isCancellingImport)
            }
        }
        .padding(24)
        .frame(width: 400)
        .interactiveDismissDisabled()
    }
}
