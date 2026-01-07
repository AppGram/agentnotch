import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    init(contentRect: NSRect, styleMask style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        configureWindow()
    }

    private func configureWindow() {
        // Floating panel behavior
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        // Window level above menu bar
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false

        // Force dark appearance
        appearance = NSAppearance(named: .darkAqua)

        // Collection behavior for all spaces
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    func setContent<Content: View>(@ViewBuilder content: () -> Content) {
        contentView = NSHostingView(rootView: content())
    }

    /// Add this window to the notch space for proper layering
    func addToNotchSpace() {
        NotchSpaceManager.shared.notchSpace.windows.insert(self)
    }

    /// Remove this window from the notch space
    func removeFromNotchSpace() {
        NotchSpaceManager.shared.notchSpace.windows.remove(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
