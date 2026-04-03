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
    @Published var expanded = false
    @Published var isHoveringIsland = false
    @Published var isHoveringPanel = false
    @Published var isPinnedExpanded = false
    @Published var lastEventText = "Waiting for pi events"
    @Published private(set) var hasBackgroundPi = false
    @Published private(set) var activeSessionCount = 0
    @Published private(set) var detectedSessions: [AgentSession] = []

    private let eventLogQueue = DispatchQueue(label: "vibe-island.event-log", qos: .utility)

    private var collapseWorkItem: DispatchWorkItem?
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var hoverCollapseWorkItem: DispatchWorkItem?
    private let inactivityTimeout: TimeInterval = 12
    private let hoverExpandDelay: TimeInterval = 0.0
    private let hoverCollapseDelay: TimeInterval = 0.16

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

    var shouldShowExpanded: Bool {
        isHoveringIsland || isHoveringPanel || isPinnedExpanded
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
            if !shouldShowExpanded {
                isPinnedExpanded = false
                setExpandedAnimated(false)
            }
        } else if payload.state == .done || payload.state == .error {
            setExpandedAnimated(true)
            scheduleAutoCollapse(for: payload.state)
        }
    }

    func setIslandHovering(_ isHovering: Bool) {
        isHoveringIsland = isHovering
        syncExpandedWithHoverState()
    }

    func setPanelHovering(_ isHovering: Bool) {
        isHoveringPanel = isHovering
        syncExpandedWithHoverState()
    }

    func togglePinnedExpanded() {
        isPinnedExpanded.toggle()
        if !isPinnedExpanded {
            promoteMostRelevantSessionIfNeeded()
        }
        syncExpandedWithHoverState()
    }

    func selectSession(_ id: String) {
        selectedSessionID = id
        isPinnedExpanded = true
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

    func scheduleExpandAfterHoverEnter() {
        cancelScheduledCollapse()
        cancelScheduledExpand()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.shouldShowExpanded else { return }
                self.setExpandedAnimated(true)
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
                self.setExpandedAnimated(false)
            }
        }
        hoverCollapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCollapseDelay, execute: work)
    }

    private func syncExpandedWithHoverState() {
        if shouldShowExpanded {
            scheduleExpandAfterHoverEnter()
        } else {
            scheduleCollapseAfterHoverExit()
        }
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

        if activeSessionCount == 0, !isHoveringIsland, !isHoveringPanel, !isPinnedExpanded, expanded {
            setExpandedAnimated(false)
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

    /// Single unified method for animated expand/collapse.
    /// All expand/collapse paths must go through this to avoid conflicting animations.
    private func setExpandedAnimated(_ value: Bool) {
        guard expanded != value else { return }
        // Use a single consistent spring so IslandView.syncVisualState
        // receives one clean onChange instead of competing animation contexts.
        expanded = value
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
                self.setExpandedAnimated(false)
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
    @EnvironmentObject private var model: AppModel
    private let activityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var cachedLayout: OverlayLayout?

    private var layout: OverlayLayout {
        if let cached = cachedLayout { return cached }
        return OverlayLayout.current() ?? OverlayLayout(screen: NSScreen.main!, calibration: .load())
    }

    private var selectedVisibleSession: AgentSession? {
        model.visibleSessions.first(where: { $0.id == model.selectedSessionID }) ?? model.visibleSessions.first
    }

    private var shouldUseExpandedWindow: Bool {
        model.expanded
    }

    private var shouldUseActiveCompactWindow: Bool {
        !model.expanded && (selectedVisibleSession?.state.isLiveActivity == true)
    }

    private var windowSize: CGSize {
        if shouldUseExpandedWindow {
            return layout.expandedWindowSize
        }
        if shouldUseActiveCompactWindow {
            return CGSize(width: layout.expandedWindowSize.width, height: layout.compactHeight)
        }
        return layout.compactWindowSize
    }

    private var windowOrigin: NSPoint {
        if shouldUseExpandedWindow || shouldUseActiveCompactWindow {
            return layout.expandedOrigin
        }
        return layout.compactOrigin
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            IslandView(
                sessions: model.visibleSessions,
                selectedSessionID: model.selectedSessionID,
                expanded: model.expanded,
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
        }
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
