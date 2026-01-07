import SwiftUI

@main
struct AgentNotchApp: App {
    @NSApplicationDelegateAdaptor(AgentNotchAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            AgentSettingsView()
                .environmentObject(TelemetryCoordinator.shared)
        }
    }
}
