import Foundation

// JSON-RPC 2.0 Types (mirroring MCP protocol)

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodableValue?

    init(jsonrpc: String = "2.0", id: JSONRPCId? = nil, method: String, params: AnyCodableValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId
    let result: AnyCodableValue?
    let error: JSONRPCError?

    var isSuccess: Bool {
        error == nil
    }
}

struct JSONRPCError: Codable, Equatable {
    let code: Int
    let message: String
    let data: AnyCodableValue?

    static func == (lhs: JSONRPCError, rhs: JSONRPCError) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message
    }
}

struct JSONRPCNotification: Codable {
    let jsonrpc: String
    let method: String
    let params: AnyCodableValue?
}

enum JSONRPCId: Codable, Hashable, Equatable {
    case int(Int)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(JSONRPCId.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected Int, String, or null"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .int(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .null:
            hasher.combine(2)
        }
    }
}

// MCP-specific message types

struct MCPToolsCallParams: Codable {
    let name: String
    let arguments: [String: AnyCodableValue]?
}

struct MCPToolResult: Codable {
    let content: [MCPContentItem]?
    let isError: Bool?
}

struct MCPContentItem: Codable {
    let type: String
    let text: String?
}

// Build result from xcode_build/xcode_run tools
struct XcodeBuildResult: Codable, Identifiable, Equatable {
    let id: UUID
    let success: Bool
    let appPath: String?
    let bundleId: String?
    let configuration: String?
    let sdk: String?
    let durationMs: Int?
    let warnings: Int?
    let errors: Int?
    let errorOutput: String?

    var duration: TimeInterval? {
        guard let ms = durationMs else { return nil }
        return TimeInterval(ms) / 1000.0
    }

    init(success: Bool, appPath: String? = nil, bundleId: String? = nil, configuration: String? = nil, sdk: String? = nil, durationMs: Int? = nil, warnings: Int? = nil, errors: Int? = nil, errorOutput: String? = nil) {
        self.id = UUID()
        self.success = success
        self.appPath = appPath
        self.bundleId = bundleId
        self.configuration = configuration
        self.sdk = sdk
        self.durationMs = durationMs
        self.warnings = warnings
        self.errors = errors
        self.errorOutput = errorOutput
    }

    enum CodingKeys: String, CodingKey {
        case success, appPath, bundleId, configuration, sdk, durationMs, warnings, errors, errorOutput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.success = try container.decode(Bool.self, forKey: .success)
        self.appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        self.configuration = try container.decodeIfPresent(String.self, forKey: .configuration)
        self.sdk = try container.decodeIfPresent(String.self, forKey: .sdk)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        self.warnings = try container.decodeIfPresent(Int.self, forKey: .warnings)
        self.errors = try container.decodeIfPresent(Int.self, forKey: .errors)
        self.errorOutput = try container.decodeIfPresent(String.self, forKey: .errorOutput)
    }
}
