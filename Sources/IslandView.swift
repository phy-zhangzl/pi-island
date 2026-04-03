import SwiftUI
import Foundation

struct IslandView: View {
    let sessions: [AgentSession]
    let selectedSessionID: String
    let expanded: Bool
    let layout: OverlayLayout
    let hasBackgroundPi: Bool
    let activeSessionCount: Int
    let isPinnedExpanded: Bool
    let onIslandHoverChanged: (Bool) -> Void
    let onPanelHoverChanged: (Bool) -> Void
    let onTogglePinnedExpanded: () -> Void
    let onSelectSession: (String) -> Void

    @State private var isHoveringCapsule = false
    @State private var isHoveringPanel = false
    @State private var widthProgress: CGFloat = 0
    @State private var heightProgress: CGFloat = 0
    @State private var visualStateToken: Int = 0
    @State private var visualTransitionTask: DispatchWorkItem?
    @State private var capsuleHoverDebounceTask: DispatchWorkItem?
    @State private var panelHoverDebounceTask: DispatchWorkItem?
    private let hoverDebounceInterval: TimeInterval = 0.08
    private let panelExpandHeightDelay: TimeInterval = 0.04
    private let panelCollapseWidthDelay: TimeInterval = 0.14
    private let compactExpandWidthDelay: TimeInterval = 0.03

    private struct VisualPhaseKey: Equatable {
        let isLiveActivity: Bool
        let isExpanded: Bool
    }

    private var selectedSession: AgentSession? {
        sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first
    }

    private var realSessions: [AgentSession] {
        sessions.filter { $0.id != "mock-chatbot" }
    }

    private var activeSessions: [AgentSession] {
        realSessions.filter { $0.state.isLiveActivity }.sorted(by: sessionSort)
    }

    private var displaySessions: [AgentSession] {
        if realSessions.isEmpty {
            return Array(sessions.prefix(1))
        }

        if !activeSessions.isEmpty {
            return activeSessions
        }

        return Array(realSessions.sorted(by: sessionSort).prefix(1))
    }

    private var sessionCount: Int {
        if activeSessionCount > 0 {
            return activeSessionCount
        }
        return hasBackgroundPi ? 1 : 0
    }

    private var isShowingActiveOnly: Bool {
        !activeSessions.isEmpty
    }

    private var rowHeight: CGFloat { 88 }
    private var rowSpacing: CGFloat { 8 }
    private var panelContentHorizontalInset: CGFloat { 12 }
    private var capsuleContentHorizontalPadding: CGFloat { panelContentHorizontalInset + 10 }
    private var capsuleBadgeHorizontalPadding: CGFloat { 7 }
    private var capsuleBadgeVerticalPadding: CGFloat { 4 }
    private var expandedListTopPadding: CGFloat { 12 }
    private var expandedBottomPadding: CGFloat { 12 }
    private var capsuleHoverHorizontalPadding: CGFloat { 18 }
    private var capsuleHoverVerticalPadding: CGFloat { 10 }
    private var panelHoverBridgeHeight: CGFloat { 22 }

    private func compactDisplayState(for session: AgentSession) -> VibeState {
        session.state.isLiveActivity ? session.state : .idle
    }

    private var visibleRowCount: Int {
        max(1, min(displaySessions.count, 2))
    }

    private var expandedScrollHeight: CGFloat {
        CGFloat(visibleRowCount) * rowHeight + CGFloat(max(visibleRowCount - 1, 0)) * rowSpacing
    }

    private var expandedContainerHeight: CGFloat {
        layout.compactHeight + expandedListTopPadding + expandedScrollHeight + expandedBottomPadding
    }

