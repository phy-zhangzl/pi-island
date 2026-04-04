import Foundation

enum IslandPresentationMode: Int, Equatable {
    case staticCapsule = 0
    case dynamicCapsule = 1
    case panel = 2
}

struct IslandPresentationContext: Equatable {
    var hasLiveActivity: Bool
    var isHoveringIsland: Bool
    var isHoveringPanel: Bool
    var isPinnedPanel: Bool
    var isIslandHoverPromotedToPanel: Bool
    var isHoldingDynamicCapsuleOnExit: Bool
}

func resolvePresentationMode(from context: IslandPresentationContext) -> IslandPresentationMode {
    if context.isPinnedPanel || context.isHoveringPanel || (context.isHoveringIsland && context.isIslandHoverPromotedToPanel) {
        return .panel
    }
    if context.hasLiveActivity || context.isHoveringIsland || context.isHoldingDynamicCapsuleOnExit {
        return .dynamicCapsule
    }
    return .staticCapsule
}
