import AppKit
import Foundation

final class GestureOverlayController {
    private var window: NSWindow?
    private let drawingView = GestureOverlayView()

    func show(points: [CGPoint]) {
        DispatchQueue.main.async {
            self.ensureWindow()
            self.drawingView.points = points
            self.window?.orderFrontRegardless()
        }
    }

    func update(points: [CGPoint]) {
        DispatchQueue.main.async {
            self.ensureWindow()
            self.drawingView.points = points
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.drawingView.points = []
            self.window?.orderOut(nil)
        }
    }

    private func ensureWindow() {
        let frame = Self.desktopFrame()

        if let window {
            if window.frame != frame {
                window.setFrame(frame, display: false)
            }
            return
        }

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = drawingView
        window.hasShadow = false

        self.window = window
    }

    private static func desktopFrame() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { partial, screen in
            partial.union(screen.frame)
        }
    }
}

private final class GestureOverlayView: NSView {
    var points: [CGPoint] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard points.count >= 2 else {
            return
        }

        let path = NSBezierPath()
        let origin = window?.frame.origin ?? .zero
        path.move(to: CGPoint(x: points[0].x - origin.x, y: points[0].y - origin.y))

        for point in points.dropFirst() {
            path.line(to: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }

        NSColor.systemTeal.setStroke()
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        if let last = points.last {
            let dotRect = NSRect(
                x: last.x - origin.x - 5,
                y: last.y - origin.y - 5,
                width: 10,
                height: 10
            )
            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2)).fill()
            NSColor.systemTeal.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}