    var body: some View {
        if let selectedSession {
            let isPiWorking = selectedSession.state.isLiveActivity
            let compactState = compactDisplayState(for: selectedSession)
            let visualKey = VisualPhaseKey(isLiveActivity: isPiWorking, isExpanded: expanded)
            let collapsedWidth = staticCompactWidth
            let expandedWidth = activeCompactWidth(for: selectedSession)
            let panelContentProgress = stagedProgress(heightProgress, start: 0.14, end: 0.68)
            let containerWidth = interpolate(from: collapsedWidth, to: expandedWidth, progress: widthProgress)
            let containerHeight = interpolate(from: layout.compactHeight, to: min(layout.expandedHeight, expandedContainerHeight), progress: heightProgress)
            let sharedContentWidth = expandedWidth - panelContentHorizontalInset * 2

            ZStack(alignment: .top) {
                unifiedShell(
                    width: containerWidth,
                    height: containerHeight,
                    accent: compactState.accentColor,
                    isActive: isPiWorking
                )

                Color.clear
                    .frame(
                        width: max(containerWidth + 24, sharedContentWidth + 24),
                        height: panelHoverBridgeHeight
                    )
                    .contentShape(Rectangle())
                    .offset(y: layout.compactHeight - panelHoverBridgeHeight * 0.5)
                    .onHover { isHovering in
                        handlePanelHover(isHovering)
                    }
                    .allowsHitTesting(expanded || heightProgress > 0.01)

                VStack(spacing: 0) {
                    capsuleContent(selectedSession, compactState: compactState)
                        .frame(width: containerWidth, height: layout.compactHeight, alignment: .center)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            handleCapsuleHover(isHovering)
                        }
                        .onTapGesture {
                            onTogglePinnedExpanded()
                        }

                    expandedContent(selectedSession, revealProgress: panelContentProgress)
                        .frame(width: sharedContentWidth, alignment: .top)
                        .frame(height: max(0, layout.expandedHeight - layout.compactHeight), alignment: .top)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            handlePanelHover(isHovering)
                        }
                        .clipped()
                        .opacity(panelContentProgress)
                        .offset(y: (1 - panelContentProgress) * -4)
                        .scaleEffect(0.994 + panelContentProgress * 0.006, anchor: .top)
                        .allowsHitTesting(expanded || heightProgress > 0.001)
                }
                .frame(width: containerWidth, height: containerHeight, alignment: .top)
            }
            .frame(width: layout.expandedWindowSize.width, height: layout.expandedWindowSize.height, alignment: .top)
            .onAppear {
                syncVisualState(for: visualKey, animated: false)
            }
            .onChange(of: visualKey) { nextKey in
                syncVisualState(for: nextKey, animated: true)
            }
        }
    }

    private var staticSideRegionWidth: CGFloat { max(38, min(46, layout.notchGapWidth * 0.18)) }
    private var staticCenterGap: CGFloat { layout.notchGapWidth }
    private var staticCompactWidth: CGFloat { staticSideRegionWidth * 2 + staticCenterGap }

    private func activeCompactWidth(for session: AgentSession) -> CGFloat {
        layout.panelWidth
    }

    private func handleCapsuleHover(_ isHovering: Bool) {
        guard isHoveringCapsule != isHovering else { return }
        isHoveringCapsule = isHovering
        debouncedIslandHover(isHovering)
    }

    private func handlePanelHover(_ isHovering: Bool) {
        let effectiveHover = (expanded || heightProgress > 0.001 || widthProgress > 0.12) && isHovering
        guard isHoveringPanel != effectiveHover else { return }
        isHoveringPanel = effectiveHover
        debouncedPanelHover(effectiveHover)
    }

    /// Debounce hover exit for capsule — uses its OWN task to avoid conflicts with panel debounce
    private func debouncedIslandHover(_ isHovering: Bool) {
        if isHovering {
            capsuleHoverDebounceTask?.cancel()
            capsuleHoverDebounceTask = nil
            onIslandHoverChanged(true)
        } else {
            let task = DispatchWorkItem { [onIslandHoverChanged] in
                onIslandHoverChanged(false)
            }
            capsuleHoverDebounceTask?.cancel()
            capsuleHoverDebounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDebounceInterval, execute: task)
        }
    }

    /// Debounce hover exit for panel — uses its OWN task to avoid conflicts with capsule debounce
    private func debouncedPanelHover(_ isHovering: Bool) {
        if isHovering {
            panelHoverDebounceTask?.cancel()
            panelHoverDebounceTask = nil
            onPanelHoverChanged(true)
        } else {
            let task = DispatchWorkItem { [onPanelHoverChanged] in
                onPanelHoverChanged(false)
            }
            panelHoverDebounceTask?.cancel()
            panelHoverDebounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverDebounceInterval, execute: task)
        }
    }

    private func syncVisualState(for key: VisualPhaseKey, animated: Bool) {
        visualStateToken += 1
        visualTransitionTask?.cancel()
        visualTransitionTask = nil

        let token = visualStateToken
        let targetWidth: CGFloat = (key.isLiveActivity || key.isExpanded) ? 1 : 0
        let targetHeight: CGFloat = key.isExpanded ? 1 : 0

        guard animated else {
            widthProgress = targetWidth
            heightProgress = targetHeight
            return
        }

        let isExpandingPanel = targetHeight > heightProgress
        let isCollapsingPanel = targetHeight < heightProgress
        let isWidthOnlyChange = targetHeight == heightProgress && targetWidth != widthProgress

        if isExpandingPanel {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                widthProgress = targetWidth
            }

            let task = DispatchWorkItem {
                guard visualStateToken == token else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    heightProgress = targetHeight
                }
                visualTransitionTask = nil
            }
            visualTransitionTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + panelExpandHeightDelay, execute: task)
            return
        }

        if isCollapsingPanel {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                heightProgress = targetHeight
            }

            if targetWidth != widthProgress {
                let task = DispatchWorkItem {
                    guard visualStateToken == token else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.94)) {
                        widthProgress = targetWidth
                    }
                    visualTransitionTask = nil
                }
                visualTransitionTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + panelCollapseWidthDelay, execute: task)
            }
            return
        }

        if isWidthOnlyChange {
            if targetWidth > widthProgress {
                let task = DispatchWorkItem {
                    guard visualStateToken == token else { return }
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.08)) {
                        widthProgress = targetWidth
                    }
                    visualTransitionTask = nil
                }
                visualTransitionTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + compactExpandWidthDelay, execute: task)
            } else {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.94)) {
                    widthProgress = targetWidth
                }
            }
        }
    }

    private func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private func stagedProgress(_ value: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        let normalized = (value - start) / (end - start)
        return min(max(normalized, 0), 1)
    }

    private func unifiedShell(width: CGFloat, height: CGFloat, accent: Color, isActive: Bool) -> some View {
        let activityProgress: CGFloat = isActive ? 1 : 0
        let compactBottomRadius = interpolate(from: 16, to: 18, progress: activityProgress)
        let shellBottomRadius = interpolate(from: compactBottomRadius, to: 24, progress: heightProgress)
        let compactStrokeOpacity = interpolate(from: 0.04, to: 0.06, progress: activityProgress)
        let shellStrokeOpacity = interpolate(from: compactStrokeOpacity, to: 0.08, progress: heightProgress)
        let compactGlowOpacity = interpolate(from: 0.06, to: 0.14, progress: activityProgress)
        let glowOpacity = interpolate(from: compactGlowOpacity, to: 0.2, progress: heightProgress)
        let shellBlur = interpolate(from: 1.2, to: 1.8, progress: heightProgress)
        let shellShadowRadius = interpolate(from: isActive ? 12 : 10, to: 16, progress: heightProgress)
        let shellShadowYOffset = interpolate(from: isActive ? 2.5 : 2, to: 4, progress: heightProgress)
        let shellShape = NotchShape(topRadius: 12, bottomRadius: shellBottomRadius)

        return shellShape
            .fill(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(hex: 0x050505),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shellShape
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(glowOpacity),
                                .clear,
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay(
                shellShape
                    .stroke(Color.white.opacity(shellStrokeOpacity), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                shellShape
                    .stroke(accent.opacity(interpolate(from: 0.08, to: 0.2, progress: activityProgress)), lineWidth: 0.8)
                    .blur(radius: shellBlur)
                    .mask {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .shadow(color: accent.opacity(interpolate(from: 0.02, to: 0.08, progress: activityProgress)), radius: shellShadowRadius, y: shellShadowYOffset)
            .frame(width: width, height: height)
    }

    private func capsuleContent(_ session: AgentSession, compactState: VibeState) -> some View {
        let isPiWorking = session.state.isLiveActivity
        let accent = compactState.accentColor

        return ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    PixelCatPet(color: accent, state: compactState)
                        .frame(width: 20, height: 20)
                }
                .frame(width: staticSideRegionWidth, alignment: .center)

                Spacer(minLength: staticCenterGap)

                HStack(spacing: 0) {
                    Text("\(sessionCount)")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, alignment: .center)
                }
                .frame(width: staticSideRegionWidth, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(isPiWorking ? 0 : 1)
            .scaleEffect(isPiWorking ? 0.985 : 1, anchor: .center)

            activeCapsuleSummary(session, accent: accent)
                .opacity(isPiWorking ? 1 : 0)
                .scaleEffect(isPiWorking ? 1 : 0.985, anchor: .center)
        }
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.06), value: isPiWorking)
    }

    private func activeCapsuleSummary(_ session: AgentSession, accent: Color) -> some View {
        let showsCompactContextBadge = layout.panelWidth >= 320
        let panelInfluence = heightProgress

        return ZStack {
            HStack(spacing: 10) {
                PixelCatPet(color: accent, state: session.state)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.04 - panelInfluence * 0.04)
                    .shadow(color: accent.opacity(interpolate(from: 0.18, to: 0.12, progress: panelInfluence)), radius: interpolate(from: 6, to: 4, progress: panelInfluence))

                if showsCompactContextBadge {
                    capsuleContextBadge(session, accent: accent)
                        .opacity(0.96 + panelInfluence * 0.04)
                        .scaleEffect(0.985 + panelInfluence * 0.015, anchor: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                capsuleStateBadge(session, accent: accent)
                    .opacity(1)
                    .scaleEffect(0.985 + panelInfluence * 0.015, anchor: .trailing)

                Text("\(max(sessionCount, 1))")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(0.92 + panelInfluence * 0.08)
                    .offset(y: -0.5 + panelInfluence * 0.5)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, capsuleContentHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func capsuleStateBadge(_ session: AgentSession, accent: Color) -> some View {
        HStack(spacing: 6) {
            PixelStatusBars(color: accent, state: session.state)
            Text(compactStatusLabel(for: session.state))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: 0xF3F6FC))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, capsuleBadgeHorizontalPadding)
        .padding(.vertical, capsuleBadgeVerticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: 0x060606))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(0.72), lineWidth: 1)
        )
        .overlay {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.14), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    @ViewBuilder
    private func capsuleContextBadge(_ session: AgentSession, accent: Color) -> some View {
        if let usage = contextUsageSummary(for: session) {
            capsuleMetricBadge(label: "ctx", value: usage, accent: accent, emphasized: true)
        } else {
            capsuleMetricBadge(label: "ctx", value: "--", accent: accent, emphasized: false)
        }
    }

    private func capsuleMetricBadge(label: String, value: String, accent: Color, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: 0x8B93A1))
            Text(value)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(emphasized ? .white : .white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, capsuleBadgeHorizontalPadding)
        .padding(.vertical, capsuleBadgeVerticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: 0x0A0A0A))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(emphasized ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func expandedContent(_ session: AgentSession, revealProgress: CGFloat) -> some View {
        let rows = displaySessions

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: isShowingActiveOnly && rows.count > 2) {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        let rowDelay = CGFloat(index) * 0.08
                        let rowProgress = stagedProgress(revealProgress, start: rowDelay, end: min(1, rowDelay + 0.5))

                        sessionRow(item)
                            .opacity(rowProgress)
                            .offset(y: (1 - rowProgress) * -8)
                    }
                }
                .padding(.top, expandedListTopPadding)
                .padding(.horizontal, panelContentHorizontalInset)
                .padding(.bottom, expandedBottomPadding)
            }
            .frame(height: expandedScrollHeight + expandedListTopPadding + expandedBottomPadding)
        }
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PiGlyph(color: session.state.accentColor)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()
                }

                Text(piStateLabel(for: session.state))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(session.state.accentColor)

                Text(session.detail)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE5E7EB))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let contextUsage = contextUsageSummary(for: session) {
                        Text(contextUsage)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(session.state.accentColor)
                            .lineLimit(1)
                    }

                    Text(session.cwd)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x8B93A1))
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(session.id == selectedSessionID ? session.state.accentColor.opacity(0.72) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(session.state.accentColor)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectSession(session.id)
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

    private func compactStatusLabel(for state: VibeState) -> String {
        switch state {
        case .thinking: return "thinking"
        case .reading: return "read"
        case .running: return "run"
        case .patching: return "edit"
        case .done: return "done"
        case .error: return "error"
        case .idle: return "idle"
        }
    }

    private func piStateLabel(for state: VibeState) -> String {
        compactStatusLabel(for: state)
    }

    @ViewBuilder
    private func contextUsageBadge(_ session: AgentSession, accent: Color) -> some View {
        if let usage = contextUsageSummary(for: session) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ctx")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8B93A1))
                Text(usage)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x0A0A0A))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("ctx")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8B93A1))
                Text("--")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x0A0A0A))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func contextUsageSummary(for session: AgentSession) -> String? {
        guard let used = session.contextTokens, used > 0 else { return nil }
        if let window = session.contextWindow, window > 0 {
            let pct = Int((Double(used) / Double(window) * 100).rounded())
            return "\(pct)%"
        }
        return compactTokenCount(used)
    }

    private func compactTokenCount(_ value: Int) -> String {
        if value < 1_000 { return "\(value)" }
        let abbreviated = Double(value) / 1_000
        if abbreviated >= 10 {
            return "\(Int(abbreviated.rounded()))k"
        }
        return String(format: "%.1fk", abbreviated)
    }
}

