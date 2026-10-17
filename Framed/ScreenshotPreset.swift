import Foundation
import CoreGraphics

nonisolated enum FrameDeviceFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case watch, iPhone, iPad, mac
    var id: Self { self }
    var title: String {
        switch self {
        case .watch: "Watch"
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }
    static func detect(in name: String) -> Self? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return nil }
        if first == "watch" || first == "aw" || (first == "apple" && words.dropFirst().first == "watch") { return .watch }
        if first == "iphone" { return .iPhone }
        if first == "ipad" { return .iPad }
        if ["mac", "macbook", "imac"].contains(first) { return .mac }
        return nil
    }
}

nonisolated struct ScreenshotPreset: Identifiable, Hashable, Codable, Sendable {
    let name: String
    let width: Int
    let height: Int
    var id: String { "\(name)-\(width)x\(height)" }
    var label: String { "\(name) · \(width) × \(height)" }
    func size(landscape: Bool) -> CGSize {
        landscape && width < height ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    struct Suggestion: Equatable {
        let preset: ScreenshotPreset
        let landscape: Bool
        var size: CGSize { preset.size(landscape: landscape) }
    }

    /// Match the screen opening, rather than the complete device artwork.
    /// Resolution breaks ties between accepted sizes with nearly identical proportions.
    static func suggestion(for screen: CGSize, family: FrameDeviceFamily? = nil) -> Suggestion? {
        guard screen.width.isFinite, screen.height.isFinite,
              screen.width > 0, screen.height > 0 else { return nil }
        let candidates = all.filter { family == nil || FrameDeviceFamily.detect(in: $0.name) == family }.flatMap { preset in
            (preset.width < preset.height ? [false, true] : [preset.width > preset.height]).map {
                Suggestion(preset: preset, landscape: $0)
            }
        }
        let ranked = candidates.map { candidate in
            let size = candidate.size
            let aspectError = abs(log((size.width / size.height) / (screen.width / screen.height)))
            let resolutionError = abs(log(size.width / screen.width)) + abs(log(size.height / screen.height))
            return (candidate, aspectError, resolutionError)
        }
        // Known device families always get an accepted canvas from that family.
        // MacBook screens with a menu-bar/notch area are slightly taller than the
        // App Store's 16:10 Mac canvases, so an exact aspect match is not expected.
        guard let closestAspect = ranked.map({ $0.1 }).min(), family != nil || closestAspect < 0.025 else { return nil }
        return ranked.filter { $0.1 <= closestAspect + 0.003 }
            .min { $0.2 < $1.2 }?.0
    }

    // Apple App Store Connect screenshot specifications, verified 2026-10-16.
    // Accepted dimensions only; required screenshot sets depend on the app's platforms.
    static let source = URL(string: "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications")!
    static let all: [Self] = [
        .init(name: "iPhone · Dynamic Island, medium", width: 1206, height: 2622),
        .init(name: "iPhone · Dynamic Island, medium", width: 1179, height: 2556),
        .init(name: "iPhone · Dynamic Island, large", width: 1320, height: 2868),
        .init(name: "iPhone · Dynamic Island, large", width: 1290, height: 2796),
        .init(name: "iPhone · Dynamic Island, large", width: 1260, height: 2736),
        .init(name: "iPhone Duo · Outer", width: 1398, height: 2034),
        .init(name: "iPhone Duo · Inner", width: 2007, height: 2853),
        .init(name: "iPhone · Face ID, large", width: 1284, height: 2778),
        .init(name: "iPhone · Face ID, large", width: 1242, height: 2688),
        .init(name: "iPhone · Face ID, medium", width: 1170, height: 2532),
        .init(name: "iPhone · Face ID, medium", width: 1125, height: 2436),
        .init(name: "iPhone · Face ID, medium", width: 1080, height: 2340),
        .init(name: "iPhone · Home button, large", width: 1242, height: 2208),
        .init(name: "iPhone · Home button, medium", width: 750, height: 1334),
        .init(name: "iPad · 13-inch", width: 2064, height: 2752),
        .init(name: "iPad · 13-inch / 12.9-inch", width: 2048, height: 2732),
        .init(name: "iPad · 11-inch", width: 1488, height: 2266),
        .init(name: "iPad · 11-inch", width: 1668, height: 2420),
        .init(name: "iPad · 11-inch", width: 1668, height: 2388),
        .init(name: "iPad · 11-inch", width: 1640, height: 2360),
        .init(name: "iPad · 10.5-inch", width: 1668, height: 2224),
        .init(name: "iPad · 9.7-inch", width: 1536, height: 2048),
        .init(name: "Mac", width: 1280, height: 800),
        .init(name: "Mac", width: 1440, height: 900),
        .init(name: "Mac", width: 2560, height: 1600),
        .init(name: "Mac", width: 2880, height: 1800),
        .init(name: "Apple TV", width: 1920, height: 1080),
        .init(name: "Apple TV / Vision Pro", width: 3840, height: 2160),
        .init(name: "Apple Watch · Ultra 4 / 3", width: 422, height: 514),
        .init(name: "Apple Watch · Ultra 2 / Ultra", width: 410, height: 502),
        .init(name: "Apple Watch · Series 12 / 11 / 10", width: 416, height: 496),
        .init(name: "Apple Watch · Series 9 / 8 / 7", width: 396, height: 484),
        .init(name: "Apple Watch · Series 6 / 5 / 4 / SE", width: 368, height: 448),
        .init(name: "Apple Watch · Series 3 / 2 / 1", width: 312, height: 390)
    ]
}
