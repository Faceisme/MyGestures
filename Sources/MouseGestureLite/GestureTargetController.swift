import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct GestureExecutionTarget {
    let policy: GestureTargetPolicy
    let pid: pid_t?
    let displayName: String
    let restoresOriginalFrontmostApplication: Bool
    let postsToProcess: Bool
    let deliveryDelay: TimeInterval
    let window: AXUIElement?
    let prefersDirectWindowClose: Bool

    var usesProcessPosting: Bool {
        postsToProcess && pid != nil
    }
}

enum GestureTargetController {
    private struct WindowCandidate {
        let pid: pid_t
        let windowID: CGWindowID
        let ownerName: String
        let title: String
        let bounds: CGRect
    }

    static func executionTarget(
        at point: CGPoint,
        policy: GestureTargetPolicy,
        frontmostApplicationAtGestureStart: NSRunningApplication?
    ) -> GestureExecutionTarget {
        switch policy {
        case .activeWindow:
            if let frontmostApplicationAtGestureStart {
                let name = frontmostApplicationAtGestureStart.localizedName
                return GestureExecutionTarget(
                    policy: policy,
                    pid: nil,
                    displayName: "手势开始时的活动应用：\(name?.isEmpty == false ? name! : "pid \(frontmostApplicationAtGestureStart.processIdentifier)")",
                    restoresOriginalFrontmostApplication: true,
                    postsToProcess: false,
                    deliveryDelay: 0,
                    window: nil,
                    prefersDirectWindowClose: false
                )
            }

            return GestureExecutionTarget(
                policy: policy,
                pid: nil,
                displayName: "未找到手势开始时的活动应用，已回退到系统前台",
                restoresOriginalFrontmostApplication: false,
                postsToProcess: false,
                deliveryDelay: 0,
                window: nil,
                prefersDirectWindowClose: false
            )

        case .windowUnderPointer:
            return targetUnderPointer(at: point)
        }
    }

    static func restoreFrontmostApplication(_ application: NSRunningApplication?) {
        guard let application,
              !application.isTerminated else {
            return
        }

        application.activate(options: [.activateAllWindows])
    }

    private static func targetUnderPointer(at point: CGPoint) -> GestureExecutionTarget {
        let accessibilityPoint = DisplayCoordinateConverter.eventLocationToAccessibilityPoint(point)
        DebugLogger.write("Target: lookup eventPoint=\(format(point)) axPoint=\(format(accessibilityPoint))")
        guard let element = elementAtPosition(accessibilityPoint) ?? fallbackElementAtOriginalPoint(point, accessibilityPoint: accessibilityPoint) else {
            DebugLogger.write("Target: no AX element at pointer, trying CGWindow fallback")
            if let candidate = windowCandidate(at: accessibilityPoint) ?? fallbackWindowCandidateAtOriginalPoint(point, accessibilityPoint: accessibilityPoint) {
                return target(from: candidate)
            }

            DebugLogger.write("Target: no CGWindow fallback at pointer")
            return fallbackTarget(reason: "未找到鼠标指针下方应用，已回退到活动窗口")
        }

        DebugLogger.write("Target: element \(elementSummary(element))")
        let window = windowElement(containing: element)
        DebugLogger.write("Target: window \(elementSummary(window))")
        let pid = window.flatMap(processIdentifier(for:)) ?? processIdentifier(for: element)
        guard let pid else {
            DebugLogger.write("Target: no pid for element/window")
            return GestureExecutionTarget(
                policy: .windowUnderPointer,
                pid: nil,
                displayName: "未找到鼠标指针下方应用，已回退到活动窗口",
                restoresOriginalFrontmostApplication: false,
                postsToProcess: false,
                deliveryDelay: 0,
                window: nil,
                prefersDirectWindowClose: false
            )
        }

        let rawApp = NSRunningApplication(processIdentifier: pid)
        let app = foregroundApplication(for: rawApp) ?? rawApp
        let isWeChatFamily = isWeChat(rawApp) || isWeChat(app)
        DebugLogger.write("Target: rawApp=\(applicationSummary(rawApp)) foregroundApp=\(applicationSummary(app)) isWeChatFamily=\(isWeChatFamily)")
        app?.activate(options: [.activateAllWindows])
        if let window {
            focus(window: window, pid: pid)
        }

        let name = app?.localizedName
        return GestureExecutionTarget(
            policy: .windowUnderPointer,
            pid: pid,
            displayName: "鼠标指针下方并已切换：\(name?.isEmpty == false ? name! : "pid \(pid)")",
            restoresOriginalFrontmostApplication: false,
            postsToProcess: false,
            deliveryDelay: isWeChatFamily ? 0.12 : 0.08,
            window: window,
            prefersDirectWindowClose: isWeChatFamily
        )
    }

