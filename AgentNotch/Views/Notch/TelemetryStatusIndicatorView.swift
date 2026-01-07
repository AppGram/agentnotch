import SwiftUI

struct TelemetryStatusIndicatorView: View {
    let state: TelemetryState

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: statusColor.opacity(state.isActive ? 0.6 : 0.3), radius: state.isActive ? 4 : 2)
    }

    private var statusColor: Color {
        switch state {
        case .stopped:
            return .gray
        case .starting:
            return .yellow
        case .running:
            return .green
        case .error:
            return .red
        }
    }
}

struct SourceIndicatorView: View {
    let source: TelemetrySource
    let isActive: Bool

    private var sourceColor: Color {
        switch source {
        case .claudeCode:
            return Color(red: 1.0, green: 0.55, blue: 0.2) // Orange
        case .codex:
            return Color(red: 0.2, green: 0.45, blue: 0.9) // Blue
        case .unknown:
            return Color(red: 0.6, green: 0.8, blue: 1.0) // Light blue
        }
    }

    var body: some View {
        Circle()
            .fill(sourceColor)
            .frame(width: 8, height: 8)
            .shadow(color: sourceColor.opacity(isActive ? 0.6 : 0.3), radius: isActive ? 4 : 2)
    }
}

#Preview {
    VStack(spacing: 20) {
        TelemetryStatusIndicatorView(state: .stopped)
        TelemetryStatusIndicatorView(state: .starting)
        TelemetryStatusIndicatorView(state: .running)
        TelemetryStatusIndicatorView(state: .error("Test"))

        Divider()

        SourceIndicatorView(source: .claudeCode, isActive: true)
        SourceIndicatorView(source: .codex, isActive: false)
        SourceIndicatorView(source: .unknown, isActive: false)
    }
    .padding()
}
