import SwiftUI
import Foundation

enum IslandMotionTokens {
    static let hoverDebounce: TimeInterval = 0.08
    static let panelExpandHeightDelay: TimeInterval = 0.04
    static let panelCollapseWidthDelay: TimeInterval = 0.14
    static let compactExpandWidthDelay: TimeInterval = 0.03
    static let windowFrameCollapseDelay: TimeInterval = 0.36
    static let windowFrameWideExpandDelay: TimeInterval = 0.06
    static let panelCollapseToStaticHoldDelay: TimeInterval = 0.2

    static let shellExpand = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.08)
    static let shellCollapse = Animation.spring(response: 0.2, dampingFraction: 0.94)
    static let panelExpandWidth = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let panelExpandHeight = Animation.spring(response: 0.34, dampingFraction: 0.9)
    static let panelCollapseHeight = Animation.spring(response: 0.24, dampingFraction: 0.92)
    static let panelCollapseWidth = Animation.spring(response: 0.22, dampingFraction: 0.94)
    static let panelContentReveal = Animation.easeOut(duration: 0.18)
    static let panelContentHide = Animation.easeOut(duration: 0.12)
}
