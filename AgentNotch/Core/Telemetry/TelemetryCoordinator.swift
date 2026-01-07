import Foundation
import Combine

public enum TelemetryState: Equatable {
    case stopped
    case starting
    case running
    case error(String)

    var isActive: Bool {
        switch self {
        case .starting, .running:
            return true
        case .stopped, .error:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Listening"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Telemetry Source
public enum TelemetrySource: String, Codable, Equatable {
    case unknown
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

// MARK: - Codex Event Types
private enum CodexEventType: String {
    case apiRequest = "codex.api_request"
    case sseEvent = "codex.sse_event"
    case userPrompt = "codex.user_prompt"
    case toolDecision = "codex.tool_decision"
    case toolResult = "codex.tool_result"

    static func from(_ eventName: String) -> CodexEventType? {
        CodexEventType(rawValue: eventName.lowercased())
    }
}

// MARK: - Claude Code Event Types
private enum ClaudeCodeEventType: String {
    case userPrompt = "claude_code.user_prompt"
    case toolResult = "claude_code.tool_result"
    case apiRequest = "claude_code.api_request"
    case apiError = "claude_code.api_error"
    case toolDecision = "claude_code.tool_decision"

    static func from(_ eventName: String) -> ClaudeCodeEventType? {
        ClaudeCodeEventType(rawValue: eventName.lowercased())
    }
}

@MainActor
public final class TelemetryCoordinator: ObservableObject {
    public static let shared = TelemetryCoordinator()

    @Published private(set) var state: TelemetryState = .stopped
    @Published private(set) var recentToolCalls: [ToolCall] = []
    @Published private(set) var sessionTokenTotal: Int = 0
    @Published private(set) var sessionCacheTokens: Int = 0
    @Published private(set) var errorOutput: String = ""
    @Published private(set) var currentConversationId: String?
    @Published private(set) var currentModel: String?
    @Published private(set) var telemetrySource: TelemetrySource = .unknown
    @Published private(set) var isAgentActive: Bool = false
    @Published private(set) var lastActivityTime: Date?

    private let server = OTLPHTTPServer()
    private let decoder = OTLPDecoder()
    private let toolCallTracker = ToolCallTracker(maxRecentCalls: AppSettings.shared.recentToolCallsLimit)
    private var tokenCache: [String: Double] = [:]
    private var cacheTokenCache: [String: Double] = [:]
    private var pendingToolDecisions: [String: ToolCall] = [:] // call_id -> ToolCall awaiting result
    private var activeCodexToolCalls: [String: (name: String, startTime: Date)] = [:] // call_id -> active tool
    private var activeCodexResponseStart: Date?

    private var cancellables = Set<AnyCancellable>()

    // Claude Code specific tracking
    private var pendingClaudeToolCalls: [String: ToolCall] = [:] // call_id -> active tool
    private var claudeSessionId: String?
    private var claudeAccountUuid: String?
    private var claudeUserEmail: String?

    // Idle detection for completion
    private var idleDetectionTask: Task<Void, Never>?
    private let idleThreshold: TimeInterval = 30.0 // seconds of inactivity to consider "finished"

    // Active time based completion detection
    private var activeTimeCompletionTask: Task<Void, Never>?
    private let activeTimeCompletionDelay: TimeInterval = 15.0 // seconds after active_time metric with no further activity
    private var lastActiveTimeMetricReceived: Date?

    private var hasActiveWork: Bool {
        if toolCallTracker.recentToolCalls.contains(where: { $0.isActive }) {
            return true
        }
        if !activeCodexToolCalls.isEmpty || !pendingClaudeToolCalls.isEmpty || !pendingToolDecisions.isEmpty {
            return true
        }
        return activeCodexResponseStart != nil
    }

    private init() {
        setupBindings()
        server.onRequest = { [weak self] request in
            Task { @MainActor in
                self?.handle(request)
            }
        }
        server.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorOutput.append(contentsOf: message + "\n")
            }
        }
    }

    private func setupBindings() {
        toolCallTracker.$recentToolCalls
            .receive(on: DispatchQueue.main)
            .assign(to: &$recentToolCalls)
    }

    public func start() async {
        guard state == .stopped else { return }
        state = .starting
        errorOutput = ""

        do {
            guard let port = UInt16(exactly: AppSettings.shared.telemetryOtlpPort) else {
                state = .error("Invalid port")
                return
            }
            try server.start(port: port)
            state = .running
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func stop() async {
        guard state == .running || state == .starting else { return }
        server.stop()
        state = .stopped
        idleDetectionTask?.cancel()
        activeTimeCompletionTask?.cancel()
        isAgentActive = false
    }

    /// Called when any activity is detected from Claude Code
    private func recordActivity() {
        lastActivityTime = Date()

        // Mark as active if not already
        if !isAgentActive {
            isAgentActive = true
            // print("[Telemetry] Agent became active")
        }

        // Cancel any pending completion timers - we have new activity
        cancelActiveTimeCompletion()

        // Reset idle detection timer
        idleDetectionTask?.cancel()
        idleDetectionTask = Task {
            try? await Task.sleep(for: .seconds(idleThreshold))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Check if still idle
                if let lastActivity = lastActivityTime,
                   Date().timeIntervalSince(lastActivity) >= idleThreshold {
                    guard !hasActiveWork else { return }
                    markAgentComplete(reason: "idle for \(idleThreshold)s")
                }
            }
        }
    }

    /// Called when active_time metric is received - this often indicates end of a response cycle
    private func handleActiveTimeReceived() {
        lastActiveTimeMetricReceived = Date()

        // Start a timer - if no more telemetry comes in, Claude is likely done
        activeTimeCompletionTask?.cancel()
        activeTimeCompletionTask = Task {
            try? await Task.sleep(for: .seconds(activeTimeCompletionDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !hasActiveWork else { return }
                // Check we haven't received new activity since the timer started
                if let lastActivity = lastActivityTime,
                   let lastActiveTime = lastActiveTimeMetricReceived,
                   lastActivity <= lastActiveTime {
                    markAgentComplete(reason: "no activity after active_time metric")
                }
            }
        }
    }

    /// Called when new telemetry activity comes in - resets completion detection
    private func cancelActiveTimeCompletion() {
        activeTimeCompletionTask?.cancel()
    }

    /// Mark the agent as complete
    private func markAgentComplete(reason: String) {
        guard isAgentActive else { return }

        // Force-complete any lingering active tool calls
        toolCallTracker.forceCompleteAllActive()
        pendingClaudeToolCalls.removeAll()
        pendingToolDecisions.removeAll()
        activeCodexToolCalls.removeAll()
        activeCodexResponseStart = nil

        isAgentActive = false
        // print("[Telemetry] Agent finished (\(reason))")

        // Create a completion tool call to show in UI
        toolCallTracker.recordCompletedToolCall(
            toolName: "Complete",
            startTime: lastActivityTime ?? Date(),
            endTime: Date(),
            success: true,
            tokens: sessionTokenTotal,
            source: telemetrySource
        )
    }

    private func handle(_ request: OTLPHTTPServer.Request) {
        switch request.route {
        case .logs:
            handleLogs(request.body)
        case .metrics:
            handleMetrics(request.body)
        case .other:
            break
        }
    }

    private func handleLogs(_ data: Data) {
        logRawPayload(data, route: "logs")
        do {
            let records = try decoder.decodeLogs(data)
            // print("[Telemetry] Received \(records.count) log records")
            for record in records {
                // print("[Telemetry] Record body: \(record.body ?? "nil"), attrs: \(record.attributes.keys.joined(separator: ", "))")
                handleLogRecord(record)
            }
        } catch {
            // print("[Telemetry] OTLP log decode error: \(error)")
            errorOutput.append("OTLP log decode error: \(error.localizedDescription)\n")
        }
    }

    private func handleMetrics(_ data: Data) {
        logRawPayload(data, route: "metrics")
        do {
            let points = try decoder.decodeMetrics(data)
            // print("[Telemetry] Received \(points.count) metric points")
            for point in points {
                // print("[Telemetry] Metric: \(point.name) = \(point.value)")
                handleMetricPoint(point)
            }
        } catch {
            // print("[Telemetry] OTLP metric decode error: \(error)")
            errorOutput.append("OTLP metric decode error: \(error.localizedDescription)\n")
        }
    }

    private func logRawPayload(_ data: Data, route: String) {
        let sampleSize = min(data.count, 256)
        let sample = data.prefix(sampleSize).base64EncodedString()
        let scanSize = min(data.count, 4096)
        let scanText = String(decoding: data.prefix(scanSize), as: UTF8.self).lowercased()
        let sourceHint: String
        if scanText.contains("codex") {
            sourceHint = "codex"
        } else if scanText.contains("claude") || scanText.contains("anthropic") {
            sourceHint = "claude"
        } else {
            sourceHint = "unknown"
        }

        // print("[Telemetry] Raw \(route) payload bytes=\(data.count) source=\(sourceHint) base64_prefix=\(sample)")
    }

    private func handleMetricPoint(_ point: TelemetryMetricPoint) {
        let nameKey = point.name.lowercased()

        // Detect source from metric name
        if nameKey.hasPrefix("claude_code.") {
            if telemetrySource != .claudeCode {
                telemetrySource = .claudeCode
            }
            handleClaudeCodeMetric(point)
            return
        }

        // Token metrics
        guard nameKey.contains("token") else { return }

        let typeAttr = point.attributes["type"]?.stringValue?.lowercased() ?? "unknown"
        let cacheKey = "\(point.name):\(typeAttr)"

        // Separate cache tokens from regular tokens
        let isCacheToken = typeAttr.contains("cache")

        if isCacheToken {
            cacheTokenCache[cacheKey] = point.value
            sessionCacheTokens = Int(cacheTokenCache.values.reduce(0, +))
        } else {
            tokenCache[cacheKey] = point.value
            sessionTokenTotal = Int(tokenCache.values.reduce(0, +))
        }

        // print("[Telemetry] Token: \(typeAttr) = \(Int(point.value)) | total: \(sessionTokenTotal) | cache: \(sessionCacheTokens)")
    }

    private func handleClaudeCodeMetric(_ point: TelemetryMetricPoint) {
        let nameKey = point.name.lowercased()
        let typeAttr = point.attributes["type"]?.stringValue?.lowercased() ?? ""
        let modelAttr = point.attributes["model"]?.stringValue

        // Update model if available
        if let model = modelAttr {
            currentModel = model
        }

        // Token usage: claude_code.token.usage with type attribute
        if nameKey.contains("token") {
            let cacheKey = "\(point.name):\(typeAttr)"
            let isCacheToken = typeAttr.contains("cache")

            if isCacheToken {
                cacheTokenCache[cacheKey] = point.value
                sessionCacheTokens = Int(cacheTokenCache.values.reduce(0, +))
            } else {
                tokenCache[cacheKey] = point.value
                sessionTokenTotal = Int(tokenCache.values.reduce(0, +))
            }
            // print("[Telemetry] Claude token (\(typeAttr)): \(Int(point.value)) | total: \(sessionTokenTotal) | cache: \(sessionCacheTokens)")
            return
        }

        // Cost usage: claude_code.cost.usage
        if nameKey.contains("cost") {
            // print("[Telemetry] Claude cost: $\(String(format: "%.4f", point.value)) model=\(modelAttr ?? "?")")
            return
        }

        // Session count: claude_code.session.count
        if nameKey.contains("session") {
            // print("[Telemetry] Claude sessions: \(Int(point.value))")
            return
        }

        // Lines of code: claude_code.lines_of_code.count
        if nameKey.contains("lines_of_code") {
            // print("[Telemetry] Claude lines of code (\(typeAttr)): \(Int(point.value))")
            return
        }

        // Commits: claude_code.commit.count
        if nameKey.contains("commit") {
            // print("[Telemetry] Claude commits: \(Int(point.value))")
            return
        }

        // Pull requests: claude_code.pull_request.count
        if nameKey.contains("pull_request") {
            // print("[Telemetry] Claude PRs: \(Int(point.value))")
            return
        }

        // Active time: claude_code.active_time.total
        if nameKey.contains("active_time") {
            // print("[Telemetry] Claude active time: \(point.value)s")
            // active_time is often sent near end of work - use it for completion detection
            handleActiveTimeReceived()
            return
        }

        // Code edit decisions: claude_code.code_edit_tool.decision
        if nameKey.contains("code_edit") || nameKey.contains("decision") {
            // print("[Telemetry] Claude edit decision: \(Int(point.value))")
            return
        }

        // Generic fallback
        // print("[Telemetry] Claude metric: \(point.name) = \(point.value)")
    }

    private func handleLogRecord(_ record: TelemetryLogRecord) {
        let attributes = record.attributes

        // Prefer body if it contains a namespaced event (e.g., claude_code.api_request)
        // Otherwise fall back to event.name attribute
        let eventName: String?
        if let body = record.body, (body.contains("claude_code.") || body.contains("codex.")) {
            eventName = body
        } else {
            eventName = attributes.stringValue(for: ["event.name", "event", "name"]) ?? record.body
        }

        guard let eventName else { return }

        // print("[Telemetry] Event: '\(eventName)'")

        // Extract common metadata
        if let conversationId = attributes.stringValue(for: ["conversation.id", "conversation_id"]) {
            currentConversationId = conversationId
        }
        if let model = attributes.stringValue(for: ["model"]) {
            currentModel = model
        }

        // Extract Claude Code specific metadata
        if let sessionId = attributes.stringValue(for: ["session.id", "session_id"]) {
            claudeSessionId = sessionId
        }
        if let accountUuid = attributes.stringValue(for: ["user.account_uuid", "account_uuid"]) {
            claudeAccountUuid = accountUuid
        }
        if let email = attributes.stringValue(for: ["user.email", "email"]) {
            claudeUserEmail = email
        }

        // Check for Claude Code specific events first
        if let claudeEvent = ClaudeCodeEventType.from(eventName) {
            if telemetrySource != .claudeCode {
                telemetrySource = .claudeCode
            }
            handleClaudeCodeEvent(claudeEvent, record: record, source: .claudeCode)
            return
        }

        // Check for Codex-specific events
        if let codexEvent = CodexEventType.from(eventName) {
            if telemetrySource != .codex {
                telemetrySource = .codex
            }
            handleCodexEvent(codexEvent, record: record, source: .codex)
            return
        }

        // Detect Claude Code events by prefix
        let normalizedEvent = eventName.lowercased()
        if normalizedEvent.hasPrefix("claude_code.") {
            if telemetrySource != .claudeCode {
                telemetrySource = .claudeCode
            }
            handleClaudeCodeGenericEvent(eventName: eventName, record: record, source: .claudeCode)
            return
        }

        // Detect source from event name
        let source: TelemetrySource = (normalizedEvent.contains("claude") || normalizedEvent.contains("anthropic"))
            ? .claudeCode
            : .unknown
        if source != .unknown, telemetrySource != source {
            telemetrySource = source
        }

        // Fall back to generic event handling
        handleGenericLogRecord(eventName: eventName, record: record, source: source)
    }

    // MARK: - Codex Event Handling

    private func handleCodexEvent(_ event: CodexEventType, record: TelemetryLogRecord, source: TelemetrySource) {
        let attributes = record.attributes
        let endTime = record.timestamp

        switch event {
        case .apiRequest:
            handleCodexApiRequest(attributes: attributes, endTime: endTime, source: source)

        case .sseEvent:
            handleCodexSseEvent(attributes: attributes, endTime: endTime, source: source)

        case .userPrompt:
            handleCodexUserPrompt(attributes: attributes, endTime: endTime)

        case .toolDecision:
            handleCodexToolDecision(attributes: attributes, endTime: endTime, source: source)

        case .toolResult:
            handleCodexToolResult(attributes: attributes, endTime: endTime)
        }
    }

    private func handleCodexApiRequest(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        recordActivity()
        let durationMs = attributes.intValue(for: ["duration_ms"])
        let statusCode = attributes.intValue(for: ["http.response.status_code"])
        let errorMessage = attributes.stringValue(for: ["error.message"])
        let attempt = attributes.intValue(for: ["attempt"]) ?? 1

        let startTime: Date
        if let durationMs {
            startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
        } else {
            startTime = endTime
        }

        let success = errorMessage == nil && (statusCode == nil || statusCode! < 400)
        let displayName = attempt > 1 ? "API Request (retry \(attempt))" : "API Request"

        toolCallTracker.recordCompletedToolCall(
            toolName: displayName,
            startTime: startTime,
            endTime: endTime,
            success: success,
            tokens: nil,
            source: source
        )

        if let error = errorMessage {
            // print("[Telemetry] Codex API error: \(error)")
        }
    }

    private func handleCodexSseEvent(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        recordActivity()
        let durationMs = attributes.intValue(for: ["duration_ms"])
        let eventKind = attributes.stringValue(for: ["event.kind"]) ?? "streaming"
        let errorMessage = attributes.stringValue(for: ["error.message"])
        let normalizedKind = eventKind.lowercased()

        // Extract token counts from SSE events
        let inputTokens = attributes.intValue(for: ["input_tokens", "input_token_count", "tokens.input"])
        let outputTokens = attributes.intValue(for: ["output_tokens", "output_token_count", "tokens.output"])
        let cacheReadTokens = attributes.intValue(for: ["cache_read_tokens", "cached_token_count", "tokens.cache_read"])
        let cacheCreationTokens = attributes.intValue(for: ["cache_creation_tokens", "tokens.cache_creation"])
        let reasoningTokens = attributes.intValue(for: ["reasoning_token_count"])
        let toolTokens = attributes.intValue(for: ["tool_token_count"])

        // Update session token totals
        if let input = inputTokens {
            let key = "codex.sse.input"
            tokenCache[key] = Double(input)
        }
        if let output = outputTokens {
            let key = "codex.sse.output"
            tokenCache[key] = Double(output)
        }
        if let reasoning = reasoningTokens {
            tokenCache["codex.sse.reasoning"] = Double(reasoning)
        }
        if let tool = toolTokens {
            tokenCache["codex.sse.tool"] = Double(tool)
        }
        sessionTokenTotal = Int(tokenCache.values.reduce(0, +))

        if let cacheRead = cacheReadTokens {
            cacheTokenCache["codex.cache.read"] = Double(cacheRead)
        }
        if let cacheCreation = cacheCreationTokens {
            cacheTokenCache["codex.cache.creation"] = Double(cacheCreation)
        }
        sessionCacheTokens = Int(cacheTokenCache.values.reduce(0, +))

        // Extract tool call information from SSE events
        let toolName = attributes.stringValue(for: ["tool_name", "function.name", "name", "tool.name"])
        let callId = attributes.stringValue(for: ["call_id", "tool_call_id", "id"]) ?? UUID().uuidString

        if normalizedKind.contains("response.created") {
            activeCodexResponseStart = endTime
        }

        let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)
        let success = errorMessage == nil

        // Determine display name based on event kind
        let displayName = parseCodexSseEventKind(eventKind, toolName: toolName, callId: callId, endTime: endTime, source: source)

        // Only record if we have a meaningful event (not just delta updates)
        if shouldRecordCodexSseEvent(eventKind) {
            let startTime: Date
            if let durationMs {
                startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
            } else if (normalizedKind.contains("response.done") || normalizedKind.contains("response.completed")),
                      let responseStart = activeCodexResponseStart {
                startTime = responseStart
                activeCodexResponseStart = nil
            } else {
                startTime = endTime
            }

            toolCallTracker.recordCompletedToolCall(
                toolName: displayName,
                startTime: startTime,
                endTime: endTime,
                success: success,
                tokens: totalTokens > 0 ? totalTokens : nil,
                source: source
            )
        }

        // print("[Telemetry] Codex SSE (\(eventKind)): tool=\(displayName), tokens=\(totalTokens)")
    }

    /// Parse Codex SSE event.kind to extract meaningful display name
    private func parseCodexSseEventKind(_ eventKind: String, toolName: String?, callId: String, endTime: Date, source: TelemetrySource) -> String {
        let kind = eventKind.lowercased()

        // Tool call events - track start and completion
        if kind.contains("tool_call") || kind.contains("function_call") {
            let name = toolName ?? extractToolNameFromEventKind(eventKind)

            if kind.contains(".delta") {
                // Tool call streaming - mark as started if not already
                if activeCodexToolCalls[callId] == nil {
                    activeCodexToolCalls[callId] = (name: name, startTime: endTime)
                    let toolCall = ToolCall(toolName: name, arguments: [:], startTime: endTime, source: source)
                    toolCallTracker.recordToolStart(id: callId, toolCall: toolCall)
                }
                return name
            } else if kind.contains(".done") || kind.contains("_done") {
                // Tool call completed
                if let active = activeCodexToolCalls.removeValue(forKey: callId) {
                    toolCallTracker.recordToolEnd(id: callId, success: true, durationMs: nil, tokens: nil, endTime: endTime)
                    return active.name
                }
                return name
            }

            return name
        }

        // Response output events
        if kind.contains("output_item") {
            if kind.contains(".added") {
                return "Processing"
            } else if kind.contains(".done") {
                return "Output Ready"
            }
        }

        // Content delta/done events (text streaming)
        if kind.contains("content") {
            if kind.contains(".delta") {
                return "Generating"
            } else if kind.contains(".done") {
                return "Response Complete"
            }
        }

        // Response lifecycle events
        if kind.contains("response.created") {
            return "Starting"
        }
        if kind.contains("response.done") || kind.contains("response.completed") {
            return "Complete"
        }
        if kind.contains("response.in_progress") {
            return "Thinking"
        }

        // Default fallback
        return toolName ?? "Thinking"
    }

    /// Extract tool name from event kind string like "response.custom_tool_call_input.delta"
    private func extractToolNameFromEventKind(_ eventKind: String) -> String {
        let parts = eventKind.split(separator: ".")

        // Look for known tool type indicators
        for part in parts {
            let p = String(part).lowercased()
            if p.contains("shell") || p.contains("bash") {
                return "Shell"
            }
            if p.contains("read") || p.contains("file") {
                return "Read"
            }
            if p.contains("write") || p.contains("edit") {
                return "Edit"
            }
            if p.contains("search") || p.contains("grep") {
                return "Search"
            }
            if p.contains("custom_tool") {
                return "Tool"
            }
            if p.contains("function") {
                return "Function"
            }
        }

        return "Tool"
    }

    /// Determine if this SSE event should create a visible entry
    private func shouldRecordCodexSseEvent(_ eventKind: String) -> Bool {
        let kind = eventKind.lowercased()

        // Skip intermediate delta events (they're tracked via start/end)
        if kind.contains(".delta") {
            return false
        }

        // Record completion events
        if kind.contains(".done") || kind.contains("_done") || kind.contains(".completed") {
            return true
        }

        // Record major lifecycle events
        if kind.contains("response.created") || kind.contains("response.done") {
            return true
        }

        // Skip other intermediate events
        return false
    }

    private func handleCodexUserPrompt(attributes: [String: TelemetryAttributeValue], endTime: Date) {
        let promptLength = attributes.intValue(for: ["prompt_length"]) ?? 0
        // Note: actual prompt content is redacted by default in Codex
        // print("[Telemetry] Codex user prompt: \(promptLength) chars")
    }

    private func handleCodexToolDecision(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        let toolName = attributes.stringValue(for: ["tool_name"]) ?? "unknown"
        let callId = attributes.stringValue(for: ["call_id"]) ?? UUID().uuidString
        let decision = attributes.stringValue(for: ["decision"]) ?? "unknown"
        let decisionSource = attributes.stringValue(for: ["source"]) ?? "unknown"

        // print("[Telemetry] Codex tool decision: \(toolName) -> \(decision) (source: \(decisionSource))")

        // Only track approved tools (they will get a result event later)
        if decision.lowercased() == "approve" || decision.lowercased() == "approved" {
            let toolCall = ToolCall(toolName: toolName, arguments: [:], startTime: endTime, source: source)
            pendingToolDecisions[callId] = toolCall
            toolCallTracker.recordToolStart(id: callId, toolCall: toolCall)
        } else {
            // Denied tools - show as completed with failure
            toolCallTracker.recordCompletedToolCall(
                toolName: "\(toolName) (denied)",
                startTime: endTime,
                endTime: endTime,
                success: false,
                tokens: nil,
                source: source
            )
        }
    }

    private func handleCodexToolResult(attributes: [String: TelemetryAttributeValue], endTime: Date) {
        let toolName = attributes.stringValue(for: ["tool_name"]) ?? "unknown"
        let callId = attributes.stringValue(for: ["call_id"]) ?? UUID().uuidString
        let durationMs = attributes.intValue(for: ["duration_ms"])
        let success = attributes.boolValue(for: ["success"]) ?? true

        // Remove from pending decisions if present
        pendingToolDecisions.removeValue(forKey: callId)

        let startTime: Date
        if let durationMs {
            startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
        } else {
            startTime = endTime
        }

        toolCallTracker.recordToolEnd(
            id: callId,
            success: success,
            durationMs: durationMs.map { Int64($0) },
            tokens: nil,
            endTime: endTime
        )

        // print("[Telemetry] Codex tool result: \(toolName) success=\(success) duration=\(durationMs ?? 0)ms")
    }

    // MARK: - Claude Code Event Handling

    private func handleClaudeCodeEvent(_ event: ClaudeCodeEventType, record: TelemetryLogRecord, source: TelemetrySource) {
        let attributes = record.attributes
        let endTime = record.timestamp

        switch event {
        case .apiRequest:
            handleClaudeApiRequest(attributes: attributes, endTime: endTime, source: source)

        case .apiError:
            handleClaudeApiError(attributes: attributes, endTime: endTime, source: source)

        case .userPrompt:
            handleClaudeUserPrompt(attributes: attributes, endTime: endTime)

        case .toolDecision:
            handleClaudeToolDecision(attributes: attributes, endTime: endTime, source: source)

        case .toolResult:
            handleClaudeToolResult(attributes: attributes, endTime: endTime, source: source)
        }
    }

    private func handleClaudeApiRequest(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        recordActivity()
        let durationMs = attributes.intValue(for: ["duration_ms", "durationMs"])
        let inputTokens = attributes.intValue(for: ["input_tokens", "gen_ai.usage.input_tokens"])
        let outputTokens = attributes.intValue(for: ["output_tokens", "gen_ai.usage.output_tokens"])
        let cacheReadTokens = attributes.intValue(for: ["cache_read_input_tokens", "cache_read_tokens"])
        let cacheCreationTokens = attributes.intValue(for: ["cache_creation_input_tokens", "cache_creation_tokens"])
        let model = attributes.stringValue(for: ["model", "gen_ai.request.model"])
        let statusCode = attributes.intValue(for: ["http.response.status_code", "status_code"])
        let costUsd = attributes.doubleValue(for: ["cost_usd", "cost", "price"])

        let startTime: Date
        if let durationMs {
            startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
        } else {
            startTime = endTime
        }

        // Update model if available
        if let model {
            currentModel = model
        }

        // Update token totals
        if let input = inputTokens {
            tokenCache["claude.input"] = Double(input)
        }
        if let output = outputTokens {
            tokenCache["claude.output"] = Double(output)
        }
        sessionTokenTotal = Int(tokenCache.values.reduce(0, +))

        if let cacheRead = cacheReadTokens {
            cacheTokenCache["claude.cache.read"] = Double(cacheRead)
        }
        if let cacheCreation = cacheCreationTokens {
            cacheTokenCache["claude.cache.creation"] = Double(cacheCreation)
        }
        sessionCacheTokens = Int(cacheTokenCache.values.reduce(0, +))

        let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)
        let success = statusCode == nil || statusCode! < 400

        toolCallTracker.recordCompletedToolCall(
            toolName: "Thinking",
            startTime: startTime,
            endTime: endTime,
            success: success,
            tokens: totalTokens > 0 ? totalTokens : nil,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUsd: costUsd,
            source: source
        )

        // print("[Telemetry] Claude API: model=\(model ?? "?") in=\(inputTokens ?? 0) out=\(outputTokens ?? 0) cost=$\(String(format: "%.4f", costUsd ?? 0))")
    }

    private func handleClaudeApiError(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        let errorMessage = attributes.stringValue(for: ["error.message", "error", "message"])
        let statusCode = attributes.intValue(for: ["http.response.status_code", "status_code"])
        let durationMs = attributes.intValue(for: ["duration_ms"])

        let startTime: Date
        if let durationMs {
            startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
        } else {
            startTime = endTime
        }

        let displayName = statusCode.map { "API Error (\($0))" } ?? "API Error"

        toolCallTracker.recordCompletedToolCall(
            toolName: displayName,
            startTime: startTime,
            endTime: endTime,
            success: false,
            tokens: nil,
            source: source
        )

        // print("[Telemetry] Claude API error: \(errorMessage ?? "unknown") status=\(statusCode ?? 0)")
    }

    private func handleClaudeUserPrompt(attributes: [String: TelemetryAttributeValue], endTime: Date) {
        let promptLength = attributes.intValue(for: ["prompt_length", "length"]) ?? 0
        // Note: actual prompt content is typically not sent for privacy
        // print("[Telemetry] Claude user prompt: \(promptLength) chars")
    }

    private func handleClaudeToolDecision(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        recordActivity()

        let toolName = attributes.stringValue(for: ["tool_name", "tool.name", "name"]) ?? "unknown"
        let callId = attributes.stringValue(for: ["call_id", "tool_call_id", "id"]) ?? UUID().uuidString
        let decision = attributes.stringValue(for: ["decision", "status"]) ?? "unknown"
        let decisionSource = attributes.stringValue(for: ["source", "decision_source"]) ?? "unknown"

        // print("[Telemetry] Claude tool decision: \(toolName) -> \(decision) (source: \(decisionSource))")

        let approved = decision.lowercased() == "approve" || decision.lowercased() == "approved" || decision.lowercased() == "accept"

        if approved {
            let toolCall = ToolCall(toolName: toolName, arguments: [:], startTime: endTime, source: source)
            pendingClaudeToolCalls[callId] = toolCall
            toolCallTracker.recordToolStart(id: callId, toolCall: toolCall)
        } else {
            toolCallTracker.recordCompletedToolCall(
                toolName: "\(toolName) (denied)",
                startTime: endTime,
                endTime: endTime,
                success: false,
                tokens: nil,
                source: source
            )
        }
    }

    private func handleClaudeToolResult(attributes: [String: TelemetryAttributeValue], endTime: Date, source: TelemetrySource) {
        recordActivity()
        let toolName = attributes.stringValue(for: ["tool_name", "tool.name", "name"]) ?? "unknown"
        let callId = attributes.stringValue(for: ["call_id", "tool_call_id", "id"]) ?? UUID().uuidString
        let durationMs = attributes.intValue(for: ["duration_ms", "execution_time_ms"])
        let success = attributes.boolValue(for: ["success", "is_success"]) ?? true
        let tokens = attributes.intValue(for: ["token_count", "tokens"])

        // Remove from pending if present
        pendingClaudeToolCalls.removeValue(forKey: callId)

        toolCallTracker.recordToolEnd(
            id: callId,
            success: success,
            durationMs: durationMs.map { Int64($0) },
            tokens: tokens,
            endTime: endTime
        )

        // print("[Telemetry] Claude tool result: \(toolName) success=\(success) duration=\(durationMs ?? 0)ms")
    }

    /// Handle generic Claude Code events that don't match specific types
    private func handleClaudeCodeGenericEvent(eventName: String, record: TelemetryLogRecord, source: TelemetrySource) {
        let attributes = record.attributes
        let endTime = record.timestamp
        let normalizedEvent = eventName.lowercased()

        // Extract common attributes
        let toolName = attributes.stringValue(for: ["tool_name", "tool.name", "name"])
        let durationMs = attributes.intValue(for: ["duration_ms"])
        let success = attributes.boolValue(for: ["success"]) ?? true
        let tokens = attributes.intValue(for: ["token_count", "tokens"])

        // Handle specific event patterns
        if normalizedEvent.contains("session") {
            // Session events - just log
            // print("[Telemetry] Claude session event: \(eventName)")
            return
        }

        if normalizedEvent.contains("cost") {
            // Cost tracking events
            if let cost = attributes.doubleValue(for: ["cost", "amount", "value"]) {
                // print("[Telemetry] Claude cost: $\(String(format: "%.4f", cost))")
            }
            return
        }

        if normalizedEvent.contains("lines_of_code") || normalizedEvent.contains("commit") || normalizedEvent.contains("pull_request") {
            // Activity metrics - log but don't create tool calls
            // print("[Telemetry] Claude activity: \(eventName)")
            return
        }

        // For other events, create a tool call entry if we have enough info
        if let toolName {
            let startTime: Date
            if let durationMs {
                startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
            } else {
                startTime = endTime
            }

            toolCallTracker.recordCompletedToolCall(
                toolName: toolName,
                startTime: startTime,
                endTime: endTime,
                success: success,
                tokens: tokens,
                source: source
            )
        }
    }

    // MARK: - Generic Event Handling (Claude Code, etc.)

    private func handleGenericLogRecord(eventName: String, record: TelemetryLogRecord, source: TelemetrySource) {
        recordActivity()
        let attributes = record.attributes
        let normalizedEvent = eventName.lowercased()
        let durationMs = attributes.intValue(for: ["duration_ms", "durationMs"]).map { Int64($0) }
        let endTime = record.timestamp

        // Handle API requests - show as "Thinking" in the notch
        if normalizedEvent.contains("api_request") || normalizedEvent.contains("api.request") {
            let inputTokens = attributes.intValue(for: ["input_tokens"])
            let outputTokens = attributes.intValue(for: ["output_tokens"])
            let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)

            let startTime: Date
            if let durationMs {
                startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
            } else {
                startTime = endTime
            }

            toolCallTracker.recordCompletedToolCall(
                toolName: "Thinking",
                startTime: startTime,
                endTime: endTime,
                success: true,
                tokens: totalTokens > 0 ? totalTokens : nil,
                source: source
            )
            return
        }

        // Handle tool events
        let toolName = attributes.stringValue(for: ["tool.name", "tool", "tool_name", "name"]) ?? "tool"
        let callId = attributes.stringValue(for: ["tool_call_id", "tool.id", "id", "request_id", "span_id"])
        let tokens = attributes.intValue(for: ["token_count", "tokens", "llm.tokens", "llm.token_count"])

        let success: Bool = {
            if let success = attributes.boolValue(for: ["success"]) {
                return success
            }
            if let status = attributes.stringValue(for: ["status", "outcome"])?.lowercased() {
                return status == "ok" || status == "success"
            }
            if let error = attributes.stringValue(for: ["error", "error.message"]) {
                return error.isEmpty
            }
            return true
        }()

        if normalizedEvent.contains("tool") && (normalizedEvent.contains("start") || normalizedEvent.contains("request")) {
            let id = callId ?? UUID().uuidString
            let toolCall = ToolCall(toolName: toolName, arguments: [:], startTime: record.timestamp, source: source)
            toolCallTracker.recordToolStart(id: id, toolCall: toolCall)
            return
        }

        if normalizedEvent.contains("tool") && (normalizedEvent.contains("end") || normalizedEvent.contains("result") || normalizedEvent.contains("response")) {
            let startTime: Date
            if let durationMs {
                startTime = endTime.addingTimeInterval(-TimeInterval(durationMs) / 1000.0)
            } else {
                startTime = endTime
            }

            if let id = callId {
                toolCallTracker.recordToolEnd(
                    id: id,
                    success: success,
                    durationMs: durationMs,
                    tokens: tokens,
                    endTime: endTime
                )
            } else {
                toolCallTracker.recordCompletedToolCall(
                    toolName: toolName,
                    startTime: startTime,
                    endTime: endTime,
                    success: success,
                    tokens: tokens,
                    source: source
                )
            }
        }
    }
}

private extension Dictionary where Key == String, Value == TelemetryAttributeValue {
    func stringValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue {
                return value
            }
        }
        return nil
    }

    func intValue(for keys: [String]) -> Int? {
        for key in keys {
            if let value = self[key]?.intValue {
                return value
            }
        }
        return nil
    }

    func boolValue(for keys: [String]) -> Bool? {
        for key in keys {
            if let value = self[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    func doubleValue(for keys: [String]) -> Double? {
        for key in keys {
            if let value = self[key]?.doubleValue {
                return value
            }
        }
        return nil
    }
}
