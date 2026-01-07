import Foundation

public enum MCPTransport: String, Codable, CaseIterable {
    case stdio
    case http
}

public struct MCPConfiguration: Codable {
    var binaryPath: String
    var httpPort: Int
    var transport: MCPTransport

    static var `default`: MCPConfiguration {
        MCPConfiguration(
            binaryPath: "/usr/local/bin/bridge4simulator-xcauto",
            httpPort: 8765,
            transport: .http
        )
    }

    static var stdio: MCPConfiguration {
        MCPConfiguration(
            binaryPath: "/usr/local/bin/bridge4simulator-xcauto",
            httpPort: 8765,
            transport: .stdio
        )
    }

    var arguments: [String] {
        switch transport {
        case .stdio:
            return ["mcp"]
        case .http:
            return ["mcp", "--http", "--port", "\(httpPort)"]
        }
    }

    var executableURL: URL? {
        let url = URL(fileURLWithPath: binaryPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var isValid: Bool {
        executableURL != nil
    }

    var httpURL: URL? {
        guard transport == .http else { return nil }
        return URL(string: "http://localhost:\(httpPort)")
    }

    // Migration support for old configs with useHTTP
    var useHTTP: Bool {
        get { transport == .http }
        set { transport = newValue ? .http : .stdio }
    }
}
