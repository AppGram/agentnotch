//
//  ClaudeCodeModels.swift
//  AgentNotch
//
//  Created for Claude Code JSONL integration
//

import Foundation

// MARK: - Session Discovery

/// Represents an active Claude Code IDE session from ~/.claude/ide/*.lock
struct ClaudeSession: Identifiable, Codable, Equatable {
    var id: String { workspaceFolders.first ?? "\(pid)" }

    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Derived from workspace path for project JSONL lookup
    /// Claude Code uses path with "/" replaced by "-" as the project directory name
    var projectKey: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        // Claude Code escapes the path: "/" -> "-", but keeps leading "-" for absolute paths
        // e.g., /Users/foo/project -> -Users-foo-project
        return workspace
            .replacingOccurrences(of: "/", with: "-")
    }

    /// Display name for UI (last folder component)
    var displayName: String {
        guard let workspace = workspaceFolders.first else { return "Unknown" }
        return URL(fileURLWithPath: workspace).lastPathComponent
    }
}

// MARK: - Token Usage

/// Token usage data from JSONL message.usage field
struct ClaudeTokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    static let contextWindow = 200_000

    var contextPercentage: Double {
        guard Self.contextWindow > 0 else { return 0 }
        return min(100, Double(totalTokens) / Double(Self.contextWindow) * 100)
    }

    struct ModelPricing {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double
        let cacheWritePerMillion: Double
    }

    static let opusPricing = ModelPricing(
        inputPerMillion: 15.0,
        outputPerMillion: 75.0,
        cacheReadPerMillion: 1.50,
        cacheWritePerMillion: 18.75
    )

    static let sonnetPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheReadPerMillion: 0.30,
        cacheWritePerMillion: 3.75
    )

    func estimatedCost(model: String) -> Double {
        let pricing = model.contains("opus") ? Self.opusPricing : Self.sonnetPricing

        let inputCost = Double(inputTokens) / 1_000_000 * pricing.inputPerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * pricing.outputPerMillion
        let cacheReadCost = Double(cacheReadInputTokens) / 1_000_000 * pricing.cacheReadPerMillion
        let cacheWriteCost = Double(cacheCreationInputTokens) / 1_000_000 * pricing.cacheWritePerMillion

        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }
}

// MARK: - Tool Execution

/// Represents a tool call in progress or completed
struct ClaudeToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool { endTime == nil }

    // New fields from JSONL
    var description: String?
    var timeout: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    var formattedDuration: String {
        guard let ms = durationMs else {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return formatMs(elapsed)
        }
        return formatMs(ms)
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let seconds = ms / 1000
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Todo Item

/// Claude Code todo item from TodoWrite tool
struct ClaudeTodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus

    enum TodoStatus: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

// MARK: - Complete State

/// Complete Claude Code state for display
struct ClaudeCodeState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""

    var tokenUsage: ClaudeTokenUsage = ClaudeTokenUsage()

    var lastMessage: String = ""
    var lastMessageTime: Date?

    var activeTools: [ClaudeToolExecution] = []
    var recentTools: [ClaudeToolExecution] = []

    var todos: [ClaudeTodoItem] = []

    var isConnected: Bool = false
    var lastUpdateTime: Date?

    /// True when Claude is waiting for user permission to execute a tool
    var needsPermission: Bool = false
    /// The tool waiting for permission (if any)
    var pendingPermissionTool: String?

    /// True when Claude is actively generating a response (thinking)
    var isThinking: Bool = false

    /// Last stop_reason from Claude (e.g., "end_turn", "tool_use")
    var lastStopReason: String?

    /// True when the session completed its last response (stop_reason = end_turn and not active)
    var isSessionComplete: Bool {
        lastStopReason == "end_turn" && !isThinking && activeTools.isEmpty
    }

    // Convenience accessors
    var contextPercentage: Double { tokenUsage.contextPercentage }
    var hasActiveTools: Bool { !activeTools.isEmpty }
    var currentToolName: String? { activeTools.first?.toolName }

    /// True when the session is actively processing (thinking or running tools)
    var isActive: Bool { isThinking || hasActiveTools }
}

// MARK: - Daily Stats (from stats-cache.json)

/// Daily activity stats from ~/.claude/stats-cache.json
struct ClaudeDailyStats: Equatable {
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var sessionCount: Int = 0
    var tokensUsed: Int = 0
    var date: String = ""

    var isEmpty: Bool { date.isEmpty }
}

/// Stats cache structure matching ~/.claude/stats-cache.json
struct ClaudeStatsCache: Codable {
    let dailyActivity: [DailyActivity]?
    let dailyModelTokens: [DailyModelTokens]?
    let modelUsage: [String: ModelUsageStats]?
    let totalSessions: Int?
    let totalMessages: Int?

    struct DailyActivity: Codable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    struct DailyModelTokens: Codable {
        let date: String
        let tokensByModel: [String: Int]?
    }

    struct ModelUsageStats: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
    }
}
