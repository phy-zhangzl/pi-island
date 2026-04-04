import SwiftUI
import Foundation

struct IslandMotionSnapshot: Equatable {
    var shellWidthProgress: CGFloat
    var panelHeightProgress: CGFloat
    var panelContentProgress: CGFloat

    static let `static` = IslandMotionSnapshot(shellWidthProgress: 0, panelHeightProgress: 0, panelContentProgress: 0)
    static let dynamic = IslandMotionSnapshot(shellWidthProgress: 1, panelHeightProgress: 0, panelContentProgress: 0)
    static let panel = IslandMotionSnapshot(shellWidthProgress: 1, panelHeightProgress: 1, panelContentProgress: 1)
}

@MainActor
final class IslandMotionCoordinator: ObservableObject {
    @Published private(set) var snapshot: IslandMotionSnapshot = .static

    private var appliedMode: IslandPresentationMode = .staticCapsule
    private var transitionToken: Int = 0
    private var scheduledTasks: [DispatchWorkItem] = []

    func apply(mode: IslandPresentationMode, animated: Bool) {
        guard animated else {
            cancelScheduledTasks()
            appliedMode = mode
            snapshot = snapshot(for: mode)
            return
        }

        guard mode != appliedMode else { return }

        transitionToken += 1
        let token = transitionToken
        let previousMode = appliedMode
        appliedMode = mode
        cancelScheduledTasks()

        switch (previousMode, mode) {
        case (.staticCapsule, .dynamicCapsule):
            animateShellWidth(to: 1, animation: IslandMotionTokens.shellExpand)

        case (.dynamicCapsule, .staticCapsule):
            animateShellWidth(to: 0, animation: IslandMotionTokens.shellCollapse)

        case (.dynamicCapsule, .panel):
            animateToPanel(token: token)

        case (.staticCapsule, .panel):
            animateShellWidth(to: 1, animation: IslandMotionTokens.panelExpandWidth)
            schedule(after: IslandMotionTokens.panelExpandHeightDelay, token: token) {
                self.animatePanelHeight(to: 1, animation: IslandMotionTokens.panelExpandHeight)
                self.animatePanelContent(to: 1, animation: IslandMotionTokens.panelContentReveal)
            }

        case (.panel, .dynamicCapsule):
            animateFromPanel(to: .dynamicCapsule, token: token)

        case (.panel, .staticCapsule):
            animateFromPanel(to: .staticCapsule, token: token)

        default:
            snapshot = snapshot(for: mode)
        }
    }

    private func animateToPanel(token: Int) {
        animateShellWidth(to: 1, animation: IslandMotionTokens.panelExpandWidth)
        schedule(after: IslandMotionTokens.panelExpandHeightDelay, token: token) {
            self.animatePanelHeight(to: 1, animation: IslandMotionTokens.panelExpandHeight)
            self.animatePanelContent(to: 1, animation: IslandMotionTokens.panelContentReveal)
        }
    }

    private func animateFromPanel(to mode: IslandPresentationMode, token: Int) {
        animatePanelContent(to: 0, animation: IslandMotionTokens.panelContentHide)
        animatePanelHeight(to: 0, animation: IslandMotionTokens.panelCollapseHeight)

        guard mode == .staticCapsule else { return }

        schedule(after: IslandMotionTokens.panelCollapseWidthDelay, token: token) {
            self.animateShellWidth(to: 0, animation: IslandMotionTokens.panelCollapseWidth)
        }
    }

    private func animateShellWidth(to value: CGFloat, animation: Animation) {
        withAnimation(animation) {
            snapshot.shellWidthProgress = value
        }
    }

    private func animatePanelHeight(to value: CGFloat, animation: Animation) {
        withAnimation(animation) {
            snapshot.panelHeightProgress = value
        }
    }

    private func animatePanelContent(to value: CGFloat, animation: Animation) {
        withAnimation(animation) {
            snapshot.panelContentProgress = value
        }
    }

    private func snapshot(for mode: IslandPresentationMode) -> IslandMotionSnapshot {
        switch mode {
        case .staticCapsule:
            return .static
        case .dynamicCapsule:
            return .dynamic
        case .panel:
            return .panel
        }
    }

    private func schedule(after delay: TimeInterval, token: Int, action: @escaping @MainActor () -> Void) {
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.transitionToken == token else { return }
            Task { @MainActor in
                action()
            }
        }
        scheduledTasks.append(task)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func cancelScheduledTasks() {
        scheduledTasks.forEach { $0.cancel() }
        scheduledTasks.removeAll()
    }
}
