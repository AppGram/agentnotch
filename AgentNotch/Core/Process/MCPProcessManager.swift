import Foundation

protocol MCPProcessManagerDelegate: AnyObject {
    func processManager(_ manager: MCPProcessManager, didReceiveOutput data: Data)
    func processManager(_ manager: MCPProcessManager, didReceiveError data: Data)
    func processManager(_ manager: MCPProcessManager, didTerminateWithStatus status: Int32)
}

final class MCPProcessManager {
    weak var delegate: MCPProcessManagerDelegate?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    private let configuration: MCPConfiguration
    private let queue = DispatchQueue(label: "com.agentnotch.process", qos: .userInitiated)

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    init(configuration: MCPConfiguration) {
        self.configuration = configuration
    }

    func launch() async throws {
        guard !isRunning else {
            throw MCPProcessError.alreadyRunning
        }

        guard let executableURL = configuration.executableURL else {
            throw MCPProcessError.binaryNotFound(path: configuration.binaryPath)
        }

        // Kill any process using the HTTP port if in HTTP mode
        if configuration.useHTTP {
            await killProcessOnPort(configuration.httpPort)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        print("[MCP] Launching: \(executableURL.path) \(configuration.arguments.joined(separator: " "))")

        // Setup pipes
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Prevent SIGPIPE crashes
        signal(SIGPIPE, SIG_IGN)

        // Setup output handler
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.delegate?.processManager(self!, didReceiveOutput: data)
        }

        // Setup error handler - also print to console for debugging
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Print stderr for debugging
            if let str = String(data: data, encoding: .utf8) {
                print("[MCP stderr]: \(str)")
            }
            self?.delegate?.processManager(self!, didReceiveError: data)
        }

        // Setup termination handler
        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            print("[MCP] Process terminated with status: \(process.terminationStatus)")
            self.cleanup()
            self.delegate?.processManager(self, didTerminateWithStatus: process.terminationStatus)
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        try process.run()
    }

    func terminate() async {
        guard let process = process, process.isRunning else { return }

        process.terminate()

        // Wait briefly for graceful shutdown
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        if process.isRunning {
            // Force kill if still running
            kill(process.processIdentifier, SIGKILL)
        }

        cleanup()
    }

    func send(_ data: Data) throws {
        guard let inputPipe = inputPipe else {
            throw MCPProcessError.notRunning
        }

        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func sendLine(_ string: String) throws {
        let line = string.hasSuffix("\n") ? string : string + "\n"
        guard let data = line.data(using: .utf8) else {
            throw MCPProcessError.encodingError
        }
        try send(data)
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
    }

    /// Kill any process using the specified port
    private func killProcessOnPort(_ port: Int) async {
        let lsofProcess = Process()
        lsofProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofProcess.arguments = ["-ti", ":\(port)"]

        let pipe = Pipe()
        lsofProcess.standardOutput = pipe
        lsofProcess.standardError = FileHandle.nullDevice

        do {
            try lsofProcess.run()
            lsofProcess.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                return // No process on port
            }

            // Parse PIDs and kill them
            let pids = output.components(separatedBy: .newlines)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

            for pid in pids {
                kill(pid, SIGTERM)
            }

            // Wait briefly for processes to terminate
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Force kill if still running
            for pid in pids {
                kill(pid, SIGKILL)
            }
        } catch {
            // Ignore errors - port might just be free
        }
    }
}

enum MCPProcessError: LocalizedError {
    case alreadyRunning
    case notRunning
    case binaryNotFound(path: String)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "MCP process is already running"
        case .notRunning:
            return "MCP process is not running"
        case .binaryNotFound(let path):
            return "MCP binary not found at: \(path)"
        case .encodingError:
            return "Failed to encode data"
        }
    }
}
