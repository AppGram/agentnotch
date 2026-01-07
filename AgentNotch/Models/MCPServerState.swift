import Foundation

enum MCPServerState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case crashed(reason: String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .running, .starting, .stopping:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .crashed(let reason):
            return "Crashed: \(reason)"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    static func == (lhs: MCPServerState, rhs: MCPServerState) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped),
             (.starting, .starting),
             (.running, .running),
             (.stopping, .stopping):
            return true
        case (.crashed(let l), .crashed(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
}
