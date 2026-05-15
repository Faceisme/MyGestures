import AppKit
import CoreGraphics
import Foundation

enum DisplayCoordinateConverter {
    private static let cacheLock = NSLock()
    private static var cachedDesktopFrame: NSRect?
    private static var didRegisterScreenObserver = false

    static func eventLocationToOverlayPoint(_ point: CGPoint) -> CGPoint {
        eventLocationToTopLeftDesktopPoint(point)
    }

    static func eventLocationToAccessibilityPoint(_ point: CGPoint) -> CGPoint {
        eventLocationToTopLeftDesktopPoint(point)
    }

    private static func eventLocationToTopLeftDesktopPoint(_ point: CGPoint) -> CGPoint {
        let desktopFrame = desktopFrame()
        guard !desktopFrame.isEmpty else {
            return point
        }

        return CGPoint(
            x: desktopFrame.minX + point.x,
            y: desktopFrame.maxY - point.y
        )
    }

    private static func desktopFrame() -> NSRect {
        registerScreenObserverIfNeeded()

        cacheLock.lock()
        if let cachedDesktopFrame {
            cacheLock.unlock()
            return cachedDesktopFrame
        }
        cacheLock.unlock()

        let frame = NSScreen.screens.reduce(NSRect.zero) { partial, screen in
            partial.union(screen.frame)
        }

        cacheLock.lock()
        cachedDesktopFrame = frame
        cacheLock.unlock()

        return frame
    }

    private static func registerScreenObserverIfNeeded() {
        cacheLock.lock()
        guard !didRegisterScreenObserver else {
            cacheLock.unlock()
            return
        }
        didRegisterScreenObserver = true
        cacheLock.unlock()

        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            invalidateDesktopFrameCache()
        }
    }

    private static func invalidateDesktopFrameCache() {
        cacheLock.lock()
        cachedDesktopFrame = nil
        cacheLock.unlock()
    }
}
