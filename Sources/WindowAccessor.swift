import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let layout: OverlayLayout
    let windowSize: CGSize
    let windowOrigin: NSPoint

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
        let frame = NSRect(
            x: windowOrigin.x,
            y: windowOrigin.y - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )
        guard window.frame != frame else { return }
        window.setFrame(frame, display: true, animate: false)
    }
}
