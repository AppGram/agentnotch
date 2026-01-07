import Foundation
import Combine

@MainActor
final class ToolCallTracker: ObservableObject {
    @Published private(set) var recentToolCalls: [ToolCall] = []
    @Published private(set) var currentBuildTime: TimeInterval?
    @Published private(set) var lastBuildResult: XcodeBuildResult?

    private var pendingCalls: [JSONRPCId: PendingCall] = [:]
    private var pendingStderrCalls: [String: ToolCall] = [:]  // For stderr/telemetry events (string IDs)
    private let parser = JSONRPCParser()
    private let maxRecentCalls: Int

    struct PendingCall {
        let toolName: String
        let arguments: [String: AnyCodableValue]
        let startTime: Date
    }

    init(maxRecentCalls: Int = 10) {
        self.maxRecentCalls = maxRecentCalls
    }

    // MARK: - Stderr event tracking (from Go server)

    func recordToolStart(id: String, toolCall: ToolCall) {
        pendingStderrCalls[id] = toolCall

        // Add to recent calls immediately (as active)
        recentToolCalls.insert(toolCall, at: 0)
        if recentToolCalls.count > maxRecentCalls {
            recentToolCalls.removeLast()
        }
    }

    func recordToolEnd(id: String, success: Bool, durationMs: Int64?, tokens: Int?, endTime: Date = Date()) {
        guard var toolCall = pendingStderrCalls.removeValue(forKey: id) else { return }

        toolCall.endTime = endTime
        toolCall.tokenCount = tokens
        if success {
            toolCall.result = .success(content: "")
        } else {
            toolCall.result = .failure(error: "Tool failed")
        }

        // Update the existing entry in recentToolCalls
        if let index = recentToolCalls.firstIndex(where: { $0.id == toolCall.id }) {
            recentToolCalls[index] = toolCall
        }

        // Track build time for build tools
        if toolCall.isBuildTool, let ms = durationMs {
            currentBuildTime = TimeInterval(ms) / 1000.0
        }
    }

    func recordCompletedToolCall(
        toolName: String,
        arguments: [String: AnyCodableValue] = [:],
        startTime: Date,
        endTime: Date,
        success: Bool,
        tokens: Int?,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        costUsd: Double? = nil,
        source: TelemetrySource = .unknown
    ) {
        var toolCall = ToolCall(
            toolName: toolName,
            arguments: arguments,
            startTime: startTime,
            tokenCount: tokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUsd: costUsd,
            source: source
        )
        toolCall.endTime = endTime
        toolCall.result = success ? .success(content: "") : .failure(error: "Tool failed")

        recentToolCalls.insert(toolCall, at: 0)
        if recentToolCalls.count > maxRecentCalls {
            recentToolCalls.removeLast()
        }
    }

    func recordRequest(_ request: JSONRPCRequest) {
        guard let id = request.id,
              let toolInfo = parser.extractToolCallInfo(from: request) else {
            return
        }

        pendingCalls[id] = PendingCall(
            toolName: toolInfo.name,
            arguments: toolInfo.arguments,
            startTime: Date()
        )
    }

    func recordResponse(_ response: JSONRPCResponse) -> ToolCall? {
        guard let pending = pendingCalls.removeValue(forKey: response.id) else {
            return nil
        }

        let endTime = Date()
        var toolCall = ToolCall(
            toolName: pending.toolName,
            arguments: pending.arguments,
            startTime: pending.startTime
        )
        toolCall.endTime = endTime

        // Extract result
        if let resultInfo = parser.extractToolResult(from: response) {
            if resultInfo.isError {
                toolCall.result = .failure(error: resultInfo.content)
            } else {
                toolCall.result = .success(content: resultInfo.content)
            }
        } else if response.error != nil {
            toolCall.result = .failure(error: response.error?.message ?? "Unknown error")
        } else {
            toolCall.result = .success(content: "")
        }

        // Track build results specially
        if toolCall.isBuildTool {
            if let buildResult = parser.extractBuildResult(from: response) {
                lastBuildResult = buildResult
                currentBuildTime = buildResult.duration
            } else {
                currentBuildTime = toolCall.duration
            }
        }

        // Add to recent calls
        recentToolCalls.insert(toolCall, at: 0)
        if recentToolCalls.count > maxRecentCalls {
            recentToolCalls.removeLast()
        }

        return toolCall
    }

    func clear() {
        pendingCalls.removeAll()
        pendingStderrCalls.removeAll()
        recentToolCalls.removeAll()
        currentBuildTime = nil
        lastBuildResult = nil
    }

    /// Force-complete all active tool calls (used when session ends)
    func forceCompleteAllActive() {
        let now = Date()
        pendingStderrCalls.removeAll()

        for i in recentToolCalls.indices {
            if recentToolCalls[i].isActive {
                recentToolCalls[i].endTime = now
                recentToolCalls[i].result = .success(content: "")
            }
        }
    }
}
