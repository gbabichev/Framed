import SwiftUI
import AppKit

private enum HeadlineFontCatalog {
    static let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// Font choices stay local until confirmed, matching the Frame Library's selection flow.
struct HeadlineFontBrowser: View {
    let headline: HeadlineSettings
    let apply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedFamily: String

    init(headline: HeadlineSettings, apply: @escaping (String) -> Void) {
        self.headline = headline
        self.apply = apply
        _selectedFamily = State(initialValue: headline.fontFamily)
    }

    private var families: [String] {
        var choices = [""] + HeadlineFontCatalog.families
        // Preserve a saved choice even if that font is no longer installed.
        if !headline.fontFamily.isEmpty && !choices.contains(headline.fontFamily) {
            choices.append(headline.fontFamily)
        }
        return search.isEmpty ? choices : choices.filter {
            ($0.isEmpty ? "System" : $0).localizedStandardContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a Font").font(.title2.bold())
                    Text("Find the right look for your headline.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search fonts", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20).padding(.bottom, 16)
            Divider()
            HStack(spacing: 0) {
                HeadlineFontGrid(families: families, headline: headline, selection: $selectedFamily)
                Divider()
                HeadlineFontDetail(family: selectedFamily, headline: headline)
                    .frame(width: 280)
            }
            Divider()
            HStack {
                Text("\(families.count) fonts").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use Font") { apply(selectedFamily); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered).controlSize(.regular).padding(20)
        }
        .frame(width: 860, height: 620)
    }
}

private struct HeadlineFontGrid: View {
    let families: [String]
    let headline: HeadlineSettings
    @Binding var selection: String

    var body: some View {
        ScrollView {
            if families.isEmpty {
                ContentUnavailableView.search
                    .frame(maxWidth: .infinity).padding(.top, 50)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(families, id: \.self) { family in
                        HeadlineFontTile(family: family, headline: headline,
                                         selected: selection == family) { selection = family }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
    }
}

private struct HeadlineFontTile: View {
    let family: String
    let headline: HeadlineSettings
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(family.isEmpty ? "System" : family)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                HeadlineFontSample(family: family, headline: headline, size: 23)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.isEmpty ? "System" : family)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(family.isEmpty ? "System" : family)
    }
}

private struct HeadlineFontSample: View {
    let family: String
    let headline: HeadlineSettings
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.05) {
            Text(headline.firstLine.trimmingCharacters(in: .whitespaces).isEmpty ? "Your headline" : headline.firstLine)
                .font(Font(HeadlineRenderer.font(family: family, weight: headline.weight, size: size)))
            if !headline.secondLine.isEmpty {
                Text(headline.secondLine)
                    .font(Font(HeadlineRenderer.font(family: family, weight: headline.weight, size: size * 0.75)))
            }
        }
        .foregroundStyle(.primary)
        .lineLimit(1).minimumScaleFactor(0.35)
        .accessibilityElement(children: .combine)
    }
}

private struct HeadlineFontDetail: View {
    let family: String
    let headline: HeadlineSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            HeadlineFontSample(family: family, headline: headline, size: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(family.isEmpty ? "System" : family).font(.headline)
            Text("\(headline.weight.title) · Subheadline at 75%")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

