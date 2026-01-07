import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var mcpCoordinator: MCPCoordinator
    @StateObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            MCPSettingsTab(settings: settings, mcpCoordinator: mcpCoordinator)
                .tabItem {
                    Label("MCP Server", systemImage: "server.rack")
                }
        }
        .frame(width: 450, height: 400)
        .overlay(alignment: .bottom) {
            SettingsFooter(versionLabel: versionLabel)
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Version \(version) (\(build))"
    }
}

private struct SettingsFooter: View {
    let versionLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            Text("AgentNotch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            Text(versionLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.08)),
            alignment: .top
        )
    }
}

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Start MCP server on launch", isOn: $settings.autoStartMCP)

                Toggle("Show build notifications", isOn: $settings.showBuildNotifications)
            } header: {
                Text("Startup")
            }

            Section {
                Stepper(value: $settings.recentToolCallsLimit, in: 5...50, step: 5) {
                    HStack {
                        Text("Recent tool calls to display")
                        Spacer()
                        Text("\(settings.recentToolCallsLimit)")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Show menu bar icon", isOn: $settings.showMenuBarItem)
            } header: {
                Text("Display")
            }

            Section {
                Toggle("Show token count in notch", isOn: $settings.showNotchTokenCount)
                Toggle("Show meme video while waiting", isOn: $settings.showMemeVideo)

                Stepper(value: $settings.memeGraceSeconds, in: 0...120, step: 5) {
                    HStack {
                        Text("Meme grace period")
                        Spacer()
                        Text("\(settings.memeGraceSeconds)s")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Notch")
            }

            Section {
                Toggle("Battery saver mode", isOn: $settings.batterySaverEnabled)
                Text("15 FPS on battery, 25 FPS when charging")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Performance")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MCPSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var mcpCoordinator: MCPCoordinator
    @State private var isSelectingFile = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Binary Path", text: $settings.mcpBinaryPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    Button("Browse...") {
                        selectBinary()
                    }
                }

                if !settings.mcpConfiguration.isValid {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Binary not found at specified path")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("MCP Binary")
            }

            Section {
                Toggle("Auto-restart on crash", isOn: $settings.autoRestartOnCrash)

                Stepper(value: $settings.maxRestartAttempts, in: 1...10) {
                    HStack {
                        Text("Max restart attempts")
                        Spacer()
                        Text("\(settings.maxRestartAttempts)")
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!settings.autoRestartOnCrash)
            } header: {
                Text("Reliability")
            }

            Section {
                HStack {
                    StatusIndicatorView(state: mcpCoordinator.state)
                    Text(mcpCoordinator.state.displayText)
                        .font(.system(size: 12))

                    Spacer()

                    if mcpCoordinator.state == .running {
                        Button("Stop") {
                            Task { await mcpCoordinator.stop() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else if mcpCoordinator.state == .stopped {
                        Button("Start") {
                            Task { try? await mcpCoordinator.start() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectBinary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.message = "Select the bridge4simulator-xcauto binary"

        if panel.runModal() == .OK, let url = panel.url {
            settings.mcpBinaryPath = url.path
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(MCPCoordinator.shared)
}
