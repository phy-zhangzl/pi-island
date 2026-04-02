import Foundation
import AppKit

/// Terminal focus is not currently supported on macOS 26
/// due to process lifecycle issues with .accessory apps.
enum TerminalNavigator {
    static func focus(session: AgentSession) {
        // No-op
    }
}
