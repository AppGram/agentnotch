import AppKit
import SwiftUI

final class AgentNotchAppDelegate: NSObject, NSApplicationDelegate, SettingsWindowProvider {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModeConfig.current = .agentNotch
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            UICoordinator.shared.setupUI()
        }

        if AppSettings.shared.telemetryAutoStart {
            Task { @MainActor in
                await TelemetryCoordinator.shared.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await TelemetryCoordinator.shared.stop()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @objc func showSettingsWindow() {
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = AgentSettingsView()
            .environmentObject(TelemetryCoordinator.shared)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Settings"
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
