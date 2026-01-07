import SwiftUI

struct StatusIndicatorView: View {
    let state: MCPServerState

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
        case .starting, .stopping:
            return .yellow
        case .running:
            return .green
        case .crashed, .error:
            return .red
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusIndicatorView(state: .stopped)
        StatusIndicatorView(state: .starting)
        StatusIndicatorView(state: .running)
        StatusIndicatorView(state: .crashed(reason: "Test"))
    }
    .padding()
}
