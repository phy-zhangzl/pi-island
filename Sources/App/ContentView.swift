import SwiftUI
import Foundation
import AppKit

struct ContentView: View {
    private enum WindowFrameMode: Int {
        case staticCompact = 0
        case wideCompact = 1
        case expanded = 2

        init(presentationMode: IslandPresentationMode) {
            switch presentationMode {
            case .staticCapsule:
                self = .staticCompact
            case .dynamicCapsule:
                self = .wideCompact
            case .panel:
                self = .expanded
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    private let activityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var cachedLayout: OverlayLayout?
    @State private var windowFrameMode: WindowFrameMode = .staticCompact
    @State private var pendingWindowFrameModeTask: DispatchWorkItem?

    private var layout: OverlayLayout {
        if let cached = cachedLayout { return cached }
        return OverlayLayout.current() ?? OverlayLayout(screen: NSScreen.main!, calibration: .load())
    }

    private var desiredWindowFrameMode: WindowFrameMode {
        WindowFrameMode(presentationMode: model.presentationMode)
    }

    private var windowSize: CGSize {
        switch windowFrameMode {
        case .expanded:
            return layout.expandedWindowSize
        case .wideCompact:
            return CGSize(width: layout.expandedWindowSize.width, height: layout.compactHeight)
        case .staticCompact:
            return layout.compactWindowSize
        }
    }

    private var windowOrigin: NSPoint {
        switch windowFrameMode {
        case .expanded, .wideCompact:
            return layout.expandedOrigin
        case .staticCompact:
            return layout.compactOrigin
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            IslandView(
                sessions: model.visibleSessions,
                selectedSessionID: model.selectedSessionID,
                presentationMode: model.presentationMode,
                layout: layout,
                hasBackgroundPi: model.hasBackgroundPi,
                activeSessionCount: model.activeSessionCount,
                isPinnedExpanded: model.isPinnedExpanded,
                onIslandHoverChanged: { isHovering in
                    model.setIslandHovering(isHovering)
                },
                onPanelHoverChanged: { isHovering in
                    model.setPanelHovering(isHovering)
                },
                onTogglePinnedExpanded: {
                    model.togglePinnedExpanded()
                },
                onSelectSession: { id in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        model.selectSession(id)
                    }
                }
            )
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .background(WindowAccessor(layout: layout, windowSize: windowSize, windowOrigin: windowOrigin))
        .onReceive(activityTimer) { _ in
            model.refreshActivity()
        }
        .onAppear {
            cachedLayout = OverlayLayout.current() ?? OverlayLayout(screen: NSScreen.main!, calibration: .load())
            syncWindowFrameMode(to: desiredWindowFrameMode, animated: false)
        }
        .onChange(of: desiredWindowFrameMode) { nextMode in
            syncWindowFrameMode(to: nextMode, animated: true)
        }
    }

    private func syncWindowFrameMode(to nextMode: WindowFrameMode, animated: Bool) {
        pendingWindowFrameModeTask?.cancel()
        pendingWindowFrameModeTask = nil

        guard animated else {
            windowFrameMode = nextMode
            return
        }

        if nextMode.rawValue > windowFrameMode.rawValue {
            if windowFrameMode == .staticCompact, nextMode == .wideCompact {
                let task = DispatchWorkItem {
                    windowFrameMode = nextMode
                    pendingWindowFrameModeTask = nil
                }
                pendingWindowFrameModeTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + IslandMotionTokens.windowFrameWideExpandDelay, execute: task)
            } else {
                windowFrameMode = nextMode
            }
            return
        }

        let task = DispatchWorkItem {
            windowFrameMode = nextMode
            pendingWindowFrameModeTask = nil
        }
        pendingWindowFrameModeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMotionTokens.windowFrameCollapseDelay, execute: task)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
