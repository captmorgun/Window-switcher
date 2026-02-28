import AppKit

enum WindowManager {
    static func snapFocusedWindow(to region: SnapRegion) {
        guard let (window, screen) = focusedWindowAndScreen() else { return }
        let targetFrame = region.frame(on: screen, settings: AppSettings.shared)
        setWindowPosition(window, point: targetFrame.origin)
        setWindowSize(window, size: targetFrame.size)
    }

    // MARK: - Window Control Actions

    // Stores the pre-maximize frame per window (keyed by AXUIElement hash) for toggle restore
    private static var preMaximizeFrames: [UInt: CGRect] = [:]

    static func maximizeFocusedWindow() {
        guard let (window, screen) = focusedWindowAndScreen() else { return }
        let visible = screen.visibleFrame
        let primaryHeight = NSScreen.screens.first!.frame.height
        let axY = primaryHeight - visible.origin.y - visible.height
        let targetFrame = CGRect(x: visible.origin.x, y: axY, width: visible.width, height: visible.height)

        let key = CFHash(window)
        if let pos = getWindowPosition(window), let sz = getWindowSize(window) {
            let current = CGRect(origin: pos, size: sz)
            let alreadyMax = abs(current.width - targetFrame.width) < 2 &&
                             abs(current.height - targetFrame.height) < 2 &&
                             abs(current.origin.x - targetFrame.origin.x) < 2 &&
                             abs(current.origin.y - targetFrame.origin.y) < 2
            if alreadyMax {
                // Restore
                if let prev = preMaximizeFrames[key] {
                    setWindowPosition(window, point: prev.origin)
                    setWindowSize(window, size: prev.size)
                    preMaximizeFrames.removeValue(forKey: key)
                }
                return
            }
            preMaximizeFrames[key] = current
        }
        setWindowPosition(window, point: targetFrame.origin)
        setWindowSize(window, size: targetFrame.size)
    }

    static func minimizeAllWindows() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let wins = windowsRef as? [AXUIElement] else { continue }
            for win in wins {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    static func minimizeActiveWindow() {
        guard let (window, _) = focusedWindowAndScreen() else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func closeActiveWindow() {
        guard let (window, _) = focusedWindowAndScreen() else { return }
        var closeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeRef) == .success,
              let closeButton = closeRef else { return }
        AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
    }

    static func centerFocusedWindow() {
        snapFocusedWindow(to: .center)
    }

    // MARK: - Layout Applier support

    static func setWindowFrame(_ window: AXUIElement, region: SnapRegion, screen: NSScreen) {
        let frame = region.frame(on: screen, settings: AppSettings.shared)
        setWindowPosition(window, point: frame.origin)
        setWindowSize(window, size: frame.size)
    }

    // MARK: - Private

    private static func focusedWindowAndScreen() -> (AXUIElement, NSScreen)? {
        guard AccessibilityHelper.isGranted() else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let windowRef = focusedWindowRef else { return nil }
        let window = windowRef as! AXUIElement
        let screen = screenForWindow(window) ?? NSScreen.main ?? NSScreen.screens.first!
        return (window, screen)
    }

    private static func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return size
    }

    private static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let pos = getWindowPosition(window) else { return nil }

        let primaryHeight = NSScreen.screens.first!.frame.height

        // Convert AX point (top-left origin) to NSScreen coordinates (bottom-left origin)
        let nsY = primaryHeight - pos.y

        for screen in NSScreen.screens {
            if pos.x >= screen.frame.minX && pos.x < screen.frame.maxX
                && nsY >= screen.frame.minY && nsY < screen.frame.maxY
            {
                return screen
            }
        }
        return nil
    }

    private static func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
                == .success
        else {
            return nil
        }
        var point = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        return point
    }

    private static func setWindowPosition(_ window: AXUIElement, point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    private static func setWindowSize(_ window: AXUIElement, size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }
}
