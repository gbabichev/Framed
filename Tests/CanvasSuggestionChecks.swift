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
        print("Canvas suggestion checks passed")
    }
}
