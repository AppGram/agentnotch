import SwiftUI

/// View displaying Claude Code tool executions with detailed info
struct ClaudeToolListView: View {
    let tools: [ClaudeToolExecution]
    let maxItems: Int

    init(tools: [ClaudeToolExecution], maxItems: Int = 5) {
        self.tools = tools
        self.maxItems = maxItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if tools.isEmpty {
                Text("No recent tools")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(Array(tools.prefix(maxItems))) { tool in
                    ClaudeToolRow(tool: tool)
                }
            }
        }
    }
}

struct ClaudeToolRow: View {
    let tool: ClaudeToolExecution

    private let claudeColor = Color(red: 1.0, green: 0.55, blue: 0.2)

    /// Display text: prefer description, then argument/filename
    private var displayTag: String? {
        if let desc = tool.description, !desc.isEmpty {
            return desc
        }
        if let arg = tool.argument, !arg.isEmpty {
            return arg
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 6) {
            // Activity indicator
            Circle()
                .fill(claudeColor)
                .frame(width: 6, height: 6)
                .shadow(color: claudeColor.opacity(tool.isRunning ? 0.6 : 0.3), radius: tool.isRunning ? 3 : 1)

            // Tool name
            Text(tool.toolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Small tag for description/filename (inline, not expanding height)
            if let tag = displayTag {
                Text(tag)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            Spacer()

            // Duration or spinner
            if tool.isRunning {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            } else {
                // Input/output tokens
                if let input = tool.inputTokens, input > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.green.opacity(0.8))
                        Text(formatTokens(input))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                if let output = tool.outputTokens, output > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.blue.opacity(0.8))
                        Text(formatTokens(output))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Text(tool.formattedDuration)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

#Preview {
    VStack {
        ClaudeToolListView(tools: [
            {
                var t = ClaudeToolExecution(id: "1", toolName: "Bash", argument: "git status", startTime: Date().addingTimeInterval(-5))
                t.description = "Show working tree status"
                t.inputTokens = 1234
                t.outputTokens = 567
                t.endTime = Date()
                return t
            }(),
            {
                var t = ClaudeToolExecution(id: "2", toolName: "Read", argument: "package.json", startTime: Date().addingTimeInterval(-2))
                t.endTime = Date()
                return t
            }(),
            ClaudeToolExecution(id: "3", toolName: "Grep", argument: "pattern", startTime: Date())
        ])
    }
    .padding()
    .background(Color.black)
}
