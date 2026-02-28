import ServiceManagement
import SwiftUI

@main
struct windowsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Windows Settings", id: "settings") {
            ContentView()
        }
        .defaultSize(width: 420, height: 600)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        if !AccessibilityHelper.isGranted() {
            AccessibilityHelper.requestAccess()
        }

        HotkeyManager.shared.start()

        // Layout auto-apply on startup is disabled — use "Apply All" button manually.

        // Hide the window after a short delay so the app stays running
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows where window.title == "Windows Settings" {
                window.orderOut(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let gap: CGFloat = 2.5
            let lineWidth: CGFloat = 1.2
            let half = rect.width / 2

            // квадраты: top-left, top-right, bottom-left, bottom-right
            let rects: [NSRect] = [
                NSRect(x: 0,        y: half + gap / 2, width: half - gap / 2, height: half - gap / 2),
                NSRect(x: half + gap / 2, y: half + gap / 2, width: half - gap / 2, height: half - gap / 2),
                NSRect(x: 0,        y: 0,              width: half - gap / 2, height: half - gap / 2),
                NSRect(x: half + gap / 2, y: 0,              width: half - gap / 2, height: half - gap / 2),
            ]

            NSColor.black.setFill()
            NSColor.black.setStroke()

            for (i, r) in rects.enumerated() {
                let path = NSBezierPath(rect: r)
                path.lineWidth = lineWidth
                if i == 0 {
                    path.fill()
                } else {
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = makeMenuBarIcon()
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Apply Layouts Now", action: #selector(applyLayouts), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Windows Settings" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func applyLayouts() {
        LayoutApplier.shared.applyAll()
    }

    @objc private func quit() {
        HotkeyManager.shared.stop()
        NSApp.terminate(nil)
    }
}
