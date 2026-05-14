import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private let mouseGestureEventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handle(proxy: proxy, type: type, event: event)
}

final class EventTapManager {
    var onStatusChange: ((String) -> Void)?
    var onGestureMatch: ((GestureMatch?) -> Void)?

    private enum InputState: String {
        case idle = "空闲"
        case pending = "等待判断"
        case gesturing = "手势中"
        case clickReplayedAwaitingUp = "已补发右键，等待松开"
        case cleanupAwaitingUp = "保险重置，等待松开"
    }

    private let store: GestureStore
    private let recognizer = GestureRecognizer()
    private let overlay = GestureOverlayController()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var state: InputState = .idle
    private var points: [CGPoint] = []
    private var displayPoints: [CGPoint] = []
    private var startPoint = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var passThroughAfterTimeoutUntilRightMouseUp = false
    private var decisionToken: UUID?
    private var gestureTimeoutToken: UUID?
    private var safetyToken: UUID?
    private var frontmostApplicationAtGestureStart: NSRunningApplication?
    private var lastFrontmostApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    private let movementThreshold: CGFloat = 10
    private let startTimeout: TimeInterval = 0.15
    private let safetyTimeout: TimeInterval = 8
    private let syntheticMarker: Int64 = 0x4D474C524550

    init(store: GestureStore = .shared) {
        self.store = store
        lastFrontmostApplication = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.state == .idle,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self.lastFrontmostApplication = application
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        stop()
    }

    func start() -> Bool {
        guard eventTap == nil else {
            return true
        }

        guard PermissionManager.isAccessibilityTrusted else {
            log("缺少辅助功能权限，无法启动主动右键拦截。")
            onStatusChange?("需要辅助功能权限")
            PermissionManager.requestAccessibilityPrompt()
            return false
        }

        let mask = eventMask(for: .rightMouseDown)
            | eventMask(for: .rightMouseDragged)
            | eventMask(for: .rightMouseUp)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseGestureEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("创建主动右键拦截失败，请检查辅助功能权限。")
            onStatusChange?("事件拦截启动失败")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        log("主动右键拦截已启动。普通右键会补发，右键拖动会进入手势模式。")
        onStatusChange?("监听中（主动拦截）")
        return true
    }

    func stop() {
        resetTracking(reason: "监听停止")

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }

        eventTap = nil
        runLoopSource = nil
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetTracking(reason: "系统禁用了事件 tap，已重置状态")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            log("事件 tap 被系统禁用后已自动重启")
            onStatusChange?("监听中（tap 已重启）")
            return nil
        }

        guard isRightMouseEvent(type) else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        if passThroughAfterTimeoutUntilRightMouseUp {
            if type == .rightMouseUp {
                passThroughAfterTimeoutUntilRightMouseUp = false
                return nil
            }
            if type == .rightMouseDragged {
                return Unmanaged.passUnretained(event)
            }
            passThroughAfterTimeoutUntilRightMouseUp = false
        }

        let location = event.location

        switch type {
        case .rightMouseDown:
            return handleRightMouseDown(at: location)
        case .rightMouseDragged:
            return handleRightMouseDragged(at: location, event: event)
        case .rightMouseUp:
            return handleRightMouseUp(at: location, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleRightMouseDown(at location: CGPoint) -> Unmanaged<CGEvent>? {
        if state != .idle {
            resetTracking(reason: "收到新的右键按下，重置旧状态")
        }

        state = .pending
        frontmostApplicationAtGestureStart = lastFrontmostApplication ?? NSWorkspace.shared.frontmostApplication
        startPoint = location
        lastPoint = location
        points = [location]
        displayPoints = [DisplayCoordinateConverter.eventLocationToOverlayPoint(location)]
        log("右键按下已拦截 raw=\(format(location)) display=\(format(displayPoints[0]))")
        armDecisionTimer()
        armGestureTimeoutTimer()
        armSafetyTimer()
        return nil
    }

    private func handleRightMouseDragged(at location: CGPoint, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch state {
        case .pending:
            appendPoint(location)

            let moved = distance(startPoint, location)
            if moved >= movementThreshold {
                state = .gesturing
                decisionToken = nil
                log("进入手势模式，移动距离 \(Int(moved))px")
                if store.preferences.showTrail {
                    overlay.show(points: displayPoints)
                }
            }
            return nil

        case .gesturing:
            appendPoint(location)
            if store.preferences.showTrail {
                overlay.update(points: displayPoints)
            }
            return nil

        case .clickReplayedAwaitingUp, .cleanupAwaitingUp:
            return nil

        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleRightMouseUp(at location: CGPoint, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch state {
        case .pending:
            replayRightClick(at: startPoint, reason: "未进入手势，补发普通右键")
            resetTracking(reason: "普通右键完成")
            return nil

        case .gesturing:
            appendPoint(location)
            let capturedPoints = points
            let capturedTargetPoint = startPoint
            let capturedFrontmostApplication = frontmostApplicationAtGestureStart
            let capturedDisplayPointsCount = displayPoints.count
            resetTracking(reason: "手势候选完成")
            log("右键松开，手势点数=\(capturedPoints.count)，显示点数=\(capturedDisplayPointsCount)，不补发右键菜单")

            DispatchQueue.main.async { [weak self] in
                self?.runGesture(
                    points: capturedPoints,
                    targetPoint: capturedTargetPoint,
                    frontmostApplicationAtGestureStart: capturedFrontmostApplication
                )
            }
            return nil

        case .clickReplayedAwaitingUp:
            resetTracking(reason: "物理右键松开，结束补发等待")
            return nil

        case .cleanupAwaitingUp:
            resetTracking(reason: "保险重置后的物理右键已松开")
            return nil

        case .idle:
            return Unmanaged.passUnretained(event)
        }
    }

    private func runGesture(
        points: [CGPoint],
        targetPoint: CGPoint,
        frontmostApplicationAtGestureStart: NSRunningApplication?
    ) {
        let threshold = CGFloat(store.preferences.recognitionThreshold)
        let match = recognizer.bestMatch(
            points: points,
            commands: store.gestures,
            threshold: threshold
        )

        onGestureMatch?(match)

        if let match {
            guard let shortcut = match.command.shortcut else {
                log("识别到 \(match.command.name)，但未设置快捷键，已跳过执行")
                return
            }

            let target = GestureTargetController.executionTarget(
                at: targetPoint,
                policy: store.preferences.gestureTargetPolicy,
                frontmostApplicationAtGestureStart: frontmostApplicationAtGestureStart
            )
            let delivery = target.usesProcessPosting ? "按进程投递" : "系统前台投递"
            log("识别到 \(match.command.name)，距离=\(String(format: "%.3f", Double(match.distance)))，目标=\(target.displayName)，方式=\(delivery)，执行快捷键=\(shortcut.displayName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if target.restoresOriginalFrontmostApplication {
                    GestureTargetController.restoreFrontmostApplication(frontmostApplicationAtGestureStart)
                }

                if let pid = target.pid {
                    ShortcutSynthesizer.send(shortcut, toPid: pid)
                } else {
                    ShortcutSynthesizer.send(shortcut)
                }

                if target.restoresOriginalFrontmostApplication {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        GestureTargetController.restoreFrontmostApplication(frontmostApplicationAtGestureStart)
                    }
                }
            }
        } else {
            let best = recognizer.bestCandidate(points: points, commands: store.gestures)
            if let best {
                log("未识别，最接近 \(best.command.name)，距离=\(String(format: "%.3f", Double(best.distance)))，阈值=\(threshold)")
            } else {
                log("未识别，没有可用候选，点数=\(points.count)")
            }
        }
    }

    private func replayRightClick(at point: CGPoint, reason: String) {
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ), let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else {
            log("补发普通右键失败")
            return
        }

        down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)

        log("\(reason) \(format(point))")
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private func appendPoint(_ point: CGPoint) {
        lastPoint = point
        points.append(point)
        displayPoints.append(DisplayCoordinateConverter.eventLocationToOverlayPoint(point))
    }

    private func resetTracking(reason: String) {
        state = .idle
        passThroughAfterTimeoutUntilRightMouseUp = false
        decisionToken = nil
        gestureTimeoutToken = nil
        safetyToken = nil
        points = []
        displayPoints = []
        frontmostApplicationAtGestureStart = nil
        startPoint = .zero
        lastPoint = .zero
        overlay.hide()
        log(reason)
    }

    private func armDecisionTimer() {
        let token = UUID()
        decisionToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + startTimeout) { [weak self] in
            guard let self,
                  self.decisionToken == token,
                  self.state == .pending else {
                return
            }

            self.replayRightClick(at: self.startPoint, reason: "150ms 内未移动，补发普通右键")
            self.state = .clickReplayedAwaitingUp
            self.decisionToken = nil
            self.log("已补发普通右键，等待物理右键松开")
        }
    }

    private func armSafetyTimer() {
        let token = UUID()
        safetyToken = token
        let timeout = max(safetyTimeout, store.preferences.gestureTimeoutSeconds + 2)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self,
                  self.safetyToken == token,
                  self.state != .idle else {
                return
            }

            self.state = .cleanupAwaitingUp
            self.decisionToken = nil
            self.points = []
            self.displayPoints = []
            self.overlay.hide()
            self.log("保险重置，继续吞掉事件直到物理右键松开")
        }
    }

    private func armGestureTimeoutTimer() {
        let token = UUID()
        gestureTimeoutToken = token
        let timeout = max(0.5, store.preferences.gestureTimeoutSeconds)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self,
                  self.gestureTimeoutToken == token,
                  self.state == .gesturing else {
                return
            }

            self.resetTracking(reason: "超时手势已取消")
            self.passThroughAfterTimeoutUntilRightMouseUp = true
            self.onGestureMatch?(nil)
            self.onStatusChange?("本次手势超时，已取消")
            self.log("手势超过 \(String(format: "%.1f", timeout)) 秒，已取消")
        }
    }

    private func isRightMouseEvent(_ type: CGEventType) -> Bool {
        type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp
    }

    private func eventMask(for type: CGEventType) -> CGEventMask {
        CGEventMask(1) << CGEventMask(type.rawValue)
    }

    private func distance(_ left: CGPoint, _ right: CGPoint) -> CGFloat {
        hypot(left.x - right.x, left.y - right.y)
    }

    private func format(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }

    private func log(_ message: String) {
    }
}
