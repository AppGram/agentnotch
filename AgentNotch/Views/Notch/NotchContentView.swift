import SwiftUI

struct NotchContentView: View {
    @EnvironmentObject var mcpCoordinator: MCPCoordinator
    @StateObject private var notchVM = NotchViewModel()
    @StateObject private var settings = AppSettings.shared
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var lastObservedBuildResult: XcodeBuildResult?
    @State private var sessionStart = Date()
    @State private var showStartupGlow = false
    @State private var startupGlowTask: Task<Void, Never>?
    @State private var isShowingBuildNotification = false
    @State private var buildNotificationTask: Task<Void, Never>?
    @State private var memeAutoOpenTask: Task<Void, Never>?
    @State private var memeGraceTask: Task<Void, Never>?
    @State private var isMemeGraceActive = false

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let activityGlowColor = Color(red: 0.0, green: 0.8, blue: 1.0)
    private let activityBrightColor = Color(red: 0.4, green: 0.95, blue: 1.0)
    private let startupGlowColor = Color(red: 0.55, green: 0.8, blue: 0.9)
    private let startupBrightColor = Color(red: 0.75, green: 0.9, blue: 1.0)

    private var hasActiveTask: Bool {
        mcpCoordinator.recentToolCalls.first?.isActive == true
    }

    private var isExpanded: Bool {
        notchVM.notchState == .open || notchVM.notchState == .peeking
    }

    private var lastTokenCount: Int? {
        mcpCoordinator.recentToolCalls.first?.tokenCount
    }