    private static func target(from candidate: WindowCandidate) -> GestureExecutionTarget {
        DebugLogger.write("Target: CGWindow candidate id=\(candidate.windowID) pid=\(candidate.pid) owner=\(candidate.ownerName) title=\(candidate.title) bounds=\(format(candidate.bounds))")
        let rawApp = NSRunningApplication(processIdentifier: candidate.pid)
        let app = foregroundApplication(for: rawApp) ?? rawApp
        let isWeChatFamily = isWeChat(rawApp) || isWeChat(app) || isWeChatText(candidate.ownerName)
        let window = axWindow(matching: candidate)
        DebugLogger.write("Target: CGWindow rawApp=\(applicationSummary(rawApp)) foregroundApp=\(applicationSummary(app)) isWeChatFamily=\(isWeChatFamily) axWindow=\(elementSummary(window))")

        app?.activate(options: [.activateAllWindows])
        if let window {
            focus(window: window, pid: candidate.pid)
        }

        let name = app?.localizedName
        return GestureExecutionTarget(
            policy: .windowUnderPointer,
            pid: candidate.pid,
            displayName: "鼠标指针下方并已切换：\(name?.isEmpty == false ? name! : "pid \(candidate.pid)")",
            restoresOriginalFrontmostApplication: false,
            postsToProcess: false,
            deliveryDelay: isWeChatFamily ? 0.12 : 0.08,
            window: window,
            prefersDirectWindowClose: isWeChatFamily
        )
    }

    static func performDirectWindowCloseIfAvailable(
        for target: GestureExecutionTarget,
        shortcut: Shortcut
    ) -> Bool {
        let isCommandW = isCommandW(shortcut)
        DebugLogger.write("DirectClose: check prefers=\(target.prefersDirectWindowClose) isCommandW=\(isCommandW) hasWindow=\(target.window != nil) target=\(target.displayName)")
        guard target.prefersDirectWindowClose,
              isCommandW,
              let window = target.window else {
            return false
        }

        if let pid = target.pid {
            focus(window: window, pid: pid)
        }

        guard let closeButton = axElementAttribute(kAXCloseButtonAttribute, of: window) else {
            DebugLogger.write("DirectClose: close button missing window=\(elementSummary(window)) attrs=\(attributeNames(of: window))")
            return false
        }

        DebugLogger.write("DirectClose: close button \(elementSummary(closeButton))")
        let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        DebugLogger.write("DirectClose: AXPress result=\(result)")
        return result == .success
    }

    private static func elementAtPosition(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &element
        )

