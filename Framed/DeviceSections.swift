import Foundation

nonisolated enum ProjectDevice: String, Codable, CaseIterable, Identifiable, Sendable {
    case iPhone, iPad, mac, watch, tv
    var id: Self { self }
    var title: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        case .watch: "Apple Watch"
        case .tv: "Apple TV"
        }
    }
    var symbol: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .mac: "laptopcomputer"
        case .watch: "applewatch"
        case .tv: "appletv"
        }
    }
    static func detect(_ name: String) -> Self {
        let name = name.lowercased()
        if name.contains("ipad") { return .iPad }
        if name.contains("mac") { return .mac }
        if name.contains("watch") { return .watch }
        if name.contains("tv") || name.contains("vision") { return .tv }
        return .iPhone
    }
    var defaultSettings: CompositionSettings {
        var settings = CompositionSettings()
        settings.preset = ScreenshotPreset.all.first { Self.detect($0.name) == self } ?? ScreenshotPreset.all[0]
        if self == .mac { settings.preset = ScreenshotPreset.all.first { $0.width == 2880 && $0.height == 1800 }! }
        return settings
    }
}

nonisolated struct DeviceSection: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var device: ProjectDevice
    var name: String? = nil
    var settings: ProjectSettings
    var mockupID: UUID?
    var styleOverrides: StyleOverrides? = nil
    var title: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? device.title : trimmed
    }
}

struct DeviceSidebarGroup: Identifiable {
    let section: DeviceSection
    let screenshots: [ImportedImage]
    var id: UUID { section.id }
}

nonisolated enum SidebarSelection: Hashable {
    case projectStyle, device(UUID), screenshot(UUID)
}

nonisolated enum ScreenshotExportScope: String, CaseIterable, Identifiable {
    case selected = "Selected", device = "Device", project = "Project"
    var id: Self { self }
}

/// A device can override the project; a screenshot can override its device.
nonisolated struct StyleOverrides: Codable, Equatable, Sendable {
    var headline = false
    var effects = false
    static let all = Self(headline: true, effects: true)
}

nonisolated enum StyleComponent { case headline, effects }

nonisolated struct ProjectStyle: Codable, Equatable, Sendable {
    var headline = HeadlineSettings()
    var effects = CompositionEffects()
}
