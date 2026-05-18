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

    static func visibleAccessibilityFrame(containingEventLocation point: CGPoint) -> CGRect {
        let accessibilityPoint = eventLocationToAccessibilityPoint(point)
        let screenFrames = NSScreen.screens.map { screen in
            accessibilityRect(fromAppKitRect: screen.visibleFrame)
        }

        if let frame = screenFrames.first(where: { $0.contains(accessibilityPoint) }) {
            return frame
        }

        return screenFrames.first ?? .zero
    }

    static func prewarm() {
        _ = desktopFrame()
        _ = visibleAccessibilityFrame(containingEventLocation: .zero)
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

    private static func accessibilityRect(fromAppKitRect rect: CGRect) -> CGRect {
        let desktopFrame = desktopFrame()
        guard !desktopFrame.isEmpty else {
            return rect
        }

        return CGRect(
            x: rect.minX,
            y: desktopFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
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
