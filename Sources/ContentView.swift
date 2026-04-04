import SwiftUI
import Foundation
import AppKit

enum VibeState: String, CaseIterable, Identifiable, Codable {
    case idle
    case thinking
    case reading
    case running
    case patching
    case done
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .reading: return "read"
        case .running: return "run"
        case .patching: return "edit"
        case .done: return "done"
        case .error: return "error"
        }
    }

    var accentColor: Color {
        switch self {
        case .idle: return Color(hex: 0x6B7280)
        case .thinking: return Color(hex: 0xF3F4F6)
        case .reading: return Color(hex: 0x56CCF2)
        case .running: return Color(hex: 0xFFB020)
        case .patching: return Color(hex: 0xB26BFF)
        case .done: return Color(hex: 0x59F08B)
        case .error: return Color(hex: 0xFF5C7A)
        }
    }

    var isLiveActivity: Bool {
        switch self {
        case .thinking, .reading, .running, .patching:
            return true
        case .idle, .done, .error:
            return false
        }
    }
}

struct PiEventPayload: Codable {
    let source: String
    let sessionId: String
    let projectName: String
    let sessionName: String?
    let cwd: String
    let terminalApp: String?
    let terminalSessionID: String?
    let state: VibeState
    let detail: String?
    let contextTokens: Int?
    let contextWindow: Int?
    let timestamp: TimeInterval
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var workspaceName: String
    var name: String
    var cwd: String
    var terminalApp: String?
    var terminalSessionID: String?
    var state: VibeState
    var detail: String
    var contextTokens: Int?
    var contextWindow: Int?
    var updatedAt: TimeInterval
    var duration: String

