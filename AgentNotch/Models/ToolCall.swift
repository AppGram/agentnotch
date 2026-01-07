import Foundation

struct ToolCall: Identifiable, Codable, Equatable {
    let id: UUID
    let toolName: String
    let arguments: [String: AnyCodableValue]
    let startTime: Date
    var endTime: Date?
    var result: ToolCallResult?
    var tokenCount: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var costUsd: Double?
    var source: TelemetrySource

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "-" }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    var isActive: Bool {
        endTime == nil
    }

    var isSuccess: Bool {
        guard let result = result else { return false }
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    var isBuildTool: Bool {
        toolName == "xcode_build" || toolName == "xcode_run"
    }

    init(
        id: UUID = UUID(),
        toolName: String,
        arguments: [String: AnyCodableValue] = [:],
        startTime: Date = Date(),
        tokenCount: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        costUsd: Double? = nil,
        source: TelemetrySource = .unknown
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.startTime = startTime
        self.tokenCount = tokenCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUsd = costUsd
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case arguments
        case startTime
        case endTime
        case result
        case tokenCount
        case inputTokens
        case outputTokens
        case costUsd
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        toolName = try container.decode(String.self, forKey: .toolName)
        arguments = try container.decode([String: AnyCodableValue].self, forKey: .arguments)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        result = try container.decodeIfPresent(ToolCallResult.self, forKey: .result)
        tokenCount = try container.decodeIfPresent(Int.self, forKey: .tokenCount)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
        source = try container.decodeIfPresent(TelemetrySource.self, forKey: .source) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(tokenCount, forKey: .tokenCount)
        try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
        try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
        try container.encodeIfPresent(costUsd, forKey: .costUsd)
        try container.encode(source, forKey: .source)
    }
}

enum ToolCallResult: Codable, Equatable {
    case success(content: String)
    case failure(error: String)

    private enum CodingKeys: String, CodingKey {
        case type, content, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "success" {
            let content = try container.decode(String.self, forKey: .content)
            self = .success(content: content)
        } else {
            let error = try container.decode(String.self, forKey: .error)
            self = .failure(error: error)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let content):
            try container.encode("success", forKey: .type)
            try container.encode(content, forKey: .content)
        case .failure(let error):
            try container.encode("failure", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }
}

// Type-erased codable value for JSON arguments
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}
