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
        guard let element = elementAtPosition(point) else {
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

        let window = windowElement(containing: element)
        let pid = window.flatMap(processIdentifier(for:)) ?? processIdentifier(for: element)
        guard let pid else {
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

    static func performDirectWindowCloseIfAvailable(
        for target: GestureExecutionTarget,
        shortcut: Shortcut
    ) -> Bool {
        guard target.prefersDirectWindowClose,
              isCommandW(shortcut),
              let window = target.window else {
            return false
        }

        if let pid = target.pid {
            focus(window: window, pid: pid)
        }

        guard let closeButton = axElementAttribute(kAXCloseButtonAttribute, of: window) else {
            return false
        }

        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
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

    private static func processIdentifier(for element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return pid
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
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
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
        return name.localizedCaseInsensitiveContains("微信")
            || name.localizedCaseInsensitiveContains("wechat")
    }

    private static func isWeChatBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier.localizedCaseInsensitiveContains("wechat")
            || bundleIdentifier.localizedCaseInsensitiveContains("xinwechat")
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

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }
}
