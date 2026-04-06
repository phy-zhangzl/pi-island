import SwiftUI
import Foundation

struct IslandLayoutTargets: Equatable {
    var collapsedWidth: CGFloat
    var expandedWidth: CGFloat
    var compactHeight: CGFloat
    var expandedHeight: CGFloat
    var panelContentWidth: CGFloat
    var panelVisible: Bool

    func containerWidth(using motion: IslandMotionSnapshot) -> CGFloat {
        interpolate(from: collapsedWidth, to: expandedWidth, progress: motion.shellWidthProgress)
    }

    func containerHeight(using motion: IslandMotionSnapshot) -> CGFloat {
        interpolate(from: compactHeight, to: expandedHeight, progress: motion.panelHeightProgress)
    }

    private func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

struct IslandLayoutResolver {
    static func resolve(layout: OverlayLayout, presentationMode: IslandPresentationMode, expandedContainerHeight: CGFloat, collapsedWidth: CGFloat, expandedWidth: CGFloat, panelContentHorizontalInset: CGFloat) -> IslandLayoutTargets {
        let clampedExpandedHeight = min(layout.expandedHeight, expandedContainerHeight)
        let panelVisible = presentationMode == .panel
        return IslandLayoutTargets(
            collapsedWidth: collapsedWidth,
            expandedWidth: expandedWidth,
            compactHeight: layout.compactHeight,
            expandedHeight: clampedExpandedHeight,
            panelContentWidth: expandedWidth - panelContentHorizontalInset * 2,
            panelVisible: panelVisible
        )
    }
}
