// NotchSizing.swift
// Sizing constants and helpers for the notch UI

import SwiftUI

// MARK: - Fixed Sizes

/// Shadow padding around the window
let shadowPadding: CGFloat = 20

/// Extra bottom spacing to allow the closed-state glow to render fully
let closedNotchGlowPadding: CGFloat = 24

/// Open notch content size - larger for better data display
let openNotchSize: CGSize = .init(width: 580, height: 368)

/// Window size (includes shadow padding)
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)

/// Corner radius for open/closed states
let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

// MARK: - Dynamic Sizing

/// Get the closed notch size for a screen
@MainActor
func getClosedNotchSize(screen: NSScreen? = nil) -> CGSize {
    let selectedScreen = screen ?? NSScreen.main

    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 185

    if let screen = selectedScreen {
        // Calculate notch width from auxiliary areas
        if let topLeftPadding = screen.auxiliaryTopLeftArea?.width,
           let topRightPadding = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - topLeftPadding - topRightPadding + 4
        }

        // Get height from safe area or menu bar
        if screen.safeAreaInsets.top > 0 {
            // Mac with notch
            notchHeight = screen.safeAreaInsets.top
        } else {
            // Mac without notch - use menu bar height
            notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            if notchHeight < 24 { notchHeight = 32 }
        }
    }

    return CGSize(width: notchWidth, height: notchHeight + 2)
}

/// Get the screen frame
@MainActor
func getScreenFrame(_ screen: NSScreen? = nil) -> CGRect? {
    let selectedScreen = screen ?? NSScreen.main
    return selectedScreen?.frame
}
