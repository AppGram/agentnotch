import SwiftUI

public struct AgentSettingsView: View {
    @EnvironmentObject var telemetryCoordinator: TelemetryCoordinator
    @StateObject private var settings = AppSettings.shared

    public init() {}

    public var body: some View {
        TabView {
            TelemetryGeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TelemetryStatusTab(settings: settings, telemetryCoordinator: telemetryCoordinator)
                .tabItem {
                    Label("Telemetry", systemImage: "waveform.path.ecg")
                }
        }
        .frame(width: 450, height: 520)
    }
}

struct TelemetryGeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Start telemetry receiver on launch", isOn: $settings.telemetryAutoStart)
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
                Toggle("Show input/output tokens", isOn: $settings.showNotchTokenBreakdown)
                Toggle("Show price", isOn: $settings.showNotchCost)
                Toggle("Show meme video while waiting", isOn: $settings.showMemeVideo)
            } header: {
                Text("Notch")
            }

            Section {
                Toggle("Codex", isOn: $settings.showSourceCodex)
                Toggle("Claude Code", isOn: $settings.showSourceClaudeCode)
                Toggle("Unknown", isOn: $settings.showSourceUnknown)
            } header: {
                Text("Sources")
            }

            Section {
                Toggle("Battery saver mode", isOn: $settings.batterySaverEnabled)
                Text("15 FPS on battery, 25 FPS when charging")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Performance")
            }

            Section {
                Toggle("Enable JSONL session tracking", isOn: $settings.enableClaudeCodeJSONL)
                Toggle("Show session dots", isOn: $settings.showSessionDots)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show permission indicator", isOn: $settings.showPermissionIndicator)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show todo list", isOn: $settings.showTodoList)
                    .disabled(!settings.enableClaudeCodeJSONL)
                Toggle("Show thinking state", isOn: $settings.showThinkingState)
                    .disabled(!settings.enableClaudeCodeJSONL)

                Text("Reads from ~/.claude to track sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Claude Code")
            }

            Section {
                Toggle("Enable usage quota tracking", isOn: $settings.enableClaudeUsage)
                Toggle("Show in closed notch", isOn: $settings.showClaudeUsageInClosedNotch)
                    .disabled(!settings.enableClaudeUsage)

                ClaudeUsageSettingsView()
                    .disabled(!settings.enableClaudeUsage)
            } header: {
                Text("Claude API Usage")
            }

            Section {
                Toggle("Enable JSONL session tracking", isOn: $settings.enableCodexJSONL)

                Text("Reads from ~/.codex/sessions to track sessions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("OpenAI Codex")
            }

            Section {
                Toggle("Show context progress bar", isOn: $settings.showContextProgress)

                Stepper(value: $settings.contextTokenLimit, in: 50_000...1_000_000, step: 50_000) {
                    HStack {
                        Text("Context limit")
                        Spacer()
                        Text("\(settings.contextTokenLimit / 1000)k")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Picker("Tool display mode", selection: $settings.toolDisplayMode) {
                    Text("Recent events list").tag("list")
                    Text("Single detailed event").tag("singular")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Display")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TelemetryStatusTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var telemetryCoordinator: TelemetryCoordinator

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("OTLP HTTP Port")
                    Spacer()
                    TextField("Port", value: $settings.telemetryOtlpPort, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Receiver")
            }

            Section {
                HStack {
                    TelemetryStatusIndicatorView(state: telemetryCoordinator.state)
                    Text(telemetryCoordinator.state.displayText)
                        .font(.system(size: 12))

                    Spacer()

                    if telemetryCoordinator.state == .running {
                        Button("Stop") {
                            Task { await telemetryCoordinator.stop() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else if telemetryCoordinator.state == .stopped {
                        Button("Start") {
                            Task { await telemetryCoordinator.start() }
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
}

#Preview {
    AgentSettingsView()
        .environmentObject(TelemetryCoordinator.shared)
}