    init(id: String, workspaceName: String, name: String, cwd: String = "", terminalApp: String? = nil, terminalSessionID: String? = nil, state: VibeState, detail: String, contextTokens: Int? = nil, contextWindow: Int? = nil, updatedAt: TimeInterval, duration: String = "now") {
        self.id = id
        self.workspaceName = workspaceName
        self.name = name
        self.cwd = cwd
        self.terminalApp = terminalApp
        self.terminalSessionID = terminalSessionID
        self.state = state
        self.detail = detail
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.updatedAt = updatedAt
        self.duration = duration
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [AgentSession]
    @Published var selectedSessionID: String
    @Published var isHoveringIsland = false
    @Published var isHoveringPanel = false
    @Published var isPinnedExpanded = false
    @Published private(set) var isIslandHoverPromotedToPanel = false
    @Published private(set) var isHoldingDynamicCapsuleOnExit = false
    @Published var lastEventText = "Waiting for pi events"
    @Published private(set) var hasBackgroundPi = false
    @Published private(set) var activeSessionCount = 0
    @Published private(set) var detectedSessions: [AgentSession] = []

    private let eventLogQueue = DispatchQueue(label: "vibe-island.event-log", qos: .utility)

    private var collapseWorkItem: DispatchWorkItem?
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private var islandHoverPromotionWorkItem: DispatchWorkItem?
    private var islandHoverExitWorkItem: DispatchWorkItem?
    private var panelCollapseToStaticWorkItem: DispatchWorkItem?
    private var lastIslandHoverActivationAt: TimeInterval = 0
    private let inactivityTimeout: TimeInterval = 12
    private let hoverExpandDelay: TimeInterval = 0.0
    private let hoverCollapseDelay: TimeInterval = 0.16
    private let islandHoverPanelPromotionDelay: TimeInterval = 0.16
    private let islandHoverExitGracePeriod: TimeInterval = 0.16

    init() {
        let now = Date().timeIntervalSince1970
        let seed = AgentSession(
            id: "mock-chatbot",
            workspaceName: "chatbot",
            name: "demo session",
            cwd: "/Users/zhenliangzhang/projects/chatbot",
            terminalApp: "iTerm2",
            terminalSessionID: nil,
            state: .idle,
            detail: "Waiting for real pi events",
            contextTokens: nil,
            contextWindow: nil,
            updatedAt: now,
            duration: "demo"
        )
        self.sessions = [seed]
        self.selectedSessionID = seed.id
        refreshCountsAndSelection()
    }

    var mergedSessions: [AgentSession] {
        sessions.filter { $0.id != "mock-chatbot" }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var shouldShowPanel: Bool {
        isHoveringPanel || isPinnedExpanded || (isHoveringIsland && isIslandHoverPromotedToPanel)
    }

    var isPanelPresented: Bool {
        presentationMode == .panel
    }

    var presentationContext: IslandPresentationContext {
        IslandPresentationContext(
            hasLiveActivity: activeSessionCount > 0,
            isHoveringIsland: isHoveringIsland,
            isHoveringPanel: isHoveringPanel,
            isPinnedPanel: isPinnedExpanded,
            isIslandHoverPromotedToPanel: isIslandHoverPromotedToPanel,
            isHoldingDynamicCapsuleOnExit: isHoldingDynamicCapsuleOnExit
        )
    }

    var presentationMode: IslandPresentationMode {
        resolvePresentationMode(from: presentationContext)
    }

    var visibleSessions: [AgentSession] {
        let merged = mergedSessions.sorted(by: sessionSort)
        let liveSessions = merged.filter { $0.state.isLiveActivity }
        if !liveSessions.isEmpty {
            return liveSessions.sorted(by: sessionSort)
        }

        if let latestBackgroundPi = merged.first {
            return [latestBackgroundPi]
        }

        return Array(sessions.prefix(1))
    }

    func apply(_ payload: PiEventPayload) {
        let identity = sessionIdentity(for: payload)
        let logLine = "[VibeIsland] event: \(payload.projectName)/\(payload.sessionName ?? payload.projectName) \(payload.state.rawValue) [id=\(identity)] \(payload.detail ?? "")\n"
        appendEventLog(logLine)

        let detail = payload.detail?.isEmpty == false ? payload.detail! : defaultDetail(for: payload.state)
        let resolvedSessionName = resolvedSessionName(from: payload)
        let session = AgentSession(
            id: identity,
            workspaceName: payload.projectName,
            name: resolvedSessionName,
            cwd: payload.cwd,
            terminalApp: payload.terminalApp,
            terminalSessionID: payload.terminalSessionID,
            state: payload.state,
            detail: detail,
            contextTokens: payload.contextTokens,
            contextWindow: payload.contextWindow,
            updatedAt: payload.timestamp,
            duration: relativeDuration(from: payload.timestamp)
        )

        if let index = sessions.firstIndex(where: { $0.id == identity }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }

        sessions.sort(by: sessionSort)
        if !isPinnedExpanded || selectedSessionID == identity {
            selectedSessionID = identity
        }
        lastEventText = "\(payload.projectName) / \(resolvedSessionName) · \(payload.state.title)"
        refreshCountsAndSelection()

        if payload.state == .idle {
            collapseWorkItem?.cancel()
            hoverExpandWorkItem?.cancel()
            hoverCollapseWorkItem?.cancel()
            if !shouldShowPanel {
                isPinnedExpanded = false
            }
        } else if payload.state == .done || payload.state == .error {
            isPinnedExpanded = true
            scheduleAutoCollapse(for: payload.state)
        }
    }

    func setIslandHovering(_ isHovering: Bool) {
        if isHovering {
            islandHoverExitWorkItem?.cancel()
            islandHoverExitWorkItem = nil

            guard !isHoveringIsland else {
                syncExpandedWithHoverState()
                return
            }

            isHoveringIsland = true
            isIslandHoverPromotedToPanel = false
            cancelPanelCollapseToStaticHold()
            lastIslandHoverActivationAt = Date().timeIntervalSince1970
            scheduleIslandHoverPanelPromotion()
            syncExpandedWithHoverState()
            return
        }

        islandHoverPromotionWorkItem?.cancel()
        islandHoverPromotionWorkItem = nil

        guard isHoveringIsland else {
            syncExpandedWithHoverState()
            return
        }

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastIslandHoverActivationAt
        let remainingGrace = islandHoverExitGracePeriod - elapsed

        let clearHover = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isHoveringIsland = false
                self.isIslandHoverPromotedToPanel = false
                self.syncExpandedWithHoverState()
            }
        }

        islandHoverExitWorkItem?.cancel()
        islandHoverExitWorkItem = clearHover

        if remainingGrace > 0, !isHoveringPanel, !isPinnedExpanded {
            DispatchQueue.main.asyncAfter(deadline: .now() + remainingGrace, execute: clearHover)
        } else {
            clearHover.perform()
        }
    }

