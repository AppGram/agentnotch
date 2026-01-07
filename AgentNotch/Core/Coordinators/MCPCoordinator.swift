import Foundation
import Combine

@MainActor
public final class MCPCoordinator: ObservableObject {
    public static let shared = MCPCoordinator()

    @Published private(set) var state: MCPServerState = .stopped
    @Published private(set) var recentToolCalls: [ToolCall] = []
    @Published private(set) var currentBuildTime: TimeInterval?
    @Published private(set) var lastBuildResult: XcodeBuildResult?
    @Published private(set) var errorOutput: String = ""

    private var processManager: MCPProcessManager?
    private let stdioHandler = StdioHandler()
    private let toolCallTracker = ToolCallTracker(maxRecentCalls: AppSettings.shared.recentToolCallsLimit)
    private let processMonitor = ProcessMonitor()
    private let parser = JSONRPCParser()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Forward tool call tracker updates
        toolCallTracker.$recentToolCalls
            .receive(on: DispatchQueue.main)
            .assign(to: &$recentToolCalls)

        toolCallTracker.$currentBuildTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentBuildTime)

        toolCallTracker.$lastBuildResult
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastBuildResult)

        // Setup restart handler
        processMonitor.onRestartNeeded = { [weak self] in
            try await self?.start()
        }

        // Setup stdio handler
        stdioHandler.onLineReceived = { [weak self] line in
            Task { @MainActor in
                self?.handleMCPLine(line)
            }
        }
    }

    public func start() async throws {
        guard state == .stopped || state.isActive == false else {
            return
        }

        state = .starting
        errorOutput = ""
        toolCallTracker.clear()

        let config = AppSettings.shared.mcpConfiguration
        let manager = MCPProcessManager(configuration: config)
        manager.delegate = self
        processManager = manager

        do {
            try await manager.launch()
            state = .running
            processMonitor.resetAttempts()
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    public func stop() async {
        guard state == .running || state == .starting else {
            return
        }

        state = .stopping
        processMonitor.cancelPendingRestart()

        await processManager?.terminate()
        processManager = nil

        state = .stopped
    }

    public func restart() async throws {
        await stop()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        try await start()
    }

    private func handleMCPLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        let message = parser.parse(data)

        switch message {
        case .request(let request):
            // Outgoing request to MCP server - track tool calls
            toolCallTracker.recordRequest(request)

        case .response(let response):
            // Response from MCP server
            _ = toolCallTracker.recordResponse(response)

        case .notification:
            // Notifications (like progress updates) - ignore for now
            break

        case .invalid:
            // Invalid JSON-RPC - might be log output, ignore
            break
        }
    }
}

extension MCPCoordinator: MCPProcessManagerDelegate {
    nonisolated func processManager(_ manager: MCPProcessManager, didReceiveOutput data: Data) {
        Task { @MainActor in
            self.stdioHandler.processReceivedData(data)
        }
    }

    nonisolated func processManager(_ manager: MCPProcessManager, didReceiveError data: Data) {
        if let errorString = String(data: data, encoding: .utf8) {
            Task { @MainActor in
                self.errorOutput += errorString
                // Parse tool events from stderr
                self.parseStderrEvents(errorString)
            }
        }
    }

    @MainActor
    private func parseStderrEvents(_ output: String) {
        // Split by newlines and parse each JSON line
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8) else { continue }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let event = json["event"] as? String,
                   let tool = json["tool"] as? String,
                   let id = json["id"] as? String {

                    if event == "tool_start" {
                        // Create new tool call
                        let toolCall = ToolCall(toolName: tool)
                        toolCallTracker.recordToolStart(id: id, toolCall: toolCall)
                    } else if event == "tool_end" {
                        let success = json["success"] as? Bool ?? false
                        let durationMs = json["duration_ms"] as? Int64
                        let tokens = json["tokens"] as? Int
                        toolCallTracker.recordToolEnd(id: id, success: success, durationMs: durationMs, tokens: tokens)
                    }
                }
            } catch {
                // Not JSON or invalid format - ignore
            }
        }
    }

    nonisolated func processManager(_ manager: MCPProcessManager, didTerminateWithStatus status: Int32) {
        Task { @MainActor in
            if status != 0 {
                self.state = .crashed(reason: "Exit code: \(status)")
            } else {
                self.state = .stopped
            }

            if AppSettings.shared.autoRestartOnCrash {
                await self.processMonitor.handleTermination(status: status)
            }
        }
    }
}
