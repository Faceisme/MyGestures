import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct GestureExecutionTarget {
    let policy: GestureTargetPolicy
    let pid: pid_t?
    let displayName: String
    let restoresOriginalFrontmostApplication: Bool

    var usesProcessPosting: Bool {
        pid != nil
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
                    restoresOriginalFrontmostApplication: true
                )
            }

            return GestureExecutionTarget(
                policy: policy,
                pid: nil,
                displayName: "未找到手势开始时的活动应用，已回退到系统前台",
                restoresOriginalFrontmostApplication: false
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
                restoresOriginalFrontmostApplication: false
            )
        }

        let window = windowElement(containing: element)
        if let window {
            raise(window: window)
        }

        guard let pid = processIdentifier(for: element) else {
            return GestureExecutionTarget(
                policy: .windowUnderPointer,
                pid: nil,
                displayName: "未找到鼠标指针下方应用，已回退到活动窗口",
                restoresOriginalFrontmostApplication: false
            )
        }

        let app = NSRunningApplication(processIdentifier: pid)
        app?.activate(options: [.activateAllWindows])

        let name = app?.localizedName
        return GestureExecutionTarget(
            policy: .windowUnderPointer,
            pid: nil,
            displayName: "鼠标指针下方并已切换：\(name?.isEmpty == false ? name! : "pid \(pid)")",
            restoresOriginalFrontmostApplication: false
        )
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

    private static func raise(window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
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
