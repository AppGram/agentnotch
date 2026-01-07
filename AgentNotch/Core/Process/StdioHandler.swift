import Foundation

final class StdioHandler {
    var onLineReceived: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var lineBuffer = Data()
    private let queue = DispatchQueue(label: "com.agentnotch.stdio")
    private let newlineData = "\n".data(using: .utf8)!

    func processReceivedData(_ data: Data) {
        queue.async { [weak self] in
            self?.processDataInternal(data)
        }
    }

    private func processDataInternal(_ data: Data) {
        lineBuffer.append(data)

        // Process complete lines
        while let newlineRange = lineBuffer.range(of: newlineData) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineRange.lowerBound)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineRange.lowerBound)

            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onLineReceived?(line)
                }
            }
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.lineBuffer.removeAll()
        }
    }
}
