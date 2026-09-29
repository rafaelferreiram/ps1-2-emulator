import CoreGraphics
import Foundation

@main
struct ResponsiveLayoutTests {
    static func main() {
        let design = LauncherLayout.designSize
        let windowed = LauncherLayout(size: design)
        require(abs(windowed.scale - 1) < 0.001, "design window stays at 1×")
        fills(windowed, design)

        // MacBook Pro 14-inch default logical resolution, in points.
        let macBook14 = CGSize(width: 1512, height: 982)
        let maximized = LauncherLayout(size: macBook14)
        let dampened = 1 + (maximized.scale - 1) * 0.5
        require(maximized.scale > 1.3, "14-inch display scales the interface up")
        require(maximized.scale > dampened + 0.1, "maximized size does not stay near the windowed size")
        fills(maximized, macBook14)
        require(maximized.previewWidth * maximized.scale > windowed.previewWidth * 1.3,
                "preview grows to fill a 14-inch display")

        // Same MacBook with the "More Space" scaled resolution.
        let moreSpace = LauncherLayout(size: CGSize(width: 1800, height: 1169))
        require(moreSpace.scale > maximized.scale, "denser 14-inch scaling grows the interface further")
        fills(moreSpace, CGSize(width: 1800, height: 1169))

        let external = LauncherLayout(size: CGSize(width: 2560, height: 1440))
        require(external.scale > moreSpace.scale, "larger display scales further")
        fills(external, CGSize(width: 2560, height: 1440))

        let ultrawide = LauncherLayout(size: CGSize(width: 1720, height: 720))
        require(ultrawide.catalogColumns > maximized.catalogColumns, "wider display adds catalog columns")
        fills(ultrawide, CGSize(width: 1720, height: 720))

        let small = LauncherLayout(size: CGSize(width: 1000, height: 650))
        require(small.scale < 1, "smaller window scales down")
        fills(small, CGSize(width: 1000, height: 650))

        let empty = LauncherLayout(size: .zero)
        require(empty.scale == 1 && empty.canvasSize.width == design.width && empty.canvasSize.height == design.height,
                "empty size stays on the design canvas")
        print("ResponsiveLayoutTests passed")
    }

    private static func fills(_ layout: LauncherLayout, _ size: CGSize) {
        require(abs(layout.canvasSize.width * layout.scale - size.width) < 0.6, "fills width \(size.width)")
        require(abs(layout.canvasSize.height * layout.scale - size.height) < 0.6, "fills height \(size.height)")
    }

    private static func require(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL \(message)\n", stderr)
            exit(1)
        }
    }
}
