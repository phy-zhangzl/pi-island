import SwiftUI
import Foundation

struct IslandPanelState: Equatable {
    var displaySessions: [AgentSession]
    var isShowingActiveOnly: Bool
    var visibleRowCount: Int
    var rowHeight: CGFloat
    var rowSpacing: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat

    var expandedScrollHeight: CGFloat {
        CGFloat(visibleRowCount) * rowHeight + CGFloat(max(visibleRowCount - 1, 0)) * rowSpacing
    }

    var expandedContainerHeight: CGFloat {
        topPadding + expandedScrollHeight + bottomPadding
    }

    var scrollFrameHeight: CGFloat {
        expandedScrollHeight + topPadding + bottomPadding
    }
}

struct IslandPanelResolver {
    static func resolve(
        sessions: [AgentSession],
        selectedSessionID: String,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat,
        sessionSort: (AgentSession, AgentSession) -> Bool
    ) -> IslandPanelState {
        let realSessions = sessions.filter { $0.id != "mock-chatbot" }
        let activeSessions = realSessions.filter { $0.state.isLiveActivity }.sorted(by: sessionSort)

        let displaySessions: [AgentSession]
        if realSessions.isEmpty {
            displaySessions = Array(sessions.prefix(1))
        } else if !activeSessions.isEmpty {
            displaySessions = activeSessions
        } else {
            displaySessions = Array(realSessions.sorted(by: sessionSort).prefix(1))
        }

        let visibleRowCount = max(1, min(displaySessions.count, 2))

        return IslandPanelState(
            displaySessions: displaySessions,
            isShowingActiveOnly: !activeSessions.isEmpty,
            visibleRowCount: visibleRowCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            topPadding: topPadding,
            bottomPadding: bottomPadding
        )
    }
}
