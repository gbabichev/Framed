import Foundation

@main struct CanvasZoomChecks {
    static func main() {
        let canvas = CGSize(width: 2880, height: 1800)
        let viewport = CGSize(width: 600, height: 500)
        let fit = CanvasZoom.fit.size(canvas: canvas, viewport: viewport, displayScale: 2)
        precondition(fit.width <= viewport.width - 72 && fit.height <= viewport.height - 48)
        precondition(abs(fit.width / fit.height - canvas.width / canvas.height) < 0.00001)
        let actual = CanvasZoom.actual.size(canvas: canvas, viewport: viewport, displayScale: 2)
        precondition(actual == CGSize(width: 1440, height: 900), "100% must map an image pixel to a physical display pixel")
        let double = CanvasZoom.double.size(canvas: canvas, viewport: viewport, displayScale: 2)
        precondition(double == canvas)
        precondition(CanvasZoom.actual.size(canvas: canvas, viewport: viewport, displayScale: 1) == canvas)
        precondition(PreviewResolution.maxDimension(canvas: canvas, viewport: actual, displayScale: 2) == 2880,
                     "100% zoom must use native image resolution")
        precondition(PreviewResolution.maxDimension(canvas: canvas, viewport: double, displayScale: 2) == 2880,
                     "Zooming beyond native size must not generate unnecessary larger images")
        let tiny = CanvasZoom.fit.size(canvas: canvas, viewport: CGSize(width: 20, height: 20), displayScale: 2)
        precondition(tiny.width > 0 && tiny.height > 0)
        print("PASS: fitted canvas, Retina and standard 100% sizing, zoom proportions, native preview resolution, small viewports")
    }
}
