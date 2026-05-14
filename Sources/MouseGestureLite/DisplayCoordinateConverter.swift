import AppKit
import CoreGraphics
import Foundation

enum DisplayCoordinateConverter {
    static func eventLocationToOverlayPoint(_ point: CGPoint) -> CGPoint {
        let desktopFrame = NSScreen.screens.reduce(NSRect.zero) { partial, screen in
            partial.union(screen.frame)
        }

        guard !desktopFrame.isEmpty else {
            return point
        }

        return CGPoint(
            x: desktopFrame.minX + point.x,
            y: desktopFrame.maxY - point.y
        )
    }
}