    private var recentTokenTotal: Int {
        mcpCoordinator.recentToolCalls.compactMap { $0.tokenCount }.reduce(0, +)
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    private var memeVideoURL: URL? {
        if let bundleURL = Bundle.main.url(forResource: "videoplayback", withExtension: "mp4") {
            return bundleURL
        }
        return URL(string: settings.memeVideoURL)
    }

    private var shouldShowMemeVideo: Bool {
        settings.showMemeVideo && memeVideoURL != nil && (hasActiveTask || isMemeGraceActive)
    }

    /// Calculate the content width (includes wings + center notch area)
    private var closedContentWidth: CGFloat {
        notchVM.closedNotchSize.width + 160  // wings extend 80px on each side
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
                    } else if hasActiveTask && notchVM.notchState == .closed && !isShowingBuildNotification {
                        NotchGlowBorder(
                            topCornerRadius: topCornerRadius,
                            bottomCornerRadius: bottomCornerRadius,
                            glowColor: activityGlowColor,
                            brightColor: activityBrightColor
                        )
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
        }
        .onDisappear {
            startupGlowTask?.cancel()
            buildNotificationTask?.cancel()
            memeAutoOpenTask?.cancel()
            memeGraceTask?.cancel()
        }
        .onChange(of: mcpCoordinator.lastBuildResult) { _, newResult in
            guard let result = newResult,
                  result.id != lastObservedBuildResult?.id,
                  notchVM.notchState == .closed else { return }
            lastObservedBuildResult = result
            showBuildNotification()
            notchVM.peek()
        }
        .onChange(of: hasActiveTask) { _, isActive in
            updateMemeAutoOpen(isActive: isActive)
            updateMemeGrace(isActive: isActive)
        }
        .onChange(of: settings.showMemeVideo) { _, isEnabled in
            if isEnabled {
                updateMemeAutoOpen(isActive: hasActiveTask)
                updateMemeGrace(isActive: hasActiveTask)
            } else {
                memeAutoOpenTask?.cancel()
                memeGraceTask?.cancel()
                isMemeGraceActive = false
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

    private func showBuildNotification() {
        buildNotificationTask?.cancel()
        isShowingBuildNotification = true
        buildNotificationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isShowingBuildNotification = false
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
                      hasActiveTask,
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
                if !hasActiveTask {
                    isMemeGraceActive = false
                }
            }
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
        let lastCall = mcpCoordinator.recentToolCalls.first
        // Calculate left wing width: status indicator (~14px) + spacing (6px) + text (~9px per char), max 18 chars
        let toolNameWidth: CGFloat = lastCall.map { CGFloat(min($0.toolName.count, 18)) * 9 } ?? 0
        let leftWingWidth: CGFloat = lastCall != nil ? 51 + toolNameWidth : 18
        let rightWingWidth: CGFloat = lastCall != nil ? 92 : 18
        let totalWidth = notchVM.closedNotchSize.width + leftWingWidth + rightWingWidth

        HStack(spacing: 0) {
            // Left wing - status indicator (+ tool name if available)
            HStack(spacing: 6) {
                StatusIndicatorView(state: mcpCoordinator.state)
                if let toolCall = lastCall {
                    Text(toolCall.toolName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .frame(width: leftWingWidth, alignment: .leading)
            .padding(.leading, 8)

            Spacer()

            // Right wing - spinner or duration/tokens (only when tool call exists)
            if let toolCall = lastCall {
                HStack(spacing: 6) {
                    if toolCall.isActive {
                        ProgressView()
                            .scaleEffect(0.3)
                            .frame(width: 8, height: 8)
                    } else {
                        if settings.showNotchTokenCount, let tokens = toolCall.tokenCount {
                            NotchPill(text: "\(tokens) t")
                        }
                        NotchPill(text: toolCall.formattedDuration, mono: true)
                    }
                }
                .frame(width: rightWingWidth, alignment: .trailing)
                .padding(.trailing, 8)
            } else {
                Spacer()
                    .frame(width: rightWingWidth)
                    .padding(.trailing, 8)
            }
        }
        .frame(width: totalWidth)
    }

    @ViewBuilder
    private var openHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                Image(systemName: "hammer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("AgentNotch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    StatusIndicatorView(state: mcpCoordinator.state)
                    Text(mcpCoordinator.state.displayText)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if mcpCoordinator.state == .running {
                    NotchControlButton(systemName: "stop.fill", tint: .red) {
                        Task { await mcpCoordinator.stop() }
                    }
                } else if mcpCoordinator.state == .stopped {
                    NotchControlButton(systemName: "play.fill", tint: .green) {
                        Task { try? await mcpCoordinator.start() }
                    }
                }

                NotchControlButton(systemName: "arrow.clockwise") {
                    Task { try? await mcpCoordinator.restart() }
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
        VStack(spacing: 12) {
            if shouldShowMemeVideo, let memeVideoURL {
                NotchSection(title: "Meme Mode") {
                    MemeVideoPlayerView(url: memeVideoURL)
                }
            }

            if let buildTime = mcpCoordinator.currentBuildTime {
                NotchSection {
                    BuildTimeView(duration: buildTime, result: mcpCoordinator.lastBuildResult)
                }
            }

            if !shouldShowMemeVideo {
                NotchSection(title: "Recent Tools") {
                    ToolCallListView(toolCalls: Array(mcpCoordinator.recentToolCalls.prefix(6)))
                }
            }

            Spacer(minLength: 0)

            NotchFooterView(
                sessionDuration: Date().timeIntervalSince(sessionStart),
                tokenTotal: recentTokenTotal,
                showTokenCount: settings.showNotchTokenCount
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var peekHeader: some View {
        HStack(spacing: 10) {
            if let result = mcpCoordinator.lastBuildResult {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(result.success ? .green : .red)

                Text(result.success ? "Build Succeeded" : "Build Failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            } else {
                StatusIndicatorView(state: mcpCoordinator.state)
                Text("Build Complete")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var peekContent: some View {
        VStack(spacing: 8) {
            if let buildTime = mcpCoordinator.currentBuildTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))

                    Text(String(format: "%.2fs", buildTime))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
        let showTokenCount: Bool

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))

                    Text(formatDuration(sessionDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    if showTokenCount {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))

                        Text(tokenTotal > 0 ? "\(tokenTotal) t" : "-")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
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

}

#Preview {
    NotchContentView()
        .environmentObject(MCPCoordinator.shared)
        .frame(width: 600, height: 300)
        .background(Color.gray.opacity(0.3))
}
