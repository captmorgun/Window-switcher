import AppKit
import SwiftUI

final class WindowSwitcherPanel {
    static let shared = WindowSwitcherPanel()

    private var panel: NSPanel?

    private init() {}

    func show() {
        WindowSwitcher.shared.show()

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = false
            p.collectionBehavior = [.transient, .fullScreenAuxiliary]

            let view = NSHostingView(rootView: WindowSwitcherView())
            view.wantsLayer = true
            view.layer?.backgroundColor = .clear
            view.layer?.cornerRadius = 10
            view.layer?.masksToBounds = true
            p.contentView = view
            panel = p
        }

        reposition()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func reposition() {
        guard let panel else { return }
        // Size to fit content first
        panel.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = panel.contentView?.fittingSize ?? CGSize(width: 280, height: 200)
        let panelSize = CGSize(width: fittingSize.width, height: fittingSize.height)

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let origin = CGPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)
    }
}
