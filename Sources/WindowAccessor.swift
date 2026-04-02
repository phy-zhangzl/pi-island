import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let layout: OverlayLayout
    let usesExpandedWindowLayout: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureOnce(window: window)
            updateFrame(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            updateFrame(window: window)
        }
    }

    /// One-time window chrome configuration. Only called in makeNSView.
    private func configureOnce(window: NSWindow) {
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isMovable = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.ignoresMouseEvents = false
    }

    /// Frame-only update, called on every SwiftUI state change.
    private func updateFrame(window: NSWindow) {
        let size = layout.expandedWindowSize
        let origin = layout.expandedOrigin
        let frame = NSRect(
            x: origin.x,
            y: origin.y - size.height,
            width: size.width,
            height: size.height
        )
        guard window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: false)
    }
}
