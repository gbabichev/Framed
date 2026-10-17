import Foundation

@main
struct CanvasSuggestionChecks {
    static func main() {
        func check(_ width: Double, _ height: Double, _ expectedWidth: Int, _ expectedHeight: Int) {
            let suggestion = ScreenshotPreset.suggestion(for: CGSize(width: width, height: height))
            precondition(suggestion?.size == CGSize(width: expectedWidth, height: expectedHeight),
                         "Unexpected suggestion for \(width) × \(height): \(String(describing: suggestion))")
        }
        // Screen detection is downsampled; allow a few pixels of measurement error.
        check(2004, 2851, 2007, 2853)
        check(2851, 2004, 2853, 2007)
        check(1395, 2033, 1398, 2034)
        // An open outer frame includes the device's back, but its screen remains portrait.
        check(1396, 2031, 1398, 2034)
        check(1179, 2556, 1179, 2556)
        check(1290, 2796, 1290, 2796)
        check(2048, 2732, 2048, 2732)
        check(2880, 1800, 2880, 1800)
        check(1920, 1080, 1920, 1080)
        precondition(ScreenshotPreset.suggestion(for: .zero) == nil)
        precondition(ScreenshotPreset.suggestion(for: CGSize(width: Double.nan, height: 100)) == nil)
        precondition(ScreenshotPreset.suggestion(for: CGSize(width: 1000, height: 1000)) == nil)
        let mac = ScreenshotPreset.suggestion(for: CGSize(width: 3456, height: 2234), family: .mac)!
        precondition(mac.preset.name == "Mac" && mac.size == CGSize(width: 2880, height: 1800) && mac.landscape,
                     "Notched MacBook screens must choose a landscape Mac canvas")
        for family in FrameDeviceFamily.allCases {
            let suggestion = ScreenshotPreset.suggestion(for: CGSize(width: 2266, height: 1488), family: family)!
            precondition(FrameDeviceFamily.detect(in: suggestion.preset.name) == family,
                         "A known family must never suggest another platform")
        }
        let ipad = ScreenshotPreset.suggestion(for: CGSize(width: 2732, height: 2048), family: .iPad)!
        precondition(ipad.size == CGSize(width: 2732, height: 2048) && ipad.landscape)
        print("Canvas suggestion checks passed")
    }
}
