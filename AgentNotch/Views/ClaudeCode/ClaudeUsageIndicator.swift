//
//  ClaudeUsageIndicator.swift
//  AgentNotch
//
//  Displays Claude API usage quota in the notch
//

import SwiftUI

// MARK: - Compact Usage Indicator (for closed notch)

/// Small usage bar shown alongside Claude Code status in closed notch
struct ClaudeUsageCompactIndicator: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        if settings.showClaudeUsageInClosedNotch, usageManager.isConfigured, let fiveHour = usageManager.usageData.fiveHour {
            HStack(spacing: 4) {
                // Percentage text
                Text(fiveHour.formattedPercentage)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(colorForLevel(fiveHour.usageLevel))

                // Mini progress bar
                UsageMiniBar(percentage: fiveHour.percentage)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.4))
            .clipShape(Capsule())
        }
    }

    private func colorForLevel(_ level: UsageLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// Tiny progress bar for closed notch
struct UsageMiniBar: View {
    let percentage: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.2))

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(width: geometry.size.width * CGFloat(min(percentage, 100) / 100))
            }
        }
        .frame(width: 30, height: 4)
    }

    private var fillColor: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }
}

// MARK: - Expanded Usage View (for open notch / stats view)

/// Full usage display for the expanded notch view
struct ClaudeUsageExpandedView: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.secondary)
                Text("API Usage")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button(action: {
                    Task {
                        await usageManager.manualRefresh()
                    }
                }) {
                    Image(systemName: usageManager.isLoading ? "arrow.trianglehead.2.clockwise" : "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(usageManager.isLoading ? 360 : 0))
                        .animation(usageManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: usageManager.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(usageManager.isLoading)
            }

            if !usageManager.isConfigured {
                // Not configured state
                VStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Session key required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Configure in Settings")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else if let error = usageManager.lastError {
                // Error state
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                // Usage bars
                VStack(spacing: 10) {
                    // 5-hour limit (always shown)
                    if let fiveHour = usageManager.usageData.fiveHour {
                        UsageBarRow(
                            label: "5 Hour",
                            data: fiveHour,
                            icon: "clock"
                        )
                    }

                    // 7-day limit
                    if let sevenDay = usageManager.usageData.sevenDay {
                        UsageBarRow(
                            label: "7 Day",
                            data: sevenDay,
                            icon: "calendar"
                        )
                    }

                    // Opus limit
                    if let opus = usageManager.usageData.opus {
                        UsageBarRow(
                            label: "Opus",
                            data: opus,
                            icon: "sparkles"
                        )
                    }

                    // Sonnet limit
                    if let sonnet = usageManager.usageData.sonnet {
                        UsageBarRow(
                            label: "Sonnet",
                            data: sonnet,
                            icon: "wand.and.stars"
                        )
                    }

                    // Extra usage (paid)
                    if let extra = usageManager.usageData.extraUsage, extra.enabled {
                        ExtraUsageRow(data: extra)
                    }
                }

                // Last updated
                Text("Updated \(usageManager.usageData.fetchedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }
}

/// Single usage bar row
struct UsageBarRow: View {
    let label: String
    let data: ClaudeUsageData.LimitData
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(data.formattedPercentage)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(colorForLevel(data.usageLevel))

                if data.resetsAt != nil {
                    Text("• \(data.formattedRemaining)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))

                    // Fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForLevel(data.usageLevel))
                        .frame(width: geometry.size.width * CGFloat(min(data.percentage, 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }

    private func colorForLevel(_ level: UsageLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// Extra usage (paid) row
struct ExtraUsageRow: View {
    let data: ClaudeUsageData.ExtraUsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("Extra Usage")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(data.formattedUsed) / \(data.formattedLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.purple)
            }

            if let percentage = data.percentage {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple)
                            .frame(width: geometry.size.width * CGFloat(min(percentage, 100) / 100))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Inline API Usage Badges (for Context bar integration)

/// Ultra-compact ring indicator for inline display
struct MiniUsageRing: View {
    let label: String
    let percentage: Double
    var color: Color? = nil

    private var ringColor: Color {
        if let color = color { return color }
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(min(percentage, 100) / 100))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(-90))
            }

            // Label + percentage
            Text("\(label) \(Int(percentage.rounded()))%")
                .font(.system(size: 8, weight: .medium).monospacedDigit())
                .foregroundColor(ringColor)
        }
    }
}

/// Inline API usage badges to display next to other elements
struct InlineApiUsageBadges: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared

    var body: some View {
        if usageManager.isConfigured {
            HStack(spacing: 6) {
                if let fiveHour = usageManager.usageData.fiveHour {
                    MiniUsageRing(
                        label: "5h",
                        percentage: fiveHour.percentage
                    )
                }
                if let sevenDay = usageManager.usageData.sevenDay {
                    MiniUsageRing(
                        label: "7d",
                        percentage: sevenDay.percentage,
                        color: .purple
                    )
                }
            }
        }
    }
}

// MARK: - Legacy Compact Stats (kept for backwards compatibility)

/// Simplified usage display with circular badges - compact inline design
struct ClaudeUsageCompactStats: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared

    var body: some View {
        HStack(spacing: 8) {
            InlineApiUsageBadges()

            Spacer()

            // Refresh button
            if usageManager.isConfigured {
                Button(action: {
                    Task { await usageManager.manualRefresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(usageManager.isLoading ? 360 : 0))
                        .animation(usageManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: usageManager.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(usageManager.isLoading)
            }
        }
    }
}

// MARK: - Usage Badge (compact inline display)

/// Compact usage badge for embedding in other views
struct UsageBadge: View {
    let label: String
    let percentage: Double

    private var badgeColor: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(Int(percentage.rounded()))%")
                .font(.system(size: 8, weight: .bold).monospacedDigit())
                .foregroundColor(badgeColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .cornerRadius(3)
    }
}

// MARK: - Settings View

/// Settings view for configuring Claude Usage
struct ClaudeUsageSettingsView: View {
    @ObservedObject var usageManager = ClaudeUsageManager.shared
    @ObservedObject var settings = AppSettings.shared

    @State private var sessionKeyInput: String = ""
    @State private var showSessionKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Session Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Key")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if showSessionKey {
                        TextField("sk-ant-...", text: $sessionKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-ant-...", text: $sessionKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: { showSessionKey.toggle() }) {
                        Image(systemName: showSessionKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save") {
                        if usageManager.isValidSessionKey(sessionKeyInput) {
                            usageManager.sessionKey = sessionKeyInput
                            if settings.enableClaudeUsage {
                                usageManager.startRefreshing()
                            }
                        }
                    }
                    .disabled(!usageManager.isValidSessionKey(sessionKeyInput))

                    if usageManager.isConfigured {
                        Button("Clear", role: .destructive) {
                            usageManager.clearCredentials()
                            sessionKeyInput = ""
                        }
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(usageManager.isConfigured ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(usageManager.isConfigured ? "Configured" : "Not configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Get your session key from claude.ai cookies (DevTools → Application → Cookies → sessionKey)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Divider()

            // Refresh Settings
            VStack(alignment: .leading, spacing: 8) {
                Picker("Refresh Mode", selection: $settings.claudeUsageRefreshMode) {
                    Text("Smart").tag("smart")
                    Text("Fixed").tag("fixed")
                }
                .pickerStyle(.segmented)

                if settings.claudeUsageRefreshMode == "fixed" {
                    Picker("Interval", selection: $settings.claudeUsageRefreshInterval) {
                        Text("1 minute").tag(60)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                        Text("10 minutes").tag(600)
                    }
                } else {
                    HStack {
                        Text("Current Mode")
                            .font(.caption)
                        Spacer()
                        Text(usageManager.currentMonitoringMode.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Error display
            if let error = usageManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            sessionKeyInput = usageManager.sessionKey ?? ""
        }
        .onChange(of: settings.enableClaudeUsage) { _, newValue in
            if newValue && usageManager.isConfigured {
                usageManager.startRefreshing()
            } else {
                usageManager.stopRefreshing()
            }
        }
    }
}

// MARK: - Previews

#Preview("Compact Indicator") {
    HStack {
        ClaudeUsageCompactIndicator()
    }
    .padding()
    .background(Color.black)
}

#Preview("Expanded View") {
    ClaudeUsageExpandedView()
        .frame(width: 300)
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("Compact Stats") {
    ClaudeUsageCompactStats()
        .frame(width: 250)
        .padding()
        .background(Color.black.opacity(0.8))
}
