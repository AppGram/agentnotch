import AppKit

struct NotchDetector {
    /// Check if the main screen has a notch using auxiliaryTopLeftArea
    static func hasNotch() -> Bool {
        guard let screen = NSScreen.main else { return false }

        // Check auxiliaryTopLeftArea - this is non-zero on notched Macs
        if let leftArea = screen.auxiliaryTopLeftArea, leftArea.width > 0 {
            return true
        }

        // Fallback to safeAreaInsets
        if screen.safeAreaInsets.top > 0 {
            return true
        }

        return false
    }

    /// Get the notch area dimensions
    private static func getNotchInfo() -> (width: CGFloat, height: CGFloat)? {
        guard let screen = NSScreen.main else { return nil }

        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea

        if let left = leftArea, let right = rightArea, (left.width > 0 || right.width > 0) {
            // Calculate notch width: screen width - left area - right area
            let screenWidth = screen.frame.width
            let notchWidth = screenWidth - left.width - right.width
            let notchHeight = max(left.height, right.height, 32)
            return (width: notchWidth, height: notchHeight)
        }

        // Fallback
        if screen.safeAreaInsets.top > 0 {
            return (width: 200, height: screen.safeAreaInsets.top)
        }

        return nil
    }

    /// Get the notch frame for the closed/minimal state
    static func notchFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }

        let screenFrame = screen.frame

        // Get notch dimensions or use defaults
        let notchInfo = getNotchInfo()
        let notchWidth: CGFloat = min(notchInfo?.width ?? 200, 220)
        let notchHeight: CGFloat = notchInfo?.height ?? 32

        // Center horizontally at the top
        let notchX = screenFrame.origin.x + (screenFrame.width - notchWidth) / 2
        let notchY = screenFrame.origin.y + screenFrame.height - notchHeight

        return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    /// Get the expanded notch frame
    static func expandedNotchFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }

        let screenFrame = screen.frame
        let notchInfo = getNotchInfo()
        let notchHeight = notchInfo?.height ?? 32

        // Larger size for expanded state
        let expandedWidth: CGFloat = 400
        let expandedHeight: CGFloat = 200

        // Center horizontally, position below the notch
        let expandedX = screenFrame.origin.x + (screenFrame.width - expandedWidth) / 2
        let expandedY = screenFrame.origin.y + screenFrame.height - expandedHeight - notchHeight

        return NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
    }

    /// Get menu bar frame (for non-notch Macs)
    static func menuBarFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }

        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = 28

        let width: CGFloat = 220
        let height: CGFloat = menuBarHeight

        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + screenFrame.height - height

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
