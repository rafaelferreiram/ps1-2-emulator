import CoreGraphics
import Foundation

/// Window dimensions are in macOS points, not panel pixels.
/// The 1100×700 design scales with the window, so a maximized 14-inch
/// MacBook and any other display fill the screen. Extra space on the
/// longer side becomes layout: wider grids and a larger preview.
struct LauncherLayout: Equatable {
    static let designSize = CGSize(width: 1100, height: 700)
    let scale: CGFloat
    let canvasSize: CGSize

    init(size: CGSize) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        // A hosting view can report an empty size before the window exists.
        guard width > 2, height > 2 else {
            scale = 1
            canvasSize = Self.designSize
            return
        }
        let fit = min(width / Self.designSize.width, height / Self.designSize.height)
        scale = fit
        canvasSize = CGSize(width: width / scale, height: height / scale)
    }

    var horizontalPadding: CGFloat { min(80, max(44, canvasSize.width * 63 / Self.designSize.width)) }
    var contentWidth: CGFloat { canvasSize.width - horizontalPadding * 2 }
    var catalogColumns: Int { min(10, max(3, Int((contentWidth - 10 + 16) / (172 + 16)))) }
    var catalogCoverHeight: CGFloat {
        let cardWidth = (contentWidth - 10 - CGFloat(catalogColumns - 1) * 16) / CGFloat(catalogColumns)
        return max(120, cardWidth - 18)
    }
    var stacksMenu: Bool { canvasSize.width / canvasSize.height < 1.15 }
    var menuWidth: CGFloat { contentWidth }
    var optionWidth: CGFloat { stacksMenu ? menuWidth : (menuWidth - 32) * 0.51 }
    var previewColumnWidth: CGFloat { stacksMenu ? menuWidth : menuWidth - optionWidth - 32 }
    var previewWidth: CGFloat { max(1, previewColumnWidth - 44) }
    var previewHeight: CGFloat { min(previewWidth * 0.75, max(298, canvasSize.height - 320)) }
}
