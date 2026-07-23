import Foundation

struct MediaProcessResult {
    var terminationStatus: Int32
    var stdout: Data
    var stderr: Data

    var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
}

/// Runs a process without a shell, drains both pipes concurrently, and reacts
/// to Swift task cancellation by terminating the child process.
enum MediaProcessRunner {
    private final class CancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.withLock { value = true } }
        var isCancelled: Bool { lock.withLock { value } }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        func append(_ data: Data) { lock.withLock { bytes.append(data) } }
        var data: Data { lock.withLock { bytes } }
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        stderrChunk: (@Sendable (Data) -> Void)? = nil
    ) async throws -> MediaProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let cancellation = CancellationBox()
        let stdout = DataBox()
        let stderr = DataBox()

        let worker = Task.detached(priority: .utility) { () throws -> MediaProcessResult in
            try runSynchronously(
                process: process,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                cancellation: cancellation,
                stdout: stdout,
                stderr: stderr,
                stderrChunk: stderrChunk
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            cancellation.cancel()
            if process.isRunning { process.terminate() }
        }
    }

    /// Kept synchronous so pipe draining can use DispatchGroup without
    /// blocking a Swift cooperative-executor thread.
    private static func runSynchronously(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        cancellation: CancellationBox,
        stdout: DataBox,
        stderr: DataBox,
        stderrChunk: (@Sendable (Data) -> Void)?
    ) throws -> MediaProcessResult {
        if cancellation.isCancelled { throw CancellationError() }
        try process.run()

        let reads = DispatchGroup()
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = stdoutPipe.fileHandleForReading.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { break }
                stdout.append(chunk)
            }
            reads.leave()
        }
        reads.enter()
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = stderrPipe.fileHandleForReading.readData(ofLength: 16 * 1024)
                if chunk.isEmpty { break }
                stderr.append(chunk)
                stderrChunk?(chunk)
            }
            reads.leave()
        }

        process.waitUntilExit()
        reads.wait()
        if cancellation.isCancelled { throw CancellationError() }
        return MediaProcessResult(
            terminationStatus: process.terminationStatus,
            stdout: stdout.data,
            stderr: stderr.data
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
