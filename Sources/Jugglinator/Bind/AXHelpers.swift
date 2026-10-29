import AppKit
import ApplicationServices
import Foundation

/// A thin wrapper over the Accessibility API. All calls are safe without permission:
/// they simply return `nil`/empty values (AXError.apiDisabled).
enum AX {
    /// App response timeout, so a hung app doesn't block Jugglinator.
    static let messagingTimeout: Float = 0.5

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return error == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = attribute(element, name) as? [AnyObject] else { return [] }
        return value.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    /// URL from an attribute that can be either a CFURL or a string.
    static func urlString(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        if let url = value as? URL { return url.absoluteString }
        if let text = value as? String, !text.isEmpty { return text }
        return nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = application(pid: pid)
        return element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        elements(application(pid: pid), kAXWindowsAttribute)
    }

    static func title(of window: AXUIElement) -> String? {
        string(window, kAXTitleAttribute)
    }

    /// Raise a window: unminimize it, make it main and perform AXRaise.
    @discardableResult
    static func raise(_ window: AXUIElement, pid: pid_t) -> Bool {
        if let minimized = attribute(window, kAXMinimizedAttribute) as? Bool, minimized {
            set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        set(window, kAXMainAttribute, kCFBooleanTrue)
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        set(application(pid: pid), kAXFrontmostAttribute, kCFBooleanTrue)
        return raised
    }

    /// Enable the web content tree in an Electron app (`AXManualAccessibility`).
    /// Returns `true` if the app accepted the flag.
    @discardableResult
    static func enableManualAccessibility(pid: pid_t) -> Bool {
        set(application(pid: pid), "AXManualAccessibility", kCFBooleanTrue) == .success
    }

    /// URLs of the window's web areas (AXWebArea → AXURL) and the window's AXDocument.
    /// Traversal is limited by node count; we don't descend into web areas.
    static func webAreaURLs(in window: AXUIElement, maxNodes: Int = 1500) -> (urls: [String], foundWebArea: Bool) {
        var urls: [String] = []
        var foundWebArea = false
        if let document = urlString(window, kAXDocumentAttribute) { urls.append(document) }
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            let node = queue.removeFirst()
            visited += 1
            if string(node, kAXRoleAttribute) == "AXWebArea" {
                foundWebArea = true
                if let url = urlString(node, "AXURL") { urls.append(url) }
                continue
            }
            queue.append(contentsOf: elements(node, kAXChildrenAttribute))
        }
        return (urls, foundWebArea)
    }
}