struct PiGlyph: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.16))
            Text("π")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

struct PixelCatPet: View {
    let color: Color
    let state: VibeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.24, paused: state == .idle)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 6)
            let frame = catFrame(tick: tick)

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let cols = frame.first?.count ?? 8
                let rows = frame.count
                let cell = max(1, floor((size - 4) / CGFloat(max(cols, rows))))
                let gap = max(0, floor(cell * 0.15))

                VStack(spacing: gap) {
                    ForEach(Array(frame.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: gap) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, bit in
                                Group {
                                    if bit == 1 {
                                        Rectangle()
                                            .fill(color)
                                            .frame(width: cell, height: cell)
                                            .overlay(alignment: .top) {
                                                Rectangle()
                                                    .fill(Color.white.opacity(0.14))
                                                    .frame(height: max(1, cell * 0.18))
                                            }
                                    } else if bit == 2 {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.92))
                                            .frame(width: cell, height: cell)
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }

    private func catFrame(tick: Int) -> [[Int]] {
        switch state {
        case .idle:
            return tick.isMultiple(of: 8) ? catIdleBlink : (tick % 4 < 2 ? catIdleA : catIdleB)
        case .thinking, .reading:
            return tick % 4 < 2 ? catWalkA : catWalkB
        case .running, .patching:
            return tick % 4 < 2 ? catRunA : catRunB
        case .done:
            return tick % 6 < 3 ? catHappyA : catHappyB
        case .error:
            return tick.isMultiple(of: 2) ? catAlertA : catAlertB
        }
    }

    private var catIdleA: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,1,0,0,0,1,0],
            [1,0,0,0,0,0,1]
        ]
    }

    private var catIdleB: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,1,0,0,0,1,1],
            [1,0,0,0,0,0,0]
        ]
    }

    private var catIdleBlink: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,0,1,0,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,1,0,0,0,1,0],
            [1,0,0,0,0,0,1]
        ]
    }

    private var catWalkA: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [1,0,1,0,1,0,1],
            [0,1,0,0,0,1,0]
        ]
    }

    private var catWalkB: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,1,0,1,0,1,0],
            [1,0,1,0,1,0,1]
        ]
    }

    private var catRunA: [[Int]] {
        [
            [0,1,0,0,0,1,0,0],
            [0,1,1,1,1,1,0,1],
            [1,1,2,1,2,1,1,0],
            [1,1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0,0],
            [1,0,1,0,1,0,1,0],
            [0,1,0,0,0,1,0,1]
        ]
    }

    private var catRunB: [[Int]] {
        [
            [0,1,0,0,0,1,0,1],
            [0,1,1,1,1,1,0,0],
            [1,1,2,1,2,1,1,1],
            [1,1,1,1,1,1,1,0],
            [0,1,1,1,1,1,0,0],
            [0,1,0,1,0,1,0,1],
            [1,0,1,0,1,0,1,0]
        ]
    }

    private var catHappyA: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,1,0,1,0,1,0],
            [1,0,0,0,0,0,1]
        ]
    }

    private var catHappyB: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [0,0,1,0,1,0,0],
            [0,1,0,0,0,1,0]
        ]
    }

    private var catAlertA: [[Int]] {
        [
            [1,0,0,0,0,0,1],
            [0,1,1,1,1,1,0],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [1,1,1,1,1,1,1],
            [0,1,0,1,0,1,0],
            [1,0,1,0,1,0,1]
        ]
    }

    private var catAlertB: [[Int]] {
        [
            [0,1,0,0,0,1,0],
            [1,1,1,1,1,1,1],
            [1,1,2,1,2,1,1],
            [1,1,1,1,1,1,1],
            [0,1,1,1,1,1,0],
            [1,0,1,0,1,0,1],
            [0,1,0,1,0,1,0]
        ]
    }
}

