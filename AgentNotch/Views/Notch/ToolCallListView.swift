import SwiftUI

struct ToolCallListView: View {
    let toolCalls: [ToolCall]
    @StateObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if toolCalls.isEmpty {
                Text("No recent tool calls")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(toolCalls) { call in
                    ToolCallRow(call: call, settings: settings)
                }
            }
        }
    }
}

struct ToolCallRow: View {
    let call: ToolCall
    @ObservedObject var settings: AppSettings

    private var sourceColor: Color {
        switch call.source {
        case .claudeCode:
            return Color(red: 1.0, green: 0.55, blue: 0.2) // Orange for Claude Code
        case .codex:
            return Color(red: 0.2, green: 0.45, blue: 0.9) // Blue for Codex
        case .unknown:
            return Color(red: 0.6, green: 0.8, blue: 1.0) // Light blue for unknown
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Source indicator
            Circle()
                .fill(sourceColor)
                .frame(width: 6, height: 6)
                .shadow(color: sourceColor.opacity(call.isActive ? 0.6 : 0.3), radius: call.isActive ? 3 : 1)

            // Tool name
            Text(call.toolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Duration + tokens + cost
            HStack(spacing: 4) {
                if call.isActive {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                } else {
                    // Input/Output tokens for Claude Code
                    if settings.showNotchTokenBreakdown,
                       let input = call.inputTokens,
                       let output = call.outputTokens {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(input)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(output)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else if settings.showNotchTokenCount, let tokens = call.tokenCount {
                        TokenPill(text: "\(tokens) t")
                    }

                    // Cost for Claude Code
                    if settings.showNotchCost,
                       call.source == .claudeCode,
                       let cost = call.costUsd,
                       cost > 0 {
                        Text("$\(String(format: "%.3f", cost))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.9))
                    }

                    Text(call.formattedDuration)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.04))
        )
    }

}

private struct TokenPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

#Preview {
    ToolCallListView(toolCalls: [
        ToolCall(toolName: "xcode_build", arguments: [:], startTime: Date().addingTimeInterval(-5)),
        ToolCall(toolName: "device_list", arguments: [:], startTime: Date().addingTimeInterval(-2)),
    ])
    .padding()
}
