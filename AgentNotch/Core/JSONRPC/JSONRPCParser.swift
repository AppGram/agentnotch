import Foundation

final class JSONRPCParser {
    private let decoder = JSONDecoder()

    enum ParsedMessage {
        case request(JSONRPCRequest)
        case response(JSONRPCResponse)
        case notification(JSONRPCNotification)
        case invalid(error: Error, rawData: Data)
    }

    func parse(_ data: Data) -> ParsedMessage {
        // Try response first (most common from MCP server)
        if let response = try? decoder.decode(JSONRPCResponse.self, from: data) {
            return .response(response)
        }

        // Try request
        if let request = try? decoder.decode(JSONRPCRequest.self, from: data) {
            if request.id != nil {
                return .request(request)
            } else {
                // No ID means it's a notification
                if let notification = try? decoder.decode(JSONRPCNotification.self, from: data) {
                    return .notification(notification)
                }
            }
        }

        // Try notification directly
        if let notification = try? decoder.decode(JSONRPCNotification.self, from: data) {
            return .notification(notification)
        }

        // Failed to parse
        let error = NSError(domain: "JSONRPCParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to parse JSON-RPC message"])
        return .invalid(error: error, rawData: data)
    }

    func extractToolCallInfo(from request: JSONRPCRequest) -> (name: String, arguments: [String: AnyCodableValue])? {
        guard request.method == "tools/call" else { return nil }

        guard case .dictionary(let params) = request.params else { return nil }

        guard case .string(let name) = params["name"] else { return nil }

        var arguments: [String: AnyCodableValue] = [:]
        if case .dictionary(let args) = params["arguments"] {
            arguments = args
        }

        return (name: name, arguments: arguments)
    }

    func extractToolResult(from response: JSONRPCResponse) -> (content: String, isError: Bool)? {
        guard let result = response.result else {
            if let error = response.error {
                return (content: error.message, isError: true)
            }
            return nil
        }

        // Try to extract content from MCP tool result format
        if case .dictionary(let dict) = result {
            var isError = false
            if case .bool(let err) = dict["isError"] {
                isError = err
            }

            if case .array(let contentArray) = dict["content"] {
                var textParts: [String] = []
                for item in contentArray {
                    if case .dictionary(let itemDict) = item {
                        if case .string(let text) = itemDict["text"] {
                            textParts.append(text)
                        }
                    }
                }
                if !textParts.isEmpty {
                    return (content: textParts.joined(separator: "\n"), isError: isError)
                }
            }
        }

        // Fallback: encode result as JSON string
        if let data = try? JSONEncoder().encode(result),
           let jsonString = String(data: data, encoding: .utf8) {
            return (content: jsonString, isError: false)
        }

        return nil
    }

    func extractBuildResult(from response: JSONRPCResponse) -> XcodeBuildResult? {
        guard let result = response.result else { return nil }

        // Try to extract content first
        if case .dictionary(let dict) = result,
           case .array(let contentArray) = dict["content"],
           let firstItem = contentArray.first,
           case .dictionary(let itemDict) = firstItem,
           case .string(let text) = itemDict["text"] {
            // Parse the text as JSON to get XcodeBuildResult
            if let textData = text.data(using: .utf8),
               let buildResult = try? JSONDecoder().decode(XcodeBuildResult.self, from: textData) {
                return buildResult
            }
        }

        return nil
    }
}
