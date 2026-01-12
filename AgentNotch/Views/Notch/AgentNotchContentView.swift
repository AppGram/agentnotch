import SwiftUI

struct AgentNotchContentView: View {
    @EnvironmentObject var telemetryCoordinator: TelemetryCoordinator
    @StateObject private var notchVM = NotchViewModel()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var claudeCodeManager = ClaudeCodeManager.shared
    @StateObject private var codexManager = CodexManager.shared
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var sessionStart = Date()
    @State private var showActivityGlow = false
    @State private var glowTask: Task<Void, Never>?
    @State private var clearTask: Task<Void, Never>?
    @State private var visibleToolCalls: [ToolCall] = []
    @State private var showStartupGlow = false
    @State private var startupGlowTask: Task<Void, Never>?
    @State private var showErrorGlow = false
    @State private var errorGlowTask: Task<Void, Never>?
    @State private var showCompletionNotice = false
    @State private var showPermissionNotice = false
    @State private var permissionToolName: String?
    @State private var completionNoticeTask: Task<Void, Never>?
    @State private var completionDebounceTask: Task<Void, Never>?
    @State private var lastCompletionId: UUID?
    @State private var completionToolCall: ToolCall?
    @State private var hadActiveToolCalls = false
    @State private var memeAutoOpenTask: Task<Void, Never>?
    @State private var memeGraceTask: Task<Void, Never>?
    @State private var isMemeGraceActive = false
    @State private var toolCallUpdateTask: Task<Void, Never>?

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let startupGlowColor = Color(red: 0.55, green: 0.8, blue: 0.9)
    private let startupBrightColor = Color(red: 0.75, green: 0.9, blue: 1.0)
    private let errorGlowColor = Color(red: 0.9, green: 0.2, blue: 0.2)
    private let errorBrightColor = Color(red: 1.0, green: 0.3, blue: 0.3)
    private let codexGlowColor = Color(red: 0.1, green: 0.3, blue: 0.7)
    private let codexBrightColor = Color(red: 0.2, green: 0.45, blue: 0.9)

    /// Show glow when there's recent activity (event within last 2 seconds)
    private var hasRecentActivity: Bool {
        guard let lastCall = visibleToolCalls.first else { return false }
        let elapsed = Date().timeIntervalSince(lastCall.endTime ?? lastCall.startTime)
        return elapsed < 2.0 || lastCall.isActive
    }

    private var isExpanded: Bool {
        notchVM.notchState == .open || notchVM.notchState == .peeking
    }