    func setPanelHovering(_ isHovering: Bool) {
        isHoveringPanel = isHovering
        if isHovering {
            islandHoverPromotionWorkItem?.cancel()
            islandHoverPromotionWorkItem = nil
            cancelPanelCollapseToStaticHold()
            if isHoveringIsland {
                isIslandHoverPromotedToPanel = true
            }
        }
        syncExpandedWithHoverState()
    }

    func togglePinnedExpanded() {
        isPinnedExpanded.toggle()
        if isPinnedExpanded {
            cancelPanelCollapseToStaticHold()
        } else {
            promoteMostRelevantSessionIfNeeded()
        }
        syncExpandedWithHoverState()
    }

    func selectSession(_ id: String) {
        selectedSessionID = id
        isPinnedExpanded = true
        cancelPanelCollapseToStaticHold()
        syncExpandedWithHoverState()
    }

    func cancelScheduledCollapse() {
        hoverCollapseWorkItem?.cancel()
        hoverCollapseWorkItem = nil
    }

    func cancelScheduledExpand() {
        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
    }

    private func scheduleIslandHoverPanelPromotion() {
        islandHoverPromotionWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.isHoveringIsland, !self.isPinnedExpanded else { return }
                self.isIslandHoverPromotedToPanel = true
                self.syncExpandedWithHoverState()
            }
        }
        islandHoverPromotionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + islandHoverPanelPromotionDelay, execute: work)
    }

    func scheduleExpandAfterHoverEnter() {
        cancelScheduledCollapse()
        cancelScheduledExpand()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldShowPanel else { return }
            }
        }
        hoverExpandWorkItem = work

        if hoverExpandDelay <= 0 {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverExpandDelay, execute: work)
        }
    }

    func scheduleCollapseAfterHoverExit() {
        cancelScheduledExpand()
        cancelScheduledCollapse()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isHoveringIsland, !self.isHoveringPanel, !self.isPinnedExpanded else { return }
            }
        }
        hoverCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCollapseDelay, execute: work)
    }

    private func syncExpandedWithHoverState() {
        if shouldShowPanel {
            cancelPanelCollapseToStaticHold()
            scheduleExpandAfterHoverEnter()
        } else {
            scheduleCollapseAfterHoverExit()

            if activeSessionCount == 0, !isHoveringIsland, !isHoveringPanel, !isPinnedExpanded {
                schedulePanelCollapseToStaticHold()
            } else {
                cancelPanelCollapseToStaticHold()
            }
        }
    }

    private func schedulePanelCollapseToStaticHold() {
        panelCollapseToStaticWorkItem?.cancel()
        isHoldingDynamicCapsuleOnExit = true

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeSessionCount == 0, !self.shouldShowPanel, !self.isHoveringIsland, !self.isHoveringPanel, !self.isPinnedExpanded else { return }
                self.isHoldingDynamicCapsuleOnExit = false
                self.panelCollapseToStaticWorkItem = nil
            }
        }
        panelCollapseToStaticWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMotionTokens.panelCollapseToStaticHoldDelay, execute: work)
    }

    private func cancelPanelCollapseToStaticHold() {
        panelCollapseToStaticWorkItem?.cancel()
        panelCollapseToStaticWorkItem = nil
        isHoldingDynamicCapsuleOnExit = false
    }

    func refreshActivity() {
        let now = Date().timeIntervalSince1970
        var changed = false

        for index in sessions.indices {
            guard sessions[index].id != "mock-chatbot" else { continue }

            let isStale = now - sessions[index].updatedAt > inactivityTimeout
            let nextState: VibeState = isStale ? .idle : sessions[index].state
            let nextDetail = isStale ? "Waiting for pi events" : sessions[index].detail
            let nextDuration = relativeDuration(from: sessions[index].updatedAt)

            if sessions[index].state != nextState || sessions[index].detail != nextDetail || sessions[index].duration != nextDuration {
                sessions[index].state = nextState
                sessions[index].detail = nextDetail
                sessions[index].duration = nextDuration
                changed = true
            }
        }

        if changed {
            sessions.sort(by: sessionSort)
        }

        refreshCountsAndSelection()

        if activeSessionCount == 0, !isHoveringIsland, !isHoveringPanel, !isPinnedExpanded, isPanelPresented {
            collapseWorkItem?.cancel()
            hoverExpandWorkItem?.cancel()
            hoverCollapseWorkItem?.cancel()
        }
    }


    private func refreshCountsAndSelection() {
        let realSessions = sessions.filter { $0.id != "mock-chatbot" }
        let merged = realSessions.sorted(by: sessionSort)
        let nextHasBackgroundPi = !realSessions.isEmpty
        let nextActive = realSessions.filter { $0.state.isLiveActivity }.count

        // Only publish if actually changed — avoids unnecessary SwiftUI diffs
        if hasBackgroundPi != nextHasBackgroundPi {
            hasBackgroundPi = nextHasBackgroundPi
        }
        if activeSessionCount != nextActive {
            activeSessionCount = nextActive
        }

        // Selection: auto-follow the most relevant session unless user pinned the panel.
        let currentValid = merged.contains(where: { $0.id == selectedSessionID })
        if isPinnedExpanded, currentValid {
            // keep pinned selection
        } else if let first = merged.first {
            if selectedSessionID != first.id {
                selectedSessionID = first.id
            }
        } else {
            let fallback = sessions.first?.id ?? "mock-chatbot"
            if selectedSessionID != fallback {
                selectedSessionID = fallback
            }
        }

        if merged != detectedSessions {
            detectedSessions = merged
        }
    }

    private func promoteMostRelevantSessionIfNeeded() {
        let candidate = sessions
            .filter { $0.id != "mock-chatbot" }
            .sorted(by: sessionSort)
            .first?.id
        if let candidate, selectedSessionID != candidate {
            selectedSessionID = candidate
        }
    }

    private func sessionPriority(for session: AgentSession) -> Int {
        switch session.state {
        case .running: return 500
        case .patching: return 480
        case .reading: return 440
        case .thinking: return 400
        case .error: return 320
        case .done: return 220
        case .idle: return 100
        }
    }

    private func sessionSort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsPriority = sessionPriority(for: lhs)
        let rhsPriority = sessionPriority(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }

    private func appendEventLog(_ line: String) {
        eventLogQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = URL(fileURLWithPath: "/tmp/vibeisland-events.log")
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func scheduleAutoCollapse(for state: VibeState) {
        collapseWorkItem?.cancel()
        let delay: TimeInterval = state == .error ? 4.0 : 2.5
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Don't force-clear hover if user is actively hovering (#6 fix)
                guard !self.isHoveringIsland, !self.isHoveringPanel else { return }
                self.isPinnedExpanded = false
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func sessionIdentity(for payload: PiEventPayload) -> String {
        if !payload.sessionId.isEmpty {
            return "pi:\(payload.sessionId)"
        }
        if let terminalSessionID = payload.terminalSessionID, !terminalSessionID.isEmpty {
            return "terminal:\(terminalSessionID)"
        }
        return "fallback:\(payload.projectName):\(payload.cwd)"
    }

    private func resolvedSessionName(from payload: PiEventPayload) -> String {
        if let sessionName = payload.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionName.isEmpty {
            return sessionName
        }
        return "Untitled session"
    }

    private func defaultDetail(for state: VibeState) -> String {
        switch state {
        case .thinking: return "Processing request"
        case .reading: return "src/agent.ts"
        case .running: return "pnpm test"
        case .patching: return "Updating src/ui.ts"
        case .done: return "Task completed"
        case .error: return "Something went wrong"
        case .idle: return "Idle"
        }
    }

    private func relativeDuration(from timestamp: TimeInterval) -> String {
        let delta = max(0, Int(Date().timeIntervalSince1970 - timestamp))
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(delta / 60)m" }
        return "\(delta / 3600)h"
    }
}

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