        guard result == .success else {
            return nil
        }
        return element
    }

    private static func fallbackElementAtOriginalPoint(_ point: CGPoint, accessibilityPoint: CGPoint) -> AXUIElement? {
        guard point != accessibilityPoint else {
            return nil
        }

        DebugLogger.write("Target: axPoint missed, retry eventPoint=\(format(point))")
        return elementAtPosition(point)
    }

    private static func windowCandidate(at point: CGPoint) -> WindowCandidate? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let onscreen = info[kCGWindowIsOnscreen as String] as? Bool,
                  onscreen,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0.01,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40,
                  bounds.height >= 40,
                  bounds.contains(point) else {
                continue
            }

            return WindowCandidate(
                pid: pid_t(pidNumber.intValue),
                windowID: CGWindowID(windowIDNumber.uint32Value),
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }

        return nil
    }

    private static func fallbackWindowCandidateAtOriginalPoint(_ point: CGPoint, accessibilityPoint: CGPoint) -> WindowCandidate? {
        guard point != accessibilityPoint else {
            return nil
        }

        DebugLogger.write("Target: CGWindow axPoint missed, retry eventPoint=\(format(point))")
        return windowCandidate(at: point)
    }

    private static func processIdentifier(for element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return pid
    }

    private static func axWindow(matching candidate: WindowCandidate) -> AXUIElement? {
        let app = AXUIElementCreateApplication(candidate.pid)
        guard let windows = axElementArrayAttribute(kAXWindowsAttribute, of: app) else {
            DebugLogger.write("Target: no AX windows for CGWindow pid=\(candidate.pid)")
            return nil
        }

        let matches = windows.compactMap { window -> (AXUIElement, CGFloat)? in
            guard let frame = frame(of: window) else {
                return nil
            }
            return (window, frameDistance(frame, candidate.bounds))
        }

        if let best = matches.min(by: { $0.1 < $1.1 }), best.1 <= 80 {
            return best.0
        }

        DebugLogger.write("Target: no AX window match for CGWindow bounds=\(format(candidate.bounds)) candidates=\(windows.map { elementSummary($0) }.joined(separator: " | "))")
        return nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, of: window),
              let size = sizeAttribute(kAXSizeAttribute, of: window) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func pointAttribute(_ name: String, of element: AXUIElement) -> CGPoint? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func sizeAttribute(_ name: String, of element: AXUIElement) -> CGSize? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func frameDistance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.minX - right.minX)
            + abs(left.minY - right.minY)
            + abs(left.width - right.width)
            + abs(left.height - right.height)
    }

    private static func foregroundApplication(for application: NSRunningApplication?) -> NSRunningApplication? {
        guard let application,
              let bundleIdentifier = application.bundleIdentifier else {
            return application
        }

        if isWeChatBundleIdentifier(bundleIdentifier),
           bundleIdentifier != "com.tencent.xinWeChat",
           let mainWeChat = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.tencent.xinWeChat" }) {
            return mainWeChat
        }

        return application
    }

    private static func windowElement(containing element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole {
            return element
        }

        if let window = axElementAttribute(kAXWindowAttribute, of: element) {
            return window
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let parent = current.flatMap({ axElementAttribute(kAXParentAttribute, of: $0) }) else {
                return nil
            }
            if role(of: parent) == kAXWindowRole {
                return parent
            }
            current = parent
        }

        return nil
    }

    private static func focus(window: AXUIElement, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        let appFrontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let appFocusedWindow = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
        let windowRaised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let windowMain = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let windowFocused = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        DebugLogger.write("Target: focus pid=\(pid) appFrontmost=\(appFrontmost) appFocusedWindow=\(appFocusedWindow) windowRaised=\(windowRaised) windowMain=\(windowMain) windowFocused=\(windowFocused)")
    }

    private static func isCommandW(_ shortcut: Shortcut) -> Bool {
        let flags = CGEventFlags(rawValue: CGEventFlags.RawValue(shortcut.modifierFlags))
        let shortcutFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        return shortcut.keyCode == VirtualKeyCode.w && flags.intersection(shortcutFlags) == .maskCommand
    }

    private static func isWeChat(_ application: NSRunningApplication?) -> Bool {
        guard let application else {
            return false
        }

        if let bundleIdentifier = application.bundleIdentifier,
           isWeChatBundleIdentifier(bundleIdentifier) {
            return true
        }

        let name = application.localizedName ?? ""
        return isWeChatText(name)
    }

    private static func isWeChatBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier.localizedCaseInsensitiveContains("wechat")
            || bundleIdentifier.localizedCaseInsensitiveContains("xinwechat")
    }

    private static func isWeChatText(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("微信")
            || text.localizedCaseInsensitiveContains("wechat")
    }

    private static func fallbackTarget(reason: String) -> GestureExecutionTarget {
        GestureExecutionTarget(
            policy: .windowUnderPointer,
            pid: nil,
            displayName: reason,
            restoresOriginalFrontmostApplication: false,
            postsToProcess: false,
            deliveryDelay: 0,
            window: nil,
            prefersDirectWindowClose: false
        )
    }

    private static func elementSummary(_ element: AXUIElement?) -> String {
        guard let element else {
            return "nil"
        }

        let pairs = [
            "pid=\(processIdentifier(for: element).map(String.init) ?? "nil")",
            "role=\(stringAttribute(kAXRoleAttribute, of: element))",
            "subrole=\(stringAttribute(kAXSubroleAttribute, of: element))",
            "title=\(stringAttribute(kAXTitleAttribute, of: element))",
            "description=\(stringAttribute(kAXDescriptionAttribute, of: element))",
            "identifier=\(stringAttribute("AXIdentifier", of: element))"
        ]
        return pairs.joined(separator: " ")
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String {
        guard let value = attribute(name, of: element) else {
            return "nil"
        }

        let text = String(describing: value)
            .replacingOccurrences(of: "\n", with: " ")
        return text.count > 120 ? String(text.prefix(120)) + "..." : text
    }

    private static func attributeNames(of element: AXUIElement) -> String {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success,
              let names else {
            return "unavailable(\(result))"
        }

        let strings = (names as NSArray).compactMap { $0 as? String }
        return strings.prefix(40).joined(separator: ",")
    }

    private static func applicationSummary(_ application: NSRunningApplication?) -> String {
        guard let application else {
            return "nil"
        }

        return "pid=\(application.processIdentifier) bundle=\(application.bundleIdentifier ?? "nil") name=\(application.localizedName ?? "nil") terminated=\(application.isTerminated)"
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }

    private static func format(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width)), \(Int(rect.height)))"
    }

    private static func role(of element: AXUIElement) -> String? {
        attribute(kAXRoleAttribute, of: element) as? String
    }

    private static func axElementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func axElementArrayAttribute(_ name: String, of element: AXUIElement) -> [AXUIElement]? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }

        return (value as! [Any]).compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            return (item as! AXUIElement)
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }
}
