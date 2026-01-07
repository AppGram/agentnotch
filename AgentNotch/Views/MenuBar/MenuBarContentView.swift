import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var mcpCoordinator: MCPCoordinator
    @State private var isAdvancedExpanded = false

    private var lastTokenCount: Int? {
        mcpCoordinator.recentToolCalls.first?.tokenCount
    }

    private var recentTokenTotal: Int {
        mcpCoordinator.recentToolCalls.compactMap { $0.tokenCount }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 12) {
            MenuSection {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AgentNotch")
                            .font(.system(size: 13, weight: .semibold))

                        HStack(spacing: 6) {
                            StatusIndicatorView(state: mcpCoordinator.state)
                            Text(mcpCoordinator.state.displayText)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if mcpCoordinator.state == .running {
                            MenuActionButton(systemName: "stop.fill", tint: .red) {
                                Task { await mcpCoordinator.stop() }
                            }
                        } else if mcpCoordinator.state == .stopped {
                            MenuActionButton(systemName: "play.fill", tint: .green) {
                                Task { try? await mcpCoordinator.start() }
                            }
                        }

                        MenuActionButton(systemName: "arrow.clockwise") {
                            Task { try? await mcpCoordinator.restart() }
                        }
                        .disabled(!mcpCoordinator.state.isActive && mcpCoordinator.state != .stopped)
                    }
                }
            }

            if let buildTime = mcpCoordinator.currentBuildTime {
                MenuSection {
                    BuildTimeView(duration: buildTime, result: mcpCoordinator.lastBuildResult)
                }
            }

            MenuSection(title: "Recent Tool Calls") {
                ToolCallListView(toolCalls: Array(mcpCoordinator.recentToolCalls.prefix(5)))
            }

            MenuSection {
                DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Last Token Count")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastTokenCount.map(String.init) ?? "-")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        HStack {
                            Text("Recent Tokens")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(recentTokenTotal > 0 ? "\(recentTokenTotal)" : "-")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 12, weight: .medium))
            }

            MenuSection {
                HStack {
                    Spacer()
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

}

private struct MenuSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}

private struct MenuActionButton: View {
    let systemName: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(tint)
    }
}

#Preview {
    MenuBarContentView()
        .environmentObject(MCPCoordinator.shared)
}