struct PixelStatusBars: View {
    let color: Color
    let state: VibeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.24, paused: state == .done || state == .idle)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 6)
            let levels = barLevels(tick: tick)

            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    VStack(spacing: 1.2) {
                        Spacer(minLength: 0)
                        ForEach(0..<4, id: \.self) { idx in
                            Rectangle()
                                .fill(idx >= 4 - level ? color : color.opacity(0.16))
                                .frame(width: 2.5, height: 2.5)
                        }
                    }
                }
            }
            .frame(width: 16, height: 12)
        }
    }

    private func barLevels(tick: Int) -> [Int] {
        switch state {
        case .thinking:
            return [1 + (tick % 3), 2 + ((tick + 1) % 2), 1 + ((tick + 2) % 3)]
        case .reading:
            return [1 + ((tick + 1) % 2), 3, 2]
        case .running:
            return [4, 2 + (tick % 2), 3]
        case .patching:
            return [2, 4, 2 + ((tick + 1) % 2)]
        case .done:
            return [1, 4, 1]
        case .error:
            return tick.isMultiple(of: 2) ? [4, 1, 4] : [1, 4, 1]
        case .idle:
            return [1, 1, 1]
        }
    }
}

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: bottomRadius, y: rect.height),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width - bottomRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height - bottomRadius),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.closeSubpath()
        return path
    }
}
