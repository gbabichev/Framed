import Foundation

@main
struct CenterSnappingChecks {
    static func main() {
        let canvas = CGSize(width: 400, height: 800)
        func snap(_ x: CGFloat, _ y: CGFloat, enabled: Bool = true) -> CGPoint {
            CenterSnapping.position(CGPoint(x: x, y: y), canvas: canvas, enabled: enabled)
        }
        precondition(snap(0.515, 0.505) == CGPoint(x: 0.5, y: 0.5))
        precondition(snap(0.485, 0.2) == CGPoint(x: 0.5, y: 0.2), "Axes must snap independently")
        precondition(snap(0.2, 0.495) == CGPoint(x: 0.2, y: 0.5))
        precondition(snap(0.53, 0.52) == CGPoint(x: 0.53, y: 0.52), "Dragging away must release the snap")
        precondition(snap(0.515, 0.505, enabled: false) == CGPoint(x: 0.515, y: 0.505))
        precondition(snap(0, 1) == CGPoint(x: 0, y: 1))
        let small = CenterSnapping.position(CGPoint(x: 0.53, y: 0.51), canvas: CGSize(width: 200, height: 400), enabled: true)
        precondition(small == CGPoint(x: 0.5, y: 0.5), "The snap zone must use preview points rather than export pixels")
        let invalid = CenterSnapping.position(CGPoint(x: 0.51, y: 0.49), canvas: .zero, enabled: true)
        precondition(invalid == CGPoint(x: 0.51, y: 0.49))
        let travel = CGSize(width: 100, height: 40)
        let window = CenterSnapping.position(CGPoint(x: 0.57, y: 0.8), canvas: travel, enabled: true)
        precondition(window == CGPoint(x: 0.5, y: 0.8),
                     "Window snapping must use available travel: seven points snaps, twelve points does not")
        let screen = CGRect(x: 180, y: 50, width: 300, height: 200)
        let windowWidth: CGFloat = 200
        precondition(screen.minX + (screen.width - windowWidth) * window.x + windowWidth / 2 == screen.midX,
                     "A centered window must align with the screen center even in an off-center device")
        print("PASS: both center axes, independent snapping, release, disabled mode, consistent point threshold and zero-size handling")
    }
}
