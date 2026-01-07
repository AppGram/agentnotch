//
//  ClaudeCodeManager.swift
//  AgentNotch
//
//  Created for Claude Code JSONL session integration
//

import Foundation
import Combine
import AppKit

// MARK: - Debug Logging (disabled in Release builds)

/// Debug-only logging function - prints only in DEBUG builds to save CPU in production
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

@MainActor
final class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    // MARK: - Cached Formatters
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Published Properties

    @Published private(set) var availableSessions: [ClaudeSession] = []
    @Published var selectedSession: ClaudeSession?
    @Published private(set) var state: ClaudeCodeState = ClaudeCodeState()
    @Published private(set) var dailyStats: ClaudeDailyStats = ClaudeDailyStats()

    // MARK: - Multi-Session Permission Tracking

    /// Per-session state tracking for permission detection
    @Published private(set) var sessionStates: [String: ClaudeCodeState] = [:]

    /// Sessions currently waiting for user permission approval
    @Published private(set) var sessionsNeedingPermission: [ClaudeSession] = []

    /// Track when we last had activity (for grace period before notch collapses)
    private var lastActivityTime: Date = Date.distantPast
    /// Grace period to keep notch visible after activity stops (seconds)
    private let activityGracePeriod: TimeInterval = 1.0

    /// True if any session has activity (thinking, active tools, or needs permission)
    var hasAnySessionActivity: Bool {
        for sessionState in sessionStates.values {
            if sessionState.isActive || sessionState.needsPermission {
                lastActivityTime = Date()
                return true
            }
        }
        if state.isActive || state.needsPermission {
            lastActivityTime = Date()
            return true
        }
        if !sessionsNeedingPermission.isEmpty {
            lastActivityTime = Date()
            return true
        }

        let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
        if timeSinceLastActivity < activityGracePeriod {
            return true
        }

        return false
    }

    // MARK: - Private Properties

    private let claudeDir: URL = {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            let homePath = String(cString: home)
            return URL(fileURLWithPath: homePath).appendingPathComponent(".claude")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }()
    private var ideDir: URL { claudeDir.appendingPathComponent("ide") }
    private var projectsDir: URL { claudeDir.appendingPathComponent("projects") }

    private var sessionFileWatcher: DispatchSourceFileSystemObject?
    private var sessionFileHandle: FileHandle?
    private var lastReadPosition: UInt64 = 0

    private var sessionScanTimer: Timer?

    /// Timer to detect when a tool is waiting for permission (no result after delay)
    private var permissionCheckTimer: Timer?
    /// Tracks tool IDs that we're waiting on for permission check
    private var pendingToolChecks: [String: Date] = [:]
    /// Delay before assuming a tool needs permission (seconds)
    private let permissionCheckDelay: TimeInterval = 2.5
    /// Flag to disable permission tracking during history loading
    private var isLoadingHistory: Bool = false

    // MARK: - Multi-Session Watching

    private var sessionWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var sessionFileHandles: [String: FileHandle] = [:]
    private var sessionReadPositions: [String: UInt64] = [:]
    private var pendingToolChecksBySession: [String: [String: Date]] = [:]
    private var isLoadingHistoryBySession: [String: Bool] = [:]

    /// Timer to detect idle state (for thinking)
    private var idleCheckTimer: Timer?
    private let idleCheckDelay: TimeInterval = 3.0

    /// Timer to detect tool idle state (no new tool for 10 seconds = session done)
    private var toolIdleTimer: Timer?
    private let toolIdleDelay: TimeInterval = 10.0

    // MARK: - Initialization

    private init() {
        debugLog("[ClaudeCode] ========================================")
        debugLog("[ClaudeCode] ClaudeCodeManager initializing...")
        debugLog("[ClaudeCode] Claude dir: \(claudeDir.path)")
        debugLog("[ClaudeCode] IDE dir: \(ideDir.path)")
        debugLog("[ClaudeCode] Projects dir: \(projectsDir.path)")
        debugLog("[ClaudeCode] ========================================")
        startSessionScanning()
        loadDailyStats()
    }

    // MARK: - Public Methods

    /// Scan for active Claude Code sessions
    func scanForSessions() {
        let fm = FileManager.default
        var sessions: [ClaudeSession] = []

        debugLog("[ClaudeCode] Scanning for sessions...")

        // First try IDE lock files (for VS Code/Cursor extensions)
        if fm.fileExists(atPath: ideDir.path) {
            debugLog("[ClaudeCode] Checking IDE dir: \(ideDir.path)")

            do {
                let allFiles = try fm.contentsOfDirectory(at: ideDir, includingPropertiesForKeys: nil)
                let lockFiles = allFiles.filter { $0.pathExtension == "lock" }
                debugLog("[ClaudeCode] Found \(lockFiles.count) IDE lock files")

                for lockFile in lockFiles {
                    guard let data = fm.contents(atPath: lockFile.path) else { continue }

                    do {
                        let session = try JSONDecoder().decode(ClaudeSession.self, from: data)
                        if isProcessRunning(pid: session.pid) {
                            debugLog("[ClaudeCode] IDE session: \(session.displayName) (pid \(session.pid))")
                            sessions.append(session)
                        }
                    } catch {
                        debugLog("[ClaudeCode] Failed to decode lock file: \(error)")
                    }
                }
            } catch {
                debugLog("[ClaudeCode] Error reading IDE dir: \(error)")
            }
        } else {
            debugLog("[ClaudeCode] No IDE dir - checking for terminal sessions")
        }

        // If no IDE sessions, discover from recently active project JSONL files
        if sessions.isEmpty && fm.fileExists(atPath: projectsDir.path) {
            debugLog("[ClaudeCode] Scanning projects dir for active terminal sessions...")

            do {
                let projectDirs = try fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey])
                    .filter { url in
                        var isDir: ObjCBool = false
                        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                    }

                // Find projects with recently modified JSONL files (last 5 minutes)
                let recentThreshold = Date().addingTimeInterval(-300) // 5 minutes

                for projectDir in projectDirs {
                    if let jsonlFile = findCurrentSessionFile(in: projectDir) {
                        let attrs = try? fm.attributesOfItem(atPath: jsonlFile.path)
                        let modDate = attrs?[.modificationDate] as? Date ?? .distantPast

                        if modDate > recentThreshold {
                            // Create a synthetic session for this terminal project
                            let workspacePath = projectDir.lastPathComponent
                                .replacingOccurrences(of: "-", with: "/")

                            let session = ClaudeSession(
                                pid: 0,  // Terminal sessions don't have a single PID
                                workspaceFolders: [workspacePath],
                                ideName: "Terminal",
                                transport: nil,
                                runningInWindows: nil
                            )
                            debugLog("[ClaudeCode] Terminal session: \(session.displayName) (modified \(Int(-modDate.timeIntervalSinceNow))s ago)")
                            sessions.append(session)
                        }
                    }
                }
            } catch {
                debugLog("[ClaudeCode] Error scanning projects: \(error)")
            }
        }

        debugLog("[ClaudeCode] Total sessions found: \(sessions.count)")
        availableSessions = sessions

        if selectedSession == nil && sessions.count == 1 {
            selectSession(sessions[0])
        }

        if let selected = selectedSession,
           !sessions.contains(where: { $0.id == selected.id }) {
            selectedSession = nil
            state = ClaudeCodeState()
            stopWatchingSessionFile()
        }

        // Watch ALL sessions for permission detection
        let currentSessionIds = Set(sessions.map { $0.id })

        for session in sessions {
            if sessionWatchers[session.id] == nil {
                startWatchingSession(session)
            }
        }

        let watchedIds = Array(sessionWatchers.keys)
        for watchedId in watchedIds where !currentSessionIds.contains(watchedId) {
            stopWatchingSession(id: watchedId)
        }
    }

    /// Select a session to monitor
    func selectSession(_ session: ClaudeSession) {
        guard session != selectedSession else { return }

        debugLog("[ClaudeCode] Selecting session: \(session.displayName)")
        selectedSession = session
        state = ClaudeCodeState()
        state.cwd = session.workspaceFolders.first ?? ""

        startWatchingSessionFile()
    }

    /// Manually refresh state
    func refresh() {
        scanForSessions()
        if selectedSession != nil {
            readNewSessionData()
        }
    }

    /// Bring the IDE running Claude Code to the front
    func focusIDE(for session: ClaudeSession? = nil) {
        guard let targetSession = session ?? selectedSession else {
            debugLog("[ClaudeCode] No session to focus")
            return
        }

        let ideName = targetSession.ideName.lowercased()
        debugLog("[ClaudeCode] Attempting to focus IDE: \(targetSession.ideName)")

        let bundleIdentifiers: [String] = {
            if ideName.contains("cursor") {
                return ["com.todesktop.230313mzl4w4u92"]
            } else if ideName.contains("code") || ideName.contains("vscode") {
                return ["com.microsoft.VSCode", "com.visualstudio.code.oss"]
            } else if ideName.contains("windsurf") {
                return ["com.codeium.windsurf"]
            } else if ideName.contains("zed") {
                return ["dev.zed.Zed"]
            } else {
                return []
            }
        }()

        for bundleId in bundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateIgnoringOtherApps])
                return
            }
        }

        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.processIdentifier == Int32(targetSession.pid) }) {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let app = runningApps.first(where: {
            $0.localizedName?.lowercased().contains(ideName) == true
        }) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Session Scanning

    private func startSessionScanning() {
        scanForSessions()
        sessionScanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForSessions()
                self?.loadDailyStats()
            }
        }
    }

    private func isProcessRunning(pid: Int) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        if runningApps.contains(where: { $0.processIdentifier == Int32(pid) }) {
            return true
        }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && size > 0
    }

    // MARK: - File Watching

    private func startWatchingSessionFile() {
        stopWatchingSessionFile()

        guard let session = selectedSession,
              let projectKey = session.projectKey else {
            return
        }

        let projectDir = projectsDir.appendingPathComponent(projectKey)
        guard let jsonlFile = findCurrentSessionFile(in: projectDir) else {
            debugLog("[ClaudeCode] No session file found for project: \(projectKey)")
            return
        }

        debugLog("[ClaudeCode] Watching session file: \(jsonlFile.path)")

        do {
            sessionFileHandle = try FileHandle(forReadingFrom: jsonlFile)
            sessionFileHandle?.seekToEndOfFile()
            lastReadPosition = sessionFileHandle?.offsetInFile ?? 0
            loadRecentHistory(from: jsonlFile)
        } catch {
            debugLog("Error opening session file: \(error)")
            return
        }

        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else {
            debugLog("Failed to open file descriptor for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewSessionData()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sessionFileWatcher = source
        state.isConnected = true
    }

    private func stopWatchingSessionFile() {
        sessionFileWatcher?.cancel()
        sessionFileWatcher = nil
        sessionFileHandle?.closeFile()
        sessionFileHandle = nil
        lastReadPosition = 0
        state.isConnected = false
    }

    private func stopWatching() {
        sessionScanTimer?.invalidate()
        sessionScanTimer = nil
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
        toolIdleTimer?.invalidate()
        toolIdleTimer = nil
        stopWatchingSessionFile()

        for sessionId in sessionWatchers.keys {
            stopWatchingSession(id: sessionId)
        }
    }

    // MARK: - Multi-Session Watching

    private func startWatchingSession(_ session: ClaudeSession) {
        debugLog("[ClaudeCode] startWatchingSession: \(session.displayName)")
        guard sessionWatchers[session.id] == nil else {
            debugLog("[ClaudeCode]   - Already watching")
            return
        }

        // Try to find the project directory
        var projectDir: URL?
        var jsonlFile: URL?

        // First try direct projectKey match
        if let projectKey = session.projectKey {
            debugLog("[ClaudeCode]   - Project key: \(projectKey)")
            let directPath = projectsDir.appendingPathComponent(projectKey)
            if let file = findCurrentSessionFile(in: directPath) {
                projectDir = directPath
                jsonlFile = file
                debugLog("[ClaudeCode]   - Found via direct match: \(directPath.path)")
            }
        }

        // Fallback: scan all project directories for a match
        if jsonlFile == nil, let workspace = session.workspaceFolders.first {
            debugLog("[ClaudeCode]   - Direct match failed, scanning all projects...")
            let fm = FileManager.default

            if let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) {
                // Look for directory that matches the workspace path
                let normalizedWorkspace = workspace.lowercased()
                for dir in projectDirs {
                    // Convert dir name back to path: "-Users-foo-project" -> "/Users/foo/project"
                    let dirName = dir.lastPathComponent
                    let dirPath = dirName.replacingOccurrences(of: "-", with: "/")
                    // Handle leading dash correctly (absolute paths start with /)
                    let normalizedDirPath = dirPath.hasPrefix("/") ? dirPath : "/" + dirPath
                    if normalizedDirPath.lowercased() == normalizedWorkspace {
                        if let file = findCurrentSessionFile(in: dir) {
                            projectDir = dir
                            jsonlFile = file
                            debugLog("[ClaudeCode]   - Found via scan: \(dir.path)")
                            break
                        }
                    }
                }
            }
        }

        guard let jsonlFile = jsonlFile else {
            debugLog("[ClaudeCode]   - No JSONL file found!")
            return
        }

        debugLog("[ClaudeCode]   - Found JSONL: \(jsonlFile.lastPathComponent)")

        var sessionState = ClaudeCodeState()
        sessionState.cwd = session.workspaceFolders.first ?? ""
        sessionState.isConnected = true
        sessionStates[session.id] = sessionState

        do {
            let handle = try FileHandle(forReadingFrom: jsonlFile)
            handle.seekToEndOfFile()
            sessionFileHandles[session.id] = handle
            sessionReadPositions[session.id] = handle.offsetInFile
            loadRecentHistoryForSession(from: jsonlFile, sessionId: session.id)
        } catch {
            return
        }

        let fd = open(jsonlFile.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.readNewSessionDataForSession(sessionId: session.id)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        sessionWatchers[session.id] = source
    }

    private func stopWatchingSession(id sessionId: String) {
        sessionWatchers[sessionId]?.cancel()
        sessionWatchers.removeValue(forKey: sessionId)
        sessionFileHandles[sessionId]?.closeFile()
        sessionFileHandles.removeValue(forKey: sessionId)
        sessionReadPositions.removeValue(forKey: sessionId)
        sessionStates.removeValue(forKey: sessionId)
        pendingToolChecksBySession.removeValue(forKey: sessionId)
        isLoadingHistoryBySession.removeValue(forKey: sessionId)
        sessionsNeedingPermission.removeAll { $0.id == sessionId }
    }

    private func loadRecentHistoryForSession(from file: URL, sessionId: String) {
        let maxBytesToRead: UInt64 = 50 * 1024

        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let startPosition = fileSize > maxBytesToRead ? fileSize - maxBytesToRead : 0
        handle.seek(toFileOffset: startPosition)

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        let linesToProcess = startPosition > 0 ? Array(lines.dropFirst().suffix(50)) : Array(lines.suffix(50))

        isLoadingHistoryBySession[sessionId] = true
        for line in linesToProcess where !line.isEmpty {
            parseJSONLLineForSession(line, sessionId: sessionId)
        }
        isLoadingHistoryBySession[sessionId] = false

        // Clear active state after history loading (we're not currently active)
        if var sessionState = sessionStates[sessionId] {
            sessionState.activeTools.removeAll()
            sessionState.isThinking = false
            sessionStates[sessionId] = sessionState

            // Also sync to main state if this is the selected session
            if selectedSession?.id == sessionId {
                state.isThinking = false
                state.activeTools.removeAll()
            }
        }
        pendingToolChecksBySession[sessionId]?.removeAll()

        // Start idle timer to ensure UI updates
        resetIdleTimer()
    }

    private func readNewSessionDataForSession(sessionId: String) {
        guard let handle = sessionFileHandles[sessionId],
              let lastPosition = sessionReadPositions[sessionId] else { return }

        handle.seek(toFileOffset: lastPosition)
        let newData = handle.readDataToEndOfFile()
        sessionReadPositions[sessionId] = handle.offsetInFile

        guard !newData.isEmpty,
              let content = String(data: newData, encoding: .utf8) else { return }

        // Notify observers BEFORE mutations for proper reactivity
        objectWillChange.send()

        // Any file activity means Claude is working
        if var sessionState = sessionStates[sessionId] {
            sessionState.isThinking = true
            sessionStates[sessionId] = sessionState
        }
        debugLog("[ClaudeCode] Session \(sessionId.prefix(8))... activity detected, isThinking=true")

        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseJSONLLineForSession(line, sessionId: sessionId)
        }

        if var sessionState = sessionStates[sessionId] {
            sessionState.lastUpdateTime = Date()
            sessionStates[sessionId] = sessionState
        }

        resetIdleTimer()
    }

    private func resetIdleTimer() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: idleCheckDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markAllSessionsIdle()
            }
        }
    }

    private func markAllSessionsIdle() {
        objectWillChange.send()
        for sessionId in sessionStates.keys {
            if var sessionState = sessionStates[sessionId], sessionState.needsPermission != true {
                sessionState.isThinking = false
                sessionStates[sessionId] = sessionState
            }
        }
        if !state.needsPermission {
            state.isThinking = false
        }
    }

    /// Reset the tool idle timer - called when any tool activity is detected
    private func resetToolIdleTimer() {
        toolIdleTimer?.invalidate()
        toolIdleTimer = Timer.scheduledTimer(withTimeInterval: toolIdleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.markSessionDoneAfterToolIdle()
            }
        }
    }

    /// Called after 10 seconds of no tool activity - mark session as done
    private func markSessionDoneAfterToolIdle() {
        debugLog("[ClaudeCode] Tool idle timeout - marking sessions as done")
        objectWillChange.send()

        // Clear all active states
        for sessionId in sessionStates.keys {
            if var sessionState = sessionStates[sessionId] {
                if sessionState.activeTools.isEmpty && !sessionState.needsPermission {
                    sessionState.isThinking = false
                    sessionState.lastStopReason = "idle_timeout"
                    sessionStates[sessionId] = sessionState
                }
            }
        }

        if state.activeTools.isEmpty && !state.needsPermission {
            state.isThinking = false
            state.lastStopReason = "idle_timeout"
        }

        // Clear any stale pending permission checks
        pendingToolChecks.removeAll()
        for sessionId in pendingToolChecksBySession.keys {
            pendingToolChecksBySession[sessionId]?.removeAll()
        }
        updateSessionsNeedingPermission()
    }

    private func parseJSONLLineForSession(_ line: String, sessionId: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Check for interruption in toolUseResult
        if let toolUseResult = json["toolUseResult"] {
            let resultStr = "\(toolUseResult)"
            if resultStr.contains("interrupted by user") || resultStr.contains("Request interrupted") {
                debugLog("[ClaudeCode] Detected user interruption in toolUseResult for session \(sessionId.prefix(8))...")
                if var sessionState = sessionStates[sessionId] {
                    sessionState.isThinking = false
                    sessionState.lastStopReason = "interrupted"
                    sessionState.activeTools.removeAll()
                    sessionStates[sessionId] = sessionState

                    // Sync to main state if selected
                    if selectedSession?.id == sessionId {
                        state.isThinking = false
                        state.lastStopReason = "interrupted"
                        state.activeTools.removeAll()
                    }
                }
                // Clear any pending permission checks
                pendingToolChecksBySession[sessionId]?.removeAll()
                updateSessionsNeedingPermission()
            }
        }

        if let message = json["message"] as? [String: Any] {
            parseMessageForSession(message, sessionId: sessionId)
        }
    }

    private func parseMessageForSession(_ message: [String: Any], sessionId: String) {
        guard var sessionState = sessionStates[sessionId] else { return }

        if let model = message["model"] as? String {
            sessionState.model = model
        }

        // Track stop_reason for session completion detection
        if let stopReason = message["stop_reason"] as? String {
            sessionState.lastStopReason = stopReason
            if stopReason == "end_turn" {
                sessionState.isThinking = false
            }
        }

        if let role = message["role"] as? String {
            if role == "user" || role == "assistant" {
                sessionState.isThinking = true
                // Reset stop_reason when new activity starts
                sessionState.lastStopReason = nil
            }
        }

        if let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String {
                    switch type {
                    case "thinking":
                        // Only mark as thinking if no recent tools completed (first thinking)
                        // or if we have active tools running
                        // If we have recent tools but no active tools, it's just final output
                        if sessionState.activeTools.isEmpty && !sessionState.recentTools.isEmpty {
                            // Post-tool thinking = final output, mark as completing
                            debugLog("[ClaudeCode] Post-tool thinking detected - session completing")
                            sessionState.isThinking = false
                        } else {
                            sessionState.isThinking = true
                        }

                    case "text":
                        // Text output means we're in final response phase
                        if sessionState.activeTools.isEmpty && !sessionState.recentTools.isEmpty {
                            sessionState.isThinking = false
                        }
                        // Check for interruption message
                        if let text = item["text"] as? String,
                           text.contains("[Request interrupted by user") {
                            debugLog("[ClaudeCode] Detected user interruption for session \(sessionId.prefix(8))...")
                            sessionState.isThinking = false
                            sessionState.lastStopReason = "interrupted"
                            sessionState.activeTools.removeAll()
                        }

                    case "tool_use":
                        // Tool use means thinking is done, now acting
                        sessionState.isThinking = false
                        // Reset tool idle timer - new tool activity detected
                        resetToolIdleTimer()

                        if let toolId = item["id"] as? String,
                           let toolName = item["name"] as? String {

                            var toolDescription: String?
                            var toolTimeout: Int?

                            if let input = item["input"] as? [String: Any] {
                                toolDescription = input["description"] as? String
                                toolTimeout = input["timeout"] as? Int
                            }

                            // Parse TodoWrite tool to extract todos
                            if toolName == "TodoWrite",
                               let input = item["input"] as? [String: Any],
                               let todos = input["todos"] as? [[String: Any]] {
                                sessionState.todos = parseTodosFromArray(todos)
                                // Also update main state todos for selected session
                                if selectedSession?.id == sessionId {
                                    state.todos = sessionState.todos
                                }
                            }

                            var tool = ClaudeToolExecution(
                                id: toolId,
                                toolName: toolName,
                                argument: extractToolArgument(from: item["input"]),
                                startTime: Date()
                            )
                            tool.description = toolDescription
                            tool.timeout = toolTimeout

                            if !sessionState.activeTools.contains(where: { $0.id == toolId }) {
                                debugLog("[ClaudeCode] Tool started: \(toolName) (id: \(toolId.prefix(8))...) desc: \(toolDescription ?? "-")")
                                sessionState.activeTools.append(tool)
                                sessionStates[sessionId] = sessionState
                                startPermissionCheckForSession(sessionId: sessionId, toolId: toolId, toolName: toolName)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }

        // Parse usage for token tracking
        if let usage = message["usage"] as? [String: Any] {
            sessionState.tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? sessionState.tokenUsage.inputTokens
            sessionState.tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? sessionState.tokenUsage.outputTokens
            sessionState.tokenUsage.cacheReadInputTokens = usage["cache_read_input_tokens"] as? Int ?? sessionState.tokenUsage.cacheReadInputTokens
            sessionState.tokenUsage.cacheCreationInputTokens = usage["cache_creation_input_tokens"] as? Int ?? sessionState.tokenUsage.cacheCreationInputTokens
        }

        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    clearPermissionCheckForSession(sessionId: sessionId, toolId: toolUseId)

                    // Move tool to recentTools instead of just removing
                    if let index = sessionState.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                        var tool = sessionState.activeTools.remove(at: index)
                        tool.endTime = Date()
                        // Attach current token usage to the completed tool
                        tool.inputTokens = sessionState.tokenUsage.inputTokens
                        tool.outputTokens = sessionState.tokenUsage.outputTokens
                        tool.cacheReadTokens = sessionState.tokenUsage.cacheReadInputTokens
                        tool.cacheWriteTokens = sessionState.tokenUsage.cacheCreationInputTokens
                        debugLog("[ClaudeCode] Tool completed: \(tool.toolName) (id: \(toolUseId.prefix(8))...) in:\(tool.inputTokens ?? 0) out:\(tool.outputTokens ?? 0)")
                        sessionState.recentTools.insert(tool, at: 0)
                        if sessionState.recentTools.count > 10 {
                            sessionState.recentTools.removeLast()
                        }
                        // Also update main state if this is the selected session
                        if selectedSession?.id == sessionId {
                            state.recentTools = sessionState.recentTools
                        }
                    }

                    sessionState.isThinking = true
                }
            }
        }

        sessionStates[sessionId] = sessionState

        // Sync main state if this is the selected session
        if selectedSession?.id == sessionId {
            state.isThinking = sessionState.isThinking
            state.activeTools = sessionState.activeTools
            state.recentTools = sessionState.recentTools
            state.todos = sessionState.todos
            state.needsPermission = sessionState.needsPermission
            state.pendingPermissionTool = sessionState.pendingPermissionTool
            state.model = sessionState.model
            state.lastUpdateTime = sessionState.lastUpdateTime
            state.lastStopReason = sessionState.lastStopReason
            state.tokenUsage = sessionState.tokenUsage
        }

        objectWillChange.send()
    }

    /// Helper to parse todos array into ClaudeTodoItem array
    private func parseTodosFromArray(_ todosArray: [[String: Any]]) -> [ClaudeTodoItem] {
        var newTodos: [ClaudeTodoItem] = []

        for todoDict in todosArray {
            guard let content = todoDict["content"] as? String,
                  let statusStr = todoDict["status"] as? String else {
                continue
            }

            let status: ClaudeTodoItem.TodoStatus
            switch statusStr {
            case "pending":
                status = .pending
            case "in_progress":
                status = .inProgress
            case "completed":
                status = .completed
            default:
                status = .pending
            }

            newTodos.append(ClaudeTodoItem(content: content, status: status))
        }

        return newTodos
    }

    private func startPermissionCheckForSession(sessionId: String, toolId: String, toolName: String) {
        guard isLoadingHistoryBySession[sessionId] != true else { return }

        pendingToolChecksBySession[sessionId, default: [:]][toolId] = Date()

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingPermissionsForAllSessions()
            }
        }
    }

    private func clearPermissionCheckForSession(sessionId: String, toolId: String) {
        pendingToolChecksBySession[sessionId]?.removeValue(forKey: toolId)

        if var sessionState = sessionStates[sessionId], sessionState.needsPermission == true {
            if pendingToolChecksBySession[sessionId]?.isEmpty ?? true {
                sessionState.needsPermission = false
                sessionState.pendingPermissionTool = nil
                sessionStates[sessionId] = sessionState
                objectWillChange.send()
            }
        }

        updateSessionsNeedingPermission()
    }

    private func checkPendingPermissionsForAllSessions() {
        let now = Date()
        var needsUIUpdate = false

        for (sessionId, toolChecks) in pendingToolChecksBySession {
            for (toolId, startTime) in toolChecks {
                let elapsed = now.timeIntervalSince(startTime)
                if elapsed >= permissionCheckDelay {
                    if var sessionState = sessionStates[sessionId],
                       let tool = sessionState.activeTools.first(where: { $0.id == toolId }) {
                        sessionState.needsPermission = true
                        sessionState.pendingPermissionTool = tool.toolName
                        sessionStates[sessionId] = sessionState
                        needsUIUpdate = true
                        debugLog("[ClaudeCode] Session \(sessionId.prefix(8))... needs permission for \(tool.toolName)")
                        break
                    }
                }
            }
        }

        if needsUIUpdate {
            objectWillChange.send()
        }

        updateSessionsNeedingPermission()

        let hasPendingTools = pendingToolChecksBySession.values.contains { !$0.isEmpty }
        if !hasPendingTools {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    private func updateSessionsNeedingPermission() {
        var needingPermission: [ClaudeSession] = []

        for session in availableSessions {
            if sessionStates[session.id]?.needsPermission == true {
                needingPermission.append(session)
            }
        }

        if state.needsPermission, let selected = selectedSession {
            if !needingPermission.contains(where: { $0.id == selected.id }) {
                needingPermission.append(selected)
            }
        }

        sessionsNeedingPermission = needingPermission
    }

    private func findCurrentSessionFile(in projectDir: URL) -> URL? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: projectDir.path) else {
            debugLog("[ClaudeCode] findCurrentSessionFile: directory does not exist: \(projectDir.path)")
            return nil
        }

        do {
            let allFiles = try fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey])
            debugLog("[ClaudeCode] findCurrentSessionFile: \(allFiles.count) files in \(projectDir.lastPathComponent)")

            let files = allFiles
                .filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return date1 > date2
                }

            debugLog("[ClaudeCode] findCurrentSessionFile: \(files.count) JSONL files found")
            if let first = files.first {
                debugLog("[ClaudeCode] findCurrentSessionFile: using \(first.lastPathComponent)")
            }

            return files.first
        } catch {
            debugLog("[ClaudeCode] findCurrentSessionFile: error: \(error)")
            return nil
        }
    }

    // MARK: - Data Reading

    private func loadRecentHistory(from file: URL) {
        let maxBytesToRead: UInt64 = 50 * 1024

        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let startPosition = fileSize > maxBytesToRead ? fileSize - maxBytesToRead : 0
        handle.seek(toFileOffset: startPosition)

        guard let data = try? handle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        let linesToProcess = startPosition > 0 ? Array(lines.dropFirst().suffix(50)) : Array(lines.suffix(50))

        isLoadingHistory = true
        for line in linesToProcess where !line.isEmpty {
            parseJSONLLine(line)
        }
        isLoadingHistory = false

        state.activeTools.removeAll()
        state.isThinking = false
        pendingToolChecks.removeAll()

        state.lastUpdateTime = Date()
    }

    private func readNewSessionData() {
        guard let handle = sessionFileHandle else { return }

        handle.seek(toFileOffset: lastReadPosition)
        let newData = handle.readDataToEndOfFile()
        lastReadPosition = handle.offsetInFile

        guard !newData.isEmpty,
              let content = String(data: newData, encoding: .utf8) else { return }

        // Any file activity = Claude is working (compacting/summarizing)
        state.isThinking = true

        let lines = content.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            parseJSONLLine(line)
        }

        state.lastUpdateTime = Date()
        resetIdleTimer()
    }

    // MARK: - JSONL Parsing

    private func parseJSONLLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // DEBUG: Print all top-level JSONL fields
        debugLog("[JSONL DEBUG] ========== NEW LINE ==========")
        debugLog("[JSONL DEBUG] Top-level keys: \(json.keys.sorted().joined(separator: ", "))")

        // Print each top-level field
        if let sessionId = json["sessionId"] as? String {
            debugLog("[JSONL DEBUG] sessionId: \(sessionId)")
            state.sessionId = sessionId
        }
        if let cwd = json["cwd"] as? String {
            debugLog("[JSONL DEBUG] cwd: \(cwd)")
            state.cwd = cwd
        }
        if let gitBranch = json["gitBranch"] as? String {
            debugLog("[JSONL DEBUG] gitBranch: \(gitBranch)")
            state.gitBranch = gitBranch
        }
        if let uuid = json["uuid"] as? String {
            debugLog("[JSONL DEBUG] uuid: \(uuid)")
        }
        if let parentUuid = json["parentUuid"] as? String {
            debugLog("[JSONL DEBUG] parentUuid: \(parentUuid)")
        }
        if let timestamp = json["timestamp"] as? String {
            debugLog("[JSONL DEBUG] timestamp: \(timestamp)")
        }
        if let isSidechain = json["isSidechain"] as? Bool {
            debugLog("[JSONL DEBUG] isSidechain: \(isSidechain)")
        }
        if let userType = json["userType"] as? String {
            debugLog("[JSONL DEBUG] userType: \(userType)")
        }
        if let version = json["version"] as? String {
            debugLog("[JSONL DEBUG] version: \(version)")
        }
        if let slug = json["slug"] as? String {
            debugLog("[JSONL DEBUG] slug: \(slug)")
        }
        if let requestId = json["requestId"] as? String {
            debugLog("[JSONL DEBUG] requestId: \(requestId)")
        }
        if let type = json["type"] as? String {
            debugLog("[JSONL DEBUG] type: \(type)")
        }
        if let toolUseResult = json["toolUseResult"] {
            debugLog("[JSONL DEBUG] toolUseResult: \(toolUseResult)")
            // Check for interruption in toolUseResult
            let resultStr = "\(toolUseResult)"
            if resultStr.contains("interrupted by user") || resultStr.contains("Request interrupted") {
                debugLog("[JSONL DEBUG] Detected user interruption in toolUseResult - marking as done")
                state.isThinking = false
                state.lastStopReason = "interrupted"
                state.activeTools.removeAll()
            }
        }

        // Check top-level type for user messages (rejections come as user type)
        if let type = json["type"] as? String, type == "user" {
            // User message might be a rejection - check content
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let itemType = item["type"] as? String, itemType == "tool_result",
                       let resultContent = item["content"] as? String,
                       resultContent.contains("interrupted") || resultContent.contains("rejected") {
                        debugLog("[JSONL DEBUG] Detected rejection/interruption in tool_result - marking as done")
                        state.isThinking = false
                        state.lastStopReason = "interrupted"
                        state.activeTools.removeAll()
                    }
                }
            }
        }
        if let todos = json["todos"] as? [[String: Any]] {
            debugLog("[JSONL DEBUG] todos (top-level): \(todos.count) items")
            for (i, todo) in todos.enumerated() {
                debugLog("[JSONL DEBUG]   todo[\(i)]: \(todo)")
            }
        }

        if let message = json["message"] as? [String: Any] {
            parseMessage(message)
        }
    }

    private func parseMessage(_ message: [String: Any]) {
        // DEBUG: Print all message-level fields
        debugLog("[JSONL DEBUG] --- MESSAGE ---")
        debugLog("[JSONL DEBUG] Message keys: \(message.keys.sorted().joined(separator: ", "))")

        if let model = message["model"] as? String {
            debugLog("[JSONL DEBUG] model: \(model)")
            state.model = model
        }
        if let id = message["id"] as? String {
            debugLog("[JSONL DEBUG] message.id: \(id)")
        }
        if let type = message["type"] as? String {
            debugLog("[JSONL DEBUG] message.type: \(type)")
        }
        if let stopReason = message["stop_reason"] as? String {
            debugLog("[JSONL DEBUG] stop_reason: \(stopReason)")
            state.lastStopReason = stopReason
            // When we get end_turn, mark thinking as done
            if stopReason == "end_turn" {
                state.isThinking = false
            }
        }
        if let stopSequence = message["stop_sequence"] {
            debugLog("[JSONL DEBUG] stop_sequence: \(stopSequence)")
        }

        if let role = message["role"] as? String {
            debugLog("[JSONL DEBUG] role: \(role)")
            if role == "user" || role == "assistant" {
                state.isThinking = true
                // Reset stop_reason when new activity starts
                state.lastStopReason = nil
            }
        }

        if let usage = message["usage"] as? [String: Any] {
            debugLog("[JSONL DEBUG] --- USAGE ---")
            debugLog("[JSONL DEBUG] usage keys: \(usage.keys.sorted().joined(separator: ", "))")
            for (key, value) in usage.sorted(by: { $0.key < $1.key }) {
                debugLog("[JSONL DEBUG] usage.\(key): \(value)")
            }
            state.tokenUsage.inputTokens = usage["input_tokens"] as? Int ?? state.tokenUsage.inputTokens
            state.tokenUsage.outputTokens = usage["output_tokens"] as? Int ?? state.tokenUsage.outputTokens
            state.tokenUsage.cacheReadInputTokens = usage["cache_read_input_tokens"] as? Int ?? state.tokenUsage.cacheReadInputTokens
            state.tokenUsage.cacheCreationInputTokens = usage["cache_creation_input_tokens"] as? Int ?? state.tokenUsage.cacheCreationInputTokens
        }

        if let content = message["content"] as? [[String: Any]] {
            debugLog("[JSONL DEBUG] --- CONTENT (array with \(content.count) items) ---")
            for (index, item) in content.enumerated() {
                if let type = item["type"] as? String {
                    debugLog("[JSONL DEBUG] content[\(index)].type: \(type)")
                    debugLog("[JSONL DEBUG] content[\(index)] keys: \(item.keys.sorted().joined(separator: ", "))")

                    switch type {
                    case "thinking":
                        // Only mark as thinking if no recent tools completed (first thinking)
                        // or if we have active tools running
                        // If we have recent tools but no active tools, it's just final output
                        if state.activeTools.isEmpty && !state.recentTools.isEmpty {
                            debugLog("[JSONL DEBUG] Post-tool thinking - session completing")
                            state.isThinking = false
                        } else {
                            state.isThinking = true
                        }
                        if let thinking = item["thinking"] as? String {
                            debugLog("[JSONL DEBUG] THINKING BLOCK: \(thinking.prefix(200))...")
                        }

                    case "text":
                        if let text = item["text"] as? String {
                            debugLog("[JSONL DEBUG] text preview: \(text.prefix(150))...")
                            let preview = text.components(separatedBy: .newlines).first ?? text
                            state.lastMessage = String(preview.prefix(100))
                            state.lastMessageTime = Date()

                            // Text output after tools = final response phase
                            if state.activeTools.isEmpty && !state.recentTools.isEmpty {
                                state.isThinking = false
                            }

                            // Detect interruption/rejection - means task is done
                            if text.contains("[Request interrupted by user") {
                                debugLog("[JSONL DEBUG] Detected user interruption - marking as done")
                                state.isThinking = false
                                state.lastStopReason = "interrupted"
                                state.activeTools.removeAll()
                                state.needsPermission = false
                                state.pendingPermissionTool = nil
                                pendingToolChecks.removeAll()
                                // Cancel timers - session is done
                                toolIdleTimer?.invalidate()
                                toolIdleTimer = nil
                                // Force UI update
                                objectWillChange.send()
                            }
                        }

                    case "tool_use":
                        // Tool use means thinking is done, now acting
                        state.isThinking = false
                        // Reset tool idle timer - new tool activity detected
                        resetToolIdleTimer()

                        if let toolId = item["id"] as? String,
                           let toolName = item["name"] as? String {
                            debugLog("[JSONL DEBUG] tool_use.id: \(toolId)")
                            debugLog("[JSONL DEBUG] tool_use.name: \(toolName)")

                            var toolDescription: String?
                            var toolTimeout: Int?

                            if let input = item["input"] as? [String: Any] {
                                debugLog("[JSONL DEBUG] tool_use.input keys: \(input.keys.sorted().joined(separator: ", "))")
                                for (key, value) in input.sorted(by: { $0.key < $1.key }) {
                                    let valueStr = "\(value)"
                                    debugLog("[JSONL DEBUG] tool_use.input.\(key): \(valueStr.prefix(100))")
                                }

                                // Extract description and timeout
                                toolDescription = input["description"] as? String
                                toolTimeout = input["timeout"] as? Int
                            }

                            // Parse TodoWrite tool to extract todos
                            if toolName == "TodoWrite",
                               let input = item["input"] as? [String: Any],
                               let todos = input["todos"] as? [[String: Any]] {
                                parseTodos(todos)
                            }

                            var tool = ClaudeToolExecution(
                                id: toolId,
                                toolName: toolName,
                                argument: extractToolArgument(from: item["input"]),
                                startTime: Date()
                            )
                            tool.description = toolDescription
                            tool.timeout = toolTimeout

                            if !state.activeTools.contains(where: { $0.id == toolId }) {
                                state.activeTools.append(tool)
                                startPermissionCheck(toolId: toolId, toolName: toolName)
                            }
                        }

                    case "tool_result":
                        debugLog("[JSONL DEBUG] tool_result.tool_use_id: \(item["tool_use_id"] ?? "nil")")
                        if let isError = item["is_error"] as? Bool {
                            debugLog("[JSONL DEBUG] tool_result.is_error: \(isError)")
                        }
                        if let content = item["content"] as? String {
                            debugLog("[JSONL DEBUG] tool_result.content preview: \(content.prefix(150))...")
                        }

                    default:
                        debugLog("[JSONL DEBUG] Unknown content type: \(type)")
                        for (key, value) in item {
                            debugLog("[JSONL DEBUG]   \(key): \(value)")
                        }
                    }
                }
            }
        }

        if let role = message["role"] as? String, role == "user",
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let type = item["type"] as? String, type == "tool_result",
                   let toolUseId = item["tool_use_id"] as? String {
                    clearPermissionCheck(toolId: toolUseId)

                    if let index = state.activeTools.firstIndex(where: { $0.id == toolUseId }) {
                        var tool = state.activeTools.remove(at: index)
                        tool.endTime = Date()
                        // Attach current token usage to the completed tool
                        tool.inputTokens = state.tokenUsage.inputTokens
                        tool.outputTokens = state.tokenUsage.outputTokens
                        tool.cacheReadTokens = state.tokenUsage.cacheReadInputTokens
                        tool.cacheWriteTokens = state.tokenUsage.cacheCreationInputTokens
                        state.recentTools.insert(tool, at: 0)
                        if state.recentTools.count > 10 {
                            state.recentTools.removeLast()
                        }
                    }

                    state.isThinking = true
                }
            }
        }
    }

    private func extractToolArgument(from input: Any?) -> String? {
        guard let input = input as? [String: Any] else { return nil }

        if let pattern = input["pattern"] as? String { return pattern }
        if let command = input["command"] as? String { return String(command.prefix(50)) }
        if let filePath = input["file_path"] as? String { return URL(fileURLWithPath: filePath).lastPathComponent }
        if let query = input["query"] as? String { return String(query.prefix(50)) }
        if let prompt = input["prompt"] as? String { return String(prompt.prefix(50)) }

        return nil
    }

    private func parseTodos(_ todosArray: [[String: Any]]) {
        var newTodos: [ClaudeTodoItem] = []

        for todoDict in todosArray {
            guard let content = todoDict["content"] as? String,
                  let statusStr = todoDict["status"] as? String else {
                continue
            }

            let status: ClaudeTodoItem.TodoStatus
            switch statusStr {
            case "pending":
                status = .pending
            case "in_progress":
                status = .inProgress
            case "completed":
                status = .completed
            default:
                status = .pending
            }

            newTodos.append(ClaudeTodoItem(content: content, status: status))
        }

        state.todos = newTodos
    }

    // MARK: - Permission Detection

    private func startPermissionCheck(toolId: String, toolName: String) {
        guard !isLoadingHistory else { return }

        pendingToolChecks[toolId] = Date()

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckDelay, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPendingPermissions()
            }
        }
    }

    private func clearPermissionCheck(toolId: String) {
        pendingToolChecks.removeValue(forKey: toolId)

        if state.needsPermission {
            if pendingToolChecks.isEmpty {
                state.needsPermission = false
                state.pendingPermissionTool = nil
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
            } else {
                checkPendingPermissions()
            }
        }

        if pendingToolChecks.isEmpty {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    private func checkPendingPermissions() {
        let now = Date()

        for (toolId, startTime) in pendingToolChecks {
            let elapsed = now.timeIntervalSince(startTime)
            if elapsed >= permissionCheckDelay {
                if let tool = state.activeTools.first(where: { $0.id == toolId }) {
                    state.needsPermission = true
                    state.pendingPermissionTool = tool.toolName
                    return
                } else {
                    state.needsPermission = true
                    state.pendingPermissionTool = "Tool"
                    return
                }
            }
        }
    }

    // MARK: - Daily Stats

    func loadDailyStats() {
        let statsFile = claudeDir.appendingPathComponent("stats-cache.json")

        guard FileManager.default.fileExists(atPath: statsFile.path),
              let data = FileManager.default.contents(atPath: statsFile.path) else {
            return
        }

        do {
            let cache = try JSONDecoder().decode(ClaudeStatsCache.self, from: data)
            let today = Self.dateFormatter.string(from: Date())

            var stats = ClaudeDailyStats()

            let sortedActivity = cache.dailyActivity?.sorted { $0.date > $1.date }
            if let todayActivity = sortedActivity?.first(where: { $0.date == today }) {
                stats.date = today
                stats.messageCount = todayActivity.messageCount ?? 0
                stats.toolCallCount = todayActivity.toolCallCount ?? 0
                stats.sessionCount = todayActivity.sessionCount ?? 0
            } else if let latestActivity = sortedActivity?.first {
                stats.date = latestActivity.date
                stats.messageCount = latestActivity.messageCount ?? 0
                stats.toolCallCount = latestActivity.toolCallCount ?? 0
                stats.sessionCount = latestActivity.sessionCount ?? 0
            }

            let sortedTokens = cache.dailyModelTokens?.sorted { $0.date > $1.date }
            let targetDate = stats.date.isEmpty ? today : stats.date
            if let dayTokens = sortedTokens?.first(where: { $0.date == targetDate }),
               let tokensByModel = dayTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
            } else if let latestTokens = sortedTokens?.first,
                      let tokensByModel = latestTokens.tokensByModel {
                stats.tokensUsed = tokensByModel.values.reduce(0, +)
                if stats.date.isEmpty {
                    stats.date = latestTokens.date
                }
            }

            if stats != dailyStats {
                dailyStats = stats
            }

        } catch {
            debugLog("[ClaudeCode] Error parsing stats-cache.json: \(error)")
        }
    }
}