    private var recentTokenTotal: Int {
        if telemetryCoordinator.sessionTokenTotal > 0 {
            return telemetryCoordinator.sessionTokenTotal
        }
        return visibleToolCalls.compactMap { $0.tokenCount }.reduce(0, +)
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    /// Calculate the content width (includes wings + center notch area)
    private var closedContentWidth: CGFloat {
        notchVM.closedNotchSize.width + 160  // wings extend 80px on each side
    }

    private var activityGlowSource: TelemetrySource {
        // Only use a source if it's visible in settings
        if let firstSource = visibleToolCalls.first?.source {
            return firstSource
        }
        // Fallback to telemetry source only if that source is visible
        let source = telemetryCoordinator.telemetrySource
        return isSourceVisible(source) ? source : .claudeCode
    }

    private var activityGlowColor: Color {
        switch activityGlowSource {
        case .codex:
            return Color(red: 0.1, green: 0.3, blue: 0.7)
        case .claudeCode, .unknown:
            return Color(red: 0.9, green: 0.4, blue: 0.1)
        }
    }

    private var activityBrightColor: Color {
        switch activityGlowSource {
        case .codex:
            return Color(red: 0.2, green: 0.45, blue: 0.9)
        case .claudeCode, .unknown:
            return Color(red: 1.0, green: 0.55, blue: 0.2)
        }
    }

    private var hasActiveToolCall: Bool {
        visibleToolCalls.first?.isActive == true
    }

    /// Check if agent is active for a source that's visible in settings
    private var isAgentActiveForVisibleSource: Bool {
        guard telemetryCoordinator.isAgentActive else { return false }
        return isSourceVisible(telemetryCoordinator.telemetrySource)
    }

    private var memeVideoURL: URL? {
        if let bundleURL = Bundle.main.url(forResource: "videoplayback", withExtension: "mp4") {
            return bundleURL
        }
        return URL(string: settings.memeVideoURL)
    }

    private var shouldShowMemeVideo: Bool {
        settings.showMemeVideo && memeVideoURL != nil && (hasActiveToolCall || isMemeGraceActive)
    }

    /// Determines if Claude Code has real activity (not just grace period)
    private var claudeHasRealActivity: Bool {
        !claudeCodeManager.state.activeTools.isEmpty
            || claudeCodeManager.state.isThinking
            || claudeCodeManager.sessionStates.values.contains { !$0.activeTools.isEmpty || $0.isThinking }
    }

    /// Determines if Codex has real activity (not just grace period)
    private var codexHasRealActivity: Bool {
        !codexManager.state.activeTools.isEmpty
            || codexManager.state.isThinking
            || codexManager.sessionStates.values.contains { !$0.activeTools.isEmpty || $0.isThinking }
    }

    /// Determines which glow color to use based on active source
    private var currentGlowColor: Color {
        if claudeHasRealActivity {
            return activityGlowColor
        } else if codexHasRealActivity {
            return codexGlowColor
        } else if codexManager.hasAnySessionActivity && !claudeCodeManager.hasAnySessionActivity {
            return codexGlowColor
        }
        return activityGlowColor
    }

    /// Determines which bright color to use based on active source
    private var currentBrightColor: Color {
        if claudeHasRealActivity {
            return activityBrightColor
        } else if codexHasRealActivity {
            return codexBrightColor
        } else if codexManager.hasAnySessionActivity && !claudeCodeManager.hasAnySessionActivity {
            return codexBrightColor
        }
        return activityBrightColor
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
                .padding(
                    .horizontal,
                    isExpanded
                        ? cornerRadiusInsets.opened.top
                        : cornerRadiusInsets.closed.bottom
                )
                .padding([.horizontal, .bottom], isExpanded ? 12 : 0)
                .background(Color.black)
                .mask(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .contentShape(
                    NotchShape(
                        topCornerRadius: topCornerRadius,
                        bottomCornerRadius: bottomCornerRadius
                    )
                )
                .onHover { hovering in
                    handleHover(hovering)
                }
                .onTapGesture {
                    notchVM.toggle()
                }
                .overlay {
                    if showStartupGlow && notchVM.notchState == .closed {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: startupGlowColor,
                            brightColor: startupBrightColor
                        )
                    } else if showErrorGlow && notchVM.notchState == .closed {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: errorGlowColor,
                            brightColor: errorBrightColor
                        )
                    } else if (showActivityGlow || (isAgentActiveForVisibleSource && hasActiveToolCall) || claudeCodeManager.hasAnySessionActivity || codexManager.hasAnySessionActivity)
                                && notchVM.notchState == .closed
                                && !showCompletionNotice {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: currentGlowColor,
                            brightColor: currentBrightColor
                        )
                    }
                }
                .onChange(of: telemetryCoordinator.recentToolCalls.count) { _, _ in
                    handleToolCallUpdate()
                }
                .onChange(of: telemetryCoordinator.recentToolCalls.first?.id) { _, _ in
                    handleToolCallUpdate()
                }
                .onChange(of: settings.showSourceCodex) { _, _ in
                    handleToolCallUpdate()
                }
                .onChange(of: settings.showSourceClaudeCode) { _, _ in
                    handleToolCallUpdate()
                }
                .onChange(of: settings.showSourceUnknown) { _, _ in
                    handleToolCallUpdate()
                }
                .onChange(of: telemetryCoordinator.isAgentActive) { wasActive, isActive in
                    if wasActive && !isActive {
                        // Only handle completion if the source that finished is visible in settings
                        guard isSourceVisible(telemetryCoordinator.telemetrySource) else { return }
                        // Agent just finished - trigger completion notice and stop glows
                        stopAllGlows()
                        handleAgentCompletion()
                    }
                }
                .onChange(of: claudeCodeManager.sessionsNeedingPermission.count) { oldCount, newCount in
                    if newCount > oldCount {
                        // New permission request - show dropdown
                        triggerPermissionNotice()
                    } else if newCount == 0 {
                        // Permission granted/denied - hide notice
                        showPermissionNotice = false
                    }
                }
                .onChange(of: hasActiveToolCall) { _, isActive in
                    updateMemeAutoOpen(isActive: isActive)
                    updateMemeGrace(isActive: isActive)
                }
                .onChange(of: settings.showMemeVideo) { _, isEnabled in
                    if isEnabled {
                        updateMemeAutoOpen(isActive: hasActiveToolCall)
                        updateMemeGrace(isActive: hasActiveToolCall)
                    } else {
                        memeAutoOpenTask?.cancel()
                        memeGraceTask?.cancel()
                        isMemeGraceActive = false
                    }
                }
                .shadow(
                    color: (isExpanded || isHovering) ? .black.opacity(0.6) : .clear,
                    radius: 8
                )
                .animation(animationSpring, value: notchVM.notchState)
                .animation(animationSpring, value: notchVM.notchSize)
        }
        .padding(.bottom, isExpanded ? 8 : closedNotchGlowPadding)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .preferredColorScheme(.dark)
        .onAppear {
            triggerStartupGlow()
            // Start Claude Usage quota tracking if enabled
            if settings.enableClaudeUsage && ClaudeUsageManager.shared.isConfigured {
                ClaudeUsageManager.shared.startRefreshing()
            }
        }
        .onDisappear {
            startupGlowTask?.cancel()
            memeAutoOpenTask?.cancel()
            memeGraceTask?.cancel()
            toolCallUpdateTask?.cancel()
        }
    }

    @ViewBuilder
    private var notchBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            notchHeader
                .frame(height: notchVM.closedNotchSize.height)

            // Expanded content
            if notchVM.notchState == .open {
                expandedContent
                    .frame(height: notchVM.notchSize.height - notchVM.closedNotchSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            } else if notchVM.notchState == .peeking {
                peekContent
                    .frame(height: notchVM.notchSize.height - notchVM.closedNotchSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var notchHeader: some View {
        if notchVM.notchState == .closed {
            closedHeader
        } else if notchVM.notchState == .peeking {
            peekHeader
        } else {
            openHeader
        }
    }

    @ViewBuilder
    private var closedHeader: some View {
        // Claude Code active tool (from JSONL parsing) - check all sessions
        let claudeActiveTool = claudeCodeManager.state.activeTools.first
            ?? claudeCodeManager.sessionStates.values.compactMap { $0.activeTools.first }.first
        // Recent completed Claude tool (within last 5 seconds)
        let recentClaudeTool: ClaudeToolExecution? = {
            if let recent = claudeCodeManager.state.recentTools.first,
               let endTime = recent.endTime,
               Date().timeIntervalSince(endTime) < 5.0 {
                return recent
            }
            return nil
        }()
        let isClaudeActive = claudeCodeManager.hasAnySessionActivity
        let isClaudeSessionIdle = claudeCodeManager.state.isSessionComplete && !isClaudeActive

        // Codex active tool (from JSONL parsing)
        let codexActiveTool = codexManager.state.activeTools.first
            ?? codexManager.sessionStates.values.compactMap { $0.activeTools.first }.first
        // Recent completed Codex tool (within last 5 seconds)
        let recentCodexTool: CodexToolExecution? = {
            if let recent = codexManager.state.recentTools.first,
               let endTime = recent.endTime,
               Date().timeIntervalSince(endTime) < 5.0 {
                return recent
            }
            return nil
        }()
        let isCodexActive = codexManager.hasAnySessionActivity

        // Determine which source is active (prefer Codex if both, since it's newer)
        let activeSource: TelemetrySource = isCodexActive ? .codex : (isClaudeActive ? .claudeCode : .unknown)
        let isSessionIdle = isClaudeSessionIdle && !isCodexActive

        // Check if we have sessions (for context indicator)
        let hasClaudeSessions = settings.showSessionDots
            && settings.enableClaudeCodeJSONL
            && !claudeCodeManager.availableSessions.isEmpty
        let hasCodexSessions = settings.showSessionDots
            && settings.enableCodexJSONL
            && !codexManager.availableSessions.isEmpty
        let hasSessions = hasClaudeSessions || hasCodexSessions
        let hasActiveSessionDots = hasSessions
            && (claudeCodeManager.sessionStates.values.contains { $0.isActive || $0.needsPermission }
                || codexManager.sessionStates.values.contains { $0.isActive })
        let hasPermissionNeeded = settings.showPermissionIndicator && !claudeCodeManager.sessionsNeedingPermission.isEmpty

        // Determine what tool to show (prefer active Codex, then active Claude, then recent)
        let currentClaudeTool: ClaudeToolExecution? = claudeActiveTool ?? recentClaudeTool
        let currentCodexTool: CodexToolExecution? = codexActiveTool ?? recentCodexTool
        let isThinking = (isClaudeActive && currentClaudeTool == nil) || (isCodexActive && currentCodexTool == nil)

        // Get current tool name (prefer Codex if active, otherwise Claude)
        let currentToolName: String? = {
            if let codexTool = currentCodexTool, isCodexActive || codexActiveTool != nil {
                return codexTool.toolName
            }
            return currentClaudeTool?.toolName
        }()
        let hasCurrentTool = currentToolName != nil

        // Determine what to show in left wing (show sessions indicator even when idle for context)
        let showLeftWing = hasCurrentTool || isThinking || hasSessions || isSessionIdle

        // Calculate wing widths (tool name up to 24 chars)
        let toolNameWidth: CGFloat = currentToolName.map { CGFloat(min($0.count, 24)) * 8 } ?? 0
        let thinkingWidth: CGFloat = 90 // Width for "Thinking..." text
        let leftWingWidth: CGFloat = showLeftWing
            ? (hasCurrentTool ? 51 + toolNameWidth : (isThinking ? 51 + thinkingWidth : (hasSessions ? 70 : 60)))
            : 0

        let rightWingWidth: CGFloat = (hasCurrentTool || isThinking) ? 120
            : (hasPermissionNeeded ? 100 : 0)

        // If nothing to show, just return the notch width
        let hasAnyContent = showLeftWing || rightWingWidth > 0
        let totalWidth = notchVM.closedNotchSize.width + leftWingWidth + rightWingWidth

        if !hasAnyContent {
            // Empty state - just the notch, no wings
            Spacer()
                .frame(width: notchVM.closedNotchSize.width)
        } else {
            HStack(spacing: 0) {
                // Left wing
                if showLeftWing {
                    HStack(spacing: 6) {
                        if hasSessions && !hasCurrentTool && !isThinking && !isSessionIdle {
                            // Show session count indicator when idle
                            let sessionCount = claudeCodeManager.availableSessions.count + codexManager.availableSessions.count
                            let hasActivity = hasActiveSessionDots
                            let indicatorColor = hasActivity ? (isCodexActive ? codexGlowColor : activityGlowColor) : Color.gray
                            Circle()
                                .fill(indicatorColor)
                                .frame(width: 6, height: 6)
                                .opacity(hasActivity ? 1.0 : 0.5)
                            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(hasActivity ? .white.opacity(0.8) : .gray)
                        } else if isSessionIdle {
                            // Session complete indicator
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.green.opacity(0.5), radius: 2)
                            Text("Done")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green.opacity(0.9))
                        } else if hasCurrentTool || isThinking {
                            // Source-specific indicator color
                            let indicatorColor = activeSource == .codex ? codexGlowColor : activityGlowColor
                            let isActive = isCodexActive || isClaudeActive
                            Circle()
                                .fill(indicatorColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: indicatorColor.opacity(isActive ? 0.6 : 0.3), radius: isActive ? 3 : 1)

                            if let toolName = currentToolName {
                                Text(toolName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            } else if isThinking {
                                Text("Thinking...")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                    .frame(width: leftWingWidth, alignment: .leading)
                    .padding(.leading, 8)
                }

                Spacer()

                // Right wing - tool info or status
                if rightWingWidth > 0 {
                    Group {
                        if let codexTool = currentCodexTool, isCodexActive || codexActiveTool != nil {
                            // Codex tool info
                            HStack(spacing: 4) {
                                if codexTool.isRunning {
                                    ProgressView()
                                        .scaleEffect(0.3)
                                        .frame(width: 8, height: 8)
                                    if let arg = codexTool.argument {
                                        Text(arg.prefix(20))
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                } else {
                                    // Show session tokens for Codex (no per-tool tokens)
                                    let tokenUsage = codexManager.state.tokenUsage
                                    if tokenUsage.inputTokens > 0 {
                                        HStack(spacing: 1) {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(.green.opacity(0.8))
                                            Text(formatTokenCount(tokenUsage.inputTokens))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    if tokenUsage.outputTokens > 0 {
                                        HStack(spacing: 1) {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(.blue.opacity(0.8))
                                            Text(formatTokenCount(tokenUsage.outputTokens))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    Text(codexTool.formattedDuration)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        } else if let claudeTool = currentClaudeTool {
                            // Claude Code tool info
                            HStack(spacing: 4) {
                                if claudeTool.isRunning {
                                    ProgressView()
                                        .scaleEffect(0.3)
                                        .frame(width: 8, height: 8)
                                    if let desc = claudeTool.description {
                                        Text(desc.prefix(20))
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                } else {
                                    if let input = claudeTool.inputTokens, input > 0 {
                                        HStack(spacing: 1) {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(.green.opacity(0.8))
                                            Text(formatTokenCount(input))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    if let output = claudeTool.outputTokens, output > 0 {
                                        HStack(spacing: 1) {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: 6, weight: .bold))
                                                .foregroundColor(.blue.opacity(0.8))
                                            Text(formatTokenCount(output))
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    Text(claudeTool.formattedDuration)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        } else if isThinking {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.3)
                                    .frame(width: 8, height: 8)
                                let modelName = isCodexActive
                                    ? extractCodexModelName(codexManager.state.model)
                                    : extractModelName(claudeCodeManager.state.model)
                                if let modelName {
                                    Text(modelName)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        } else if hasPermissionNeeded {
                            HStack(spacing: 4) {
                                PermissionNeededIndicatorCompact()
                                Text("Needs OK")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .frame(width: rightWingWidth, alignment: .trailing)
                    .padding(.trailing, 8)
                }
            }
            .frame(width: totalWidth)
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    /// Extract model name from full model ID (e.g., "opus" from "claude-opus-4-5-20251101")
    private func extractModelName(_ modelId: String) -> String? {
        let parts = modelId.lowercased().split(separator: "-")
        // Look for known model names
        if parts.contains("opus") { return "Opus" }
        if parts.contains("sonnet") { return "Sonnet" }
        if parts.contains("haiku") { return "Haiku" }
        // Fallback: return second part if available (usually the model name)
        if parts.count > 1 {
            return String(parts[1]).capitalized
        }
        return nil
    }

    /// Extract model name from Codex model ID (e.g., "GPT-4" from "gpt-4-turbo")
    private func extractCodexModelName(_ modelId: String) -> String? {
        let id = modelId.lowercased()
        if id.contains("o3") { return "o3" }
        if id.contains("o1") { return "o1" }
        if id.contains("gpt-4") { return "GPT-4" }
        if id.contains("gpt-3") { return "GPT-3" }
        if id.contains("codex") { return "Codex" }
        // Fallback: first part
        let parts = id.split(separator: "-")
        if let first = parts.first {
            return String(first).uppercased()
        }
        return nil
    }

    @ViewBuilder
    private var openHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AgentNotch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    TelemetryStatusIndicatorView(state: telemetryCoordinator.state)
                    Text(telemetryCoordinator.state.displayText)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if telemetryCoordinator.state == .running {
                    NotchControlButton(systemName: "stop.fill", tint: .red) {
                        Task { await telemetryCoordinator.stop() }
                    }
                } else if telemetryCoordinator.state == .stopped {
                    NotchControlButton(systemName: "play.fill", tint: .green) {
                        Task { await telemetryCoordinator.start() }
                    }
                }

                NotchControlButton(systemName: "gearshape") {
                    openSettings()
                }

                NotchControlButton(systemName: "power", tint: .red) {
                    NSApp.terminate(nil)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12))
            )
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 6) {
            if shouldShowMemeVideo, let memeVideoURL {
                NotchSection(title: "Meme Mode") {
                    MemeVideoPlayerView(url: memeVideoURL)
                }
            }

            if !shouldShowMemeVideo {
                // Show todo list if enabled and has items
                if settings.showTodoList && !claudeCodeManager.state.todos.isEmpty {
                    NotchSection(title: "Current Tasks") {
                        TodoListView(todos: claudeCodeManager.state.todos, maxItems: 4)
                    }
                }

                // Determine which tools to show (prefer Codex if active)
                let codexTools = codexManager.state.activeTools + codexManager.state.recentTools
                let claudeTools = claudeCodeManager.state.activeTools + claudeCodeManager.state.recentTools
                let isCodexActive = codexManager.hasAnySessionActivity

                if settings.toolDisplayMode == "singular" {
                    // Singular mode: show one detailed event
                    if isCodexActive, let currentTool = codexTools.first {
                        NotchSection(title: currentTool.isRunning ? "Active Tool" : "Last Tool") {
                            SingularCodexToolDetailView(tool: currentTool, tokenUsage: codexManager.state.tokenUsage)
                        }
                    } else if let currentTool = claudeTools.first {
                        NotchSection(title: currentTool.isRunning ? "Active Tool" : "Last Tool") {
                            SingularToolDetailView(tool: currentTool, tokenUsage: claudeCodeManager.state.tokenUsage)
                        }
                    } else if let lastCall = visibleToolCalls.first {
                        NotchSection(title: lastCall.isActive ? "Active Tool" : "Last Tool") {
                            SingularTelemetryToolView(toolCall: lastCall)
                        }
                    }
                } else {
                    // List mode: show recent events list
                    if isCodexActive && !codexTools.isEmpty {
                        NotchSection(title: "Recent Tools (Codex)") {
                            CodexToolListView(tools: codexTools, maxItems: 4)
                        }
                    } else if !claudeTools.isEmpty {
                        NotchSection(title: "Recent Tools") {
                            ClaudeToolListView(tools: claudeTools, maxItems: 4)
                        }
                    } else {
                        NotchSection(title: "Recent Tools") {
                            ToolCallListView(toolCalls: Array(visibleToolCalls.prefix(4)))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Permission badge above footer
            if settings.showPermissionIndicator && !claudeCodeManager.sessionsNeedingPermission.isEmpty {
                PermissionNeededBadge(toolName: claudeCodeManager.state.pendingPermissionTool)
                    .onTapGesture {
                        claudeCodeManager.focusIDE()
                    }
            }

            // Context progress bar (with integrated API usage badges)
            if settings.showContextProgress {
                ContextProgressBar(
                    tokenUsage: claudeCodeManager.state.tokenUsage,
                    contextLimit: settings.contextTokenLimit,
                    showApiUsage: settings.enableClaudeUsage
                )
            }

            // Use Claude Code tokens when JSONL is source, otherwise use telemetry
            let claudeTokens = claudeCodeManager.state.tokenUsage
            let hasClaudeTokens = claudeTokens.inputTokens > 0 || claudeTokens.outputTokens > 0
            let displayTokenTotal = hasClaudeTokens ? (claudeTokens.inputTokens + claudeTokens.outputTokens) : recentTokenTotal
            let displayCacheTokens = hasClaudeTokens ? claudeTokens.cacheReadInputTokens : telemetryCoordinator.sessionCacheTokens
            let displayCacheWriteTokens = hasClaudeTokens ? claudeTokens.cacheCreationInputTokens : 0

            NotchFooterView(
                sessionDuration: Date().timeIntervalSince(sessionStart),
                tokenTotal: displayTokenTotal,
                cacheReadTokens: displayCacheTokens,
                cacheWriteTokens: displayCacheWriteTokens,
                showTokenCount: settings.showNotchTokenCount,
                gitBranch: claudeCodeManager.state.gitBranch
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var peekHeader: some View {
        Group {
            if showCompletionNotice, let toolCall = completionToolCall {
                completionHeader(toolCall: toolCall)
            } else {
                HStack(spacing: 10) {
                    TelemetryStatusIndicatorView(state: telemetryCoordinator.state)
                    Text("Telemetry Active")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private var peekContent: some View {
        Group {
            if showPermissionNotice {
                permissionContent
            } else if showCompletionNotice, let toolCall = completionToolCall {
                completionContent(toolCall: toolCall)
            } else {
                VStack(spacing: 8) {
                    if settings.showNotchTokenCount, recentTokenTotal > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))

                            Text("\(recentTokenTotal) t")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
    }

    private var permissionContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Pulsing orange indicator
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
                    .shadow(color: .orange.opacity(0.6), radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    if let toolName = permissionToolName {
                        Text("Claude wants to run: \(toolName)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                Text("Check Terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .onTapGesture {
            claudeCodeManager.focusIDE()
        }
    }

    private struct NotchSection<Content: View>: View {
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
                        .foregroundColor(.white.opacity(0.55))
                }

                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }
    }

    private struct NotchControlButton: View {
        let systemName: String
        var tint: Color? = nil
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(tint ?? .white.opacity(0.75))
            .padding(6)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.08))
            )
        }
    }

    private struct NotchPill: View {
        let text: String
        var mono: Bool = false

        var body: some View {
            Text(text)
                .font(.system(size: 9, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }

    private struct NotchFooterView: View {
        let sessionDuration: TimeInterval
        let tokenTotal: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
        let showTokenCount: Bool
        let gitBranch: String?

        var body: some View {
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(formatDuration(sessionDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    // Git branch badge
                    if let branch = gitBranch, !branch.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.purple.opacity(0.8))
                            Text(branch)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.purple.opacity(0.9))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                    }

                    Spacer()

                    if showTokenCount {
                        // Regular tokens (input + output)
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Text(tokenTotal > 0 ? formatTokens(tokenTotal) : "-")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))

                        // Cache read tokens (green - savings)
                        if cacheReadTokens > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.green.opacity(0.8))
                                Text(formatTokens(cacheReadTokens))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.9))
                            }
                        }

                        // Cache write tokens (yellow - creation)
                        if cacheWriteTokens > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.yellow.opacity(0.8))
                                Text(formatTokens(cacheWriteTokens))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.yellow.opacity(0.9))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
        }

        private func formatTokens(_ count: Int) -> String {
            if count >= 1000 {
                return String(format: "%.1fk", Double(count) / 1000.0)
            }
            return "\(count)"
        }

        private func formatDuration(_ duration: TimeInterval) -> String {
            let totalSeconds = Int(duration)
            if totalSeconds < 60 {
                return "\(totalSeconds)s"
            } else if totalSeconds < 3600 {
                let minutes = totalSeconds / 60
                let seconds = totalSeconds % 60
                return String(format: "%dm %02ds", minutes, seconds)
            } else {
                let hours = totalSeconds / 3600
                let minutes = (totalSeconds % 3600) / 60
                return String(format: "%dh %02dm", hours, minutes)
            }
        }
    }

    // MARK: - Context Progress Bar

    private struct ContextProgressBar: View {
        let tokenUsage: ClaudeTokenUsage
        let contextLimit: Int
        var showApiUsage: Bool = false

        private var totalTokens: Int {
            tokenUsage.inputTokens + tokenUsage.outputTokens + tokenUsage.cacheReadInputTokens
        }

        private var progress: Double {
            guard contextLimit > 0 else { return 0 }
            return min(1.0, Double(totalTokens) / Double(contextLimit))
        }

        private var progressColor: Color {
            if progress > 0.9 { return .red }
            if progress > 0.7 { return .orange }
            if progress > 0.5 { return .yellow }
            return .green
        }

        var body: some View {
            VStack(spacing: 4) {
                HStack {
                    Text("Context")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Text("\(formatTokens(totalTokens)) / \(formatTokens(contextLimit))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    // API Usage badges integrated inline
                    if showApiUsage {
                        InlineApiUsageBadges()
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))

                        // Progress fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor.opacity(0.8))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }

        private func formatTokens(_ count: Int) -> String {
            if count >= 1000 {
                return String(format: "%.1fk", Double(count) / 1000.0)
            }
            return "\(count)"
        }
    }

    // MARK: - Singular Tool Detail View (for Claude Code tools)

    private struct SingularToolDetailView: View {
        let tool: ClaudeToolExecution
        let tokenUsage: ClaudeTokenUsage

        private let claudeColor = Color(red: 1.0, green: 0.55, blue: 0.2)

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Tool name and status
                HStack(spacing: 8) {
                    Circle()
                        .fill(claudeColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: claudeColor.opacity(tool.isRunning ? 0.6 : 0.3), radius: tool.isRunning ? 4 : 2)

                    Text(tool.toolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if tool.isRunning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(tool.formattedDuration)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Description
                if let desc = tool.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Argument/filename
                if let arg = tool.argument, !arg.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(arg)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                // Token details
                HStack(spacing: 12) {
                    // Input tokens
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Input")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.green.opacity(0.8))
                            Text(formatTokens(tool.inputTokens ?? tokenUsage.inputTokens))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    // Output tokens
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.blue.opacity(0.8))
                            Text(formatTokens(tool.outputTokens ?? tokenUsage.outputTokens))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }

                    // Cache read
                    if (tool.cacheReadTokens ?? tokenUsage.cacheReadInputTokens) > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cache")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green.opacity(0.8))
                                Text(formatTokens(tool.cacheReadTokens ?? tokenUsage.cacheReadInputTokens))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Spacer()

                    // Timeout if present
                    if let timeout = tool.timeout {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Timeout")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(timeout / 1000)s")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }

        private func formatTokens(_ count: Int) -> String {
            if count >= 1000 {
                return String(format: "%.1fk", Double(count) / 1000.0)
            }
            return "\(count)"
        }
    }

    // MARK: - Singular Telemetry Tool View (fallback for non-Claude tools)

    private struct SingularTelemetryToolView: View {
        let toolCall: ToolCall

        private var sourceColor: Color {
            switch toolCall.source {
            case .codex:
                return Color(red: 0.2, green: 0.45, blue: 0.9)
            case .claudeCode:
                return Color(red: 1.0, green: 0.55, blue: 0.2)
            case .unknown:
                return Color.gray
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Tool name and status
                HStack(spacing: 8) {
                    Circle()
                        .fill(sourceColor)
                        .frame(width: 10, height: 10)

                    Text(toolCall.toolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if toolCall.isActive {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(toolCall.formattedDuration)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Result or status
                if !toolCall.isActive {
                    HStack(spacing: 4) {
                        Image(systemName: toolCall.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(toolCall.isSuccess ? .green : .red)
                        Text(toolCall.isSuccess ? "Completed" : "Failed")
                            .font(.system(size: 11))
                            .foregroundColor(toolCall.isSuccess ? .green : .red)
                    }
                }

                // Tokens if available
                if let tokens = toolCall.tokenCount, tokens > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("\(tokens) tokens")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Source badge
                HStack {
                    Spacer()
                    Text(toolCall.source.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(sourceColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            guard notchVM.notchState == .closed else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard notchVM.notchState == .closed, isHovering else { return }
                    notchVM.open()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        isHovering = false
                    }

                    if notchVM.notchState == .open {
                        notchVM.close()
                    }
                }
            }
        }
    }

    private func updateMemeAutoOpen(isActive: Bool) {
        memeAutoOpenTask?.cancel()
        guard settings.showMemeVideo, isActive else { return }
        memeAutoOpenTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard settings.showMemeVideo,
                      hasActiveToolCall,
                      notchVM.notchState == .closed else { return }
                notchVM.open()
            }
        }
    }

    private func updateMemeGrace(isActive: Bool) {
        memeGraceTask?.cancel()

        if isActive {
            isMemeGraceActive = true
            return
        }

        guard settings.showMemeVideo else {
            isMemeGraceActive = false
            return
        }

        isMemeGraceActive = true
        memeGraceTask = Task {
            let graceSeconds = max(0, settings.memeGraceSeconds)
            try? await Task.sleep(for: .seconds(graceSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !hasActiveToolCall {
                    isMemeGraceActive = false
                }
            }
        }
    }

    private func triggerActivityGlow() {
        // Show glow immediately (only if not already showing)
        if !showActivityGlow {
            showActivityGlow = true
        }

        // Cancel previous hide timer and restart
        // Glow will hide only after 4 seconds of NO new events AND no active tools
        glowTask?.cancel()
        glowTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Keep glow visible while any tool is still active
                let hasActiveTool = visibleToolCalls.contains { $0.isActive }
                guard !hasActiveTool else { return }
                withAnimation(.easeOut(duration: 0.5)) {
                    showActivityGlow = false
                }
            }
        }
    }

    private func triggerErrorGlow() {
        // Show error glow immediately
        showErrorGlow = true
        // Stop activity glow when showing error
        showActivityGlow = false
        glowTask?.cancel()

        // Cancel previous error hide timer and restart
        // Error glow hides after 5 seconds
        errorGlowTask?.cancel()
        errorGlowTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.5)) {
                    showErrorGlow = false
                }
            }
        }
    }

    private func stopAllGlows() {
        glowTask?.cancel()
        errorGlowTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            showActivityGlow = false
            showErrorGlow = false
        }
    }

    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task {
            // Clear after 30 seconds of inactivity
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    visibleToolCalls = []
                }
            }
        }
    }

    private func handleToolCallUpdate() {
        // Debounce rapid updates - coalesce multiple onChange calls into one
        toolCallUpdateTask?.cancel()
        toolCallUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                performToolCallUpdate()
            }
        }
    }

    private func performToolCallUpdate() {
        visibleToolCalls = telemetryCoordinator.recentToolCalls.filter { isSourceVisible($0.source) }

        // Check if the most recent completed tool call is an error
        if let lastCall = visibleToolCalls.first,
           !lastCall.isActive,
           !lastCall.isSuccess {
            triggerErrorGlow()
        } else {
            triggerActivityGlow()
        }

        scheduleClear()
        updateCompletionNoticeState()
    }

    private func updateCompletionNoticeState() {
        let hasActiveNow = visibleToolCalls.contains { $0.isActive }
        let lastCompleted = visibleToolCalls.first(where: { !$0.isActive })
        let isCompletionEvent = lastCompleted.map(isCompletionToolCall) ?? false

        if hasActiveNow {
            completionDebounceTask?.cancel()
        } else if isCompletionEvent {
            // Only show completion peek for actual "Complete" tool calls from telemetry,
            // not for every tool that finishes. JSONL tracking handles session completion separately.
            completionDebounceTask?.cancel()
            completionDebounceTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let stillIdle = !visibleToolCalls.contains { $0.isActive }
                guard stillIdle, let completed = lastCompleted else { return }
                if let endTime = completed.endTime, Date().timeIntervalSince(endTime) > 10 {
                    return
                }
                guard completed.id != lastCompletionId else { return }
                await MainActor.run {
                    showCompletionNotice = true
                    completionToolCall = completed
                    lastCompletionId = completed.id
                    stopActivityGlowForCompletion()
                    notchVM.peek(duration: 3.0)
                    completionNoticeTask?.cancel()
                    completionNoticeTask = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showCompletionNotice = false
                            }
                        }
                    }
                }
            }
        }

        hadActiveToolCalls = hasActiveNow
    }

    private func isCompletionToolCall(_ toolCall: ToolCall) -> Bool {
        let name = toolCall.toolName.lowercased()
        return name == "complete"
            || name == "response complete"
            || name == "output ready"
            || name == "response completed"
    }

    private func completionHeader(toolCall: ToolCall) -> some View {
        HStack(spacing: 10) {
            let isSuccess = toolCall.isSuccess
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSuccess ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(isSuccess ? "Task Complete" : "Task Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Source: \(toolCall.source.displayName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(sourceTint(for: toolCall.source))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func sourceTint(for source: TelemetrySource) -> Color {
        switch source {
        case .codex:
            return Color(red: 0.2, green: 0.45, blue: 0.9)
        case .claudeCode:
            return Color(red: 1.0, green: 0.55, blue: 0.2)
        case .unknown:
            return Color.white.opacity(0.65)
        }
    }

    private func completionContent(toolCall: ToolCall) -> some View {
        VStack(spacing: 8) {
            let summary = completionSummary(for: toolCall)
            Text(summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(toolCall.toolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                if settings.showNotchTokenCount, let tokens = toolCall.tokenCount {
                    NotchPill(text: "\(tokens) t")
                }

                NotchPill(text: toolCall.formattedDuration, mono: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func completionSummary(for toolCall: ToolCall) -> String {
        if let result = toolCall.result {
            switch result {
            case .success(let content):
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            case .failure(let error):
                let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        if isCompletionToolCall(toolCall) {
            return "Model finished response"
        }
        return "Finished \(toolCall.toolName)"
    }

    private func stopActivityGlowForCompletion() {
        glowTask?.cancel()
        showActivityGlow = false
    }

    private func triggerPermissionNotice() {
        // Get the tool name from the first session needing permission
        if let session = claudeCodeManager.sessionsNeedingPermission.first,
           let state = claudeCodeManager.sessionStates[session.id] {
            permissionToolName = state.pendingPermissionTool
        } else {
            permissionToolName = claudeCodeManager.state.pendingPermissionTool
        }

        showPermissionNotice = true
        notchVM.peek(duration: 5.0)

        // Auto-hide after duration
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                if showPermissionNotice {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showPermissionNotice = false
                    }
                }
            }
        }
    }

    private func triggerStartupGlow() {
        startupGlowTask?.cancel()
        showStartupGlow = true
        startupGlowTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showStartupGlow = false
                }
            }
        }
    }

    private func handleAgentCompletion() {
        // Refresh visible tool calls first
        visibleToolCalls = telemetryCoordinator.recentToolCalls.filter { isSourceVisible($0.source) }

        // Find the completion tool call that was just added
        guard let completeCall = visibleToolCalls.first(where: { $0.toolName == "Complete" }),
              completeCall.id != lastCompletionId else { return }

        showCompletionNotice = true
        completionToolCall = completeCall
        lastCompletionId = completeCall.id
        stopActivityGlowForCompletion()

        // Peek the notch to show completion
        notchVM.peek(duration: 3.0)

        // Hide completion notice after delay
        completionNoticeTask?.cancel()
        completionNoticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCompletionNotice = false
                }
            }
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow")), to: NSApp.delegate, from: nil)
    }

    private func isSourceVisible(_ source: TelemetrySource) -> Bool {
        switch source {
        case .codex:
            return settings.showSourceCodex
        case .claudeCode:
            return settings.showSourceClaudeCode
        case .unknown:
            return settings.showSourceUnknown
        }
    }
}

#Preview {
    AgentNotchContentView()
        .environmentObject(TelemetryCoordinator.shared)
        .frame(width: 600, height: 300)
        .background(Color.gray.opacity(0.3))
}
