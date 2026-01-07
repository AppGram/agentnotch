// NotchSpaceManager.swift
// Manages the CGSSpace for notch windows

import Foundation

final class NotchSpaceManager {
    static let shared = NotchSpaceManager()

    /// The notch space at the maximum possible level
    let notchSpace: CGSSpace

    private init() {
        // Max level to appear above everything
        notchSpace = CGSSpace(level: 2147483647)
    }
}
