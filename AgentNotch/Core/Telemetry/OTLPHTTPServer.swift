import Foundation
import Network
import zlib

final class OTLPHTTPServer {
    enum Route {
        case logs
        case metrics
        case other
    }

    struct Request {
        let route: Route
        let body: Data
    }

    var onRequest: ((Request) -> Void)?
    var onError: ((String) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.agentnotch.otlp.server", qos: .userInitiated)
    private var activeHandlers: [ObjectIdentifier: HTTPConnectionHandler] = [:]

    func start(port: UInt16) throws {
        let params = NWParameters.tcp
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "OTLPHTTPServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port: \(port)"])
        }
        let listener = try NWListener(using: params, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        let handler = HTTPConnectionHandler(connection: connection) { [weak self] request in
            print("[OTLP] Received request: \(request.route), body size: \(request.body.count)")
            self?.onRequest?(request)
        } onError: { [weak self] message in
            self?.onError?(message)
        } onComplete: { [weak self] handler in
            self?.queue.async {
                self?.activeHandlers.removeValue(forKey: ObjectIdentifier(handler))
            }
        }

        activeHandlers[ObjectIdentifier(handler)] = handler
        handler.start()
    }
}

private final class HTTPConnectionHandler {
    private let connection: NWConnection
    private let onRequest: (OTLPHTTPServer.Request) -> Void
    private let onError: (String) -> Void
    private let onComplete: (HTTPConnectionHandler) -> Void

    private var buffer = Data()
    private var headerParsed = false
    private var contentLength: Int = 0
    private var route: OTLPHTTPServer.Route = .other
    private var contentEncoding: String?

    init(
        connection: NWConnection,
        onRequest: @escaping (OTLPHTTPServer.Request) -> Void,
        onError: @escaping (String) -> Void,
        onComplete: @escaping (HTTPConnectionHandler) -> Void
    ) {
        self.connection = connection
        self.onRequest = onRequest
        self.onError = onError
        self.onComplete = onComplete
    }

    func start() {
        connection.start(queue: .global())
        receiveNext()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data {
                self.buffer.append(data)
                self.processBuffer()
            }

            if let error {
                self.onError("OTLP HTTP receive error: \(error)")
                self.finish()
                return
            }

            if isComplete {
                self.finish()
                return
            }

            self.receiveNext()
        }
    }

    private func processBuffer() {
        if !headerParsed {
            guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
            parseHeaders(headerData)
            buffer.removeSubrange(0..<headerRange.upperBound)
            headerParsed = true
        }

        guard headerParsed else { return }
        guard buffer.count >= contentLength else { return }

        let body = Data(buffer.prefix(contentLength))
        buffer.removeSubrange(0..<contentLength)
        let decodedBody = decodeBodyIfNeeded(body)
        onRequest(.init(route: route, body: decodedBody))
        sendResponse(status: 200)
        finish()
    }

    private func finish() {
        connection.cancel()
        onComplete(self)
    }

    private func parseHeaders(_ data: Data) {
        let headerString = String(decoding: data, as: UTF8.self)
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return }

        let parts = requestLine.split(separator: " ")
        if parts.count >= 2 {
            route = Self.route(for: String(parts[1]))
        }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("content-length:") {
                let value = trimmed.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            } else if trimmed.lowercased().hasPrefix("content-encoding:") {
                let value = trimmed.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                contentEncoding = value.lowercased()
            }
        }
    }

    private func sendResponse(status: Int) {
        let response = "HTTP/1.1 \(status) OK\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func decodeBodyIfNeeded(_ data: Data) -> Data {
        if shouldGunzip(data), let inflated = gunzip(data) {
            return inflated
        }
        return data
    }

    private func shouldGunzip(_ data: Data) -> Bool {
        if contentEncoding?.contains("gzip") == true {
            return true
        }
        return data.starts(with: [0x1f, 0x8b])
    }

    private func gunzip(_ data: Data) -> Data? {
        var stream = z_stream()
        var status = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = UInt32(data.count)

            var output = Data()
            let chunkSize = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while true {
                status = buffer.withUnsafeMutableBytes { bufferPtr in
                    stream.next_out = bufferPtr.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = UInt32(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }

                if status == Z_STREAM_END {
                    return output
                }
                if status != Z_OK {
                    return nil
                }
            }
        }
    }

    private static func route(for path: String) -> OTLPHTTPServer.Route {
        if path.hasSuffix("/v1/logs") {
            return .logs
        }
        if path.hasSuffix("/v1/metrics") {
            return .metrics
        }
        return .other
    }
}
