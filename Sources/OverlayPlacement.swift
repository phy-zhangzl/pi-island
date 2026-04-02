import SwiftUI
import AppKit

struct OverlayCalibration {
    var xOffset: CGFloat
    var compactYOffset: CGFloat
    var expandedYOffset: CGFloat

    static func load() -> OverlayCalibration {
        let defaults = UserDefaults.standard
        func value(_ key: String) -> CGFloat {
            guard let number = defaults.object(forKey: key) as? NSNumber else { return 0 }
            return CGFloat(number.doubleValue)
        }
        return OverlayCalibration(
            xOffset: value("overlay.offset.x"),
            compactYOffset: value("overlay.offset.compactY"),
            expandedYOffset: value("overlay.offset.expandedY")
        )
    }
}

struct OverlayLayout {
    let screen: NSScreen
    let calibration: OverlayCalibration

    static func current(calibration: OverlayCalibration = .load()) -> OverlayLayout? {
        guard let screen = builtInScreen() else { return nil }
        return OverlayLayout(screen: screen, calibration: calibration)
    }

    var notchGapWidth: CGFloat {
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? ((screen.frame.width - 220) / 2)
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? ((screen.frame.width - 220) / 2)
        let measured = screen.frame.width - leftWidth - rightWidth
        return max(140, measured)
    }

    var notchHeight: CGFloat {
        let safeTop = screen.safeAreaInsets.top
        if safeTop > 0 { return safeTop }
        let fallback = screen.frame.maxY - screen.visibleFrame.maxY
        return max(30, fallback)
    }

    var compactSideWidth: CGFloat {
        max(70, min(94, notchGapWidth * 0.28))
    }

    var compactHeight: CGFloat { notchHeight + 2 }
    var expandedHeight: CGFloat { notchHeight + 248 }
    var panelWidth: CGFloat { max(432, min(540, notchGapWidth + 256)) }
    var bridgeWidth: CGFloat { max(104, min(128, notchGapWidth * 0.5)) }
    var compactTotalWidth: CGFloat { notchGapWidth + compactSideWidth * 2 + 24 }
    var expandedTotalWidth: CGFloat { max(compactTotalWidth + 96, panelWidth + 44) }

    var compactWindowSize: CGSize {
        CGSize(width: compactTotalWidth, height: compactHeight)
    }

    var expandedWindowSize: CGSize {
        CGSize(width: expandedTotalWidth, height: expandedHeight)
    }

    var compactOrigin: NSPoint {
        NSPoint(
            x: floor(screen.frame.midX - compactWindowSize.width / 2 + calibration.xOffset),
            y: floor(screen.frame.maxY + calibration.compactYOffset),
        )
    }

    var expandedOrigin: NSPoint {
        NSPoint(
            x: floor(screen.frame.midX - expandedWindowSize.width / 2 + calibration.xOffset),
            y: floor(screen.frame.maxY + calibration.expandedYOffset),
        )
    }

    static func builtInScreen() -> NSScreen? {
        if let builtIn = NSScreen.screens.first(where: { $0.localizedName.localizedCaseInsensitiveContains("Built-in") }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
