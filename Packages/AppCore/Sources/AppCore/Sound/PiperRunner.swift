import Foundation

/// Why rendering with Piper failed – shown in Einstellungen › Ton.
public enum PiperError: Error, Equatable, LocalizedError {
    case missing
    case timeout(TimeInterval)
    case crashed(Int32)
    case failed(Int32, String)
    case noAudio
    case voiceNotInstalled(String)
    case download(String)
    case checksum(String)

    public var errorDescription: String? {
        switch self {
        case .missing:
            return "Die Sprachausgabe (Piper) fehlt im App-Paket. Installiere die App neu."
        case .timeout(let seconds):
            return "Piper hat nach \(Int(seconds)) Sekunden keinen Ton geliefert und wurde beendet."
        case .crashed(let signal):
            return "Piper ist abgestürzt (Signal \(signal))."
        case .failed(let status, let detail):
            let tail = detail.isEmpty ? "" : ": \(detail)"
            return "Piper ist mit Fehler \(status) beendet\(tail)."
        case .noAudio:
            return "Piper hat keinen Ton erzeugt. Steht im Text etwas Sprechbares?"
        case .voiceNotInstalled(let label):
            return "Die Stimme „\(label)“ ist nicht geladen."
        case .download(let detail):
            return "Die Stimme konnte nicht geladen werden (\(detail)). Zum ersten Gebrauch braucht sie einmal Internet – prüf die Verbindung und versuch es noch einmal."
        case .checksum(let label):
            return "Die geladene Stimme „\(label)“ ist beschädigt (Prüfsumme stimmt nicht). Versuch es noch einmal."
        }
    }
}

/// Runs a program with text on stdin and a deadline – off the main thread, cancellable.
/// Used for Piper; generic so the tests can run `/bin/sh` instead.
public enum PiperRunner {
    public static let defaultTimeout: TimeInterval = 20

    /// Deadline for one render (voice load included): 20 s + 0.15 s per character, like the Phase 5
    /// renderer – 1 000 characters with „Thorsten · hoch“ took 18 s under Rosetta on an M1 Max.
    public static func timeout(forCharacters count: Int) -> TimeInterval {
        defaultTimeout + 0.15 * Double(max(0, count))
    }

    /// Runs `executable` and waits. Throws `.missing`, `.timeout`, `.crashed`, `.failed`
    /// (with the last line of stderr) or `CancellationError`.
    public static func run(executable: URL, arguments: [String], input: String,
                           timeout: TimeInterval = defaultTimeout) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw PiperError.missing }
        let job = Job(executable: executable, arguments: arguments, input: input, timeout: timeout)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                job.start { continuation.resume(with: $0) }
            }
        } onCancel: {
            job.cancel()
        }
    }

    /// Owns the Process; completes exactly once (exit, timeout or cancellation).
    private final class Job: @unchecked Sendable {
        private let process = Process()
        private let timeout: TimeInterval
        private let input: String
        private let lock = NSLock()
        private var completion: ((Result<Void, Error>) -> Void)?
        private var reason: Error?
        private let stderr = Pipe()
        private var stderrData = Data()

        init(executable: URL, arguments: [String], input: String, timeout: TimeInterval) {
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            // Nothing from the app's environment (DYLD_*, proxies) reaches the helper.
            process.environment = ["PATH": "/usr/bin:/bin", "LANG": "de_DE.UTF-8"]
            self.timeout = timeout
            self.input = input
        }

        func start(_ completion: @escaping (Result<Void, Error>) -> Void) {
            let stdin = Pipe()
            process.standardInput = stdin
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self, !chunk.isEmpty else { return }
                self.lock.withLock {
                    // Keep the tail only (Piper logs one line per sentence).
                    self.stderrData.append(chunk)
                    if self.stderrData.count > 8_192 { self.stderrData = self.stderrData.suffix(4_096) }
                }
            }
            process.terminationHandler = { [weak self] process in self?.finished(process) }
            let cancelledEarly: Bool = lock.withLock {
                self.completion = completion
                return reason != nil
            }
            if cancelledEarly { finishNow(); return }
            do {
                try process.run()
            } catch {
                lock.withLock { self.reason = PiperError.missing }
                finishNow()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.stop(because: PiperError.timeout(self.timeout))
            }
            let data = Data(input.utf8)
            let writer = stdin.fileHandleForWriting
            // Piper may exit before reading everything: a write into the closed pipe must fail
            // with EPIPE instead of killing the app with SIGPIPE.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? writer.write(contentsOf: data)
                try? writer.close()
            }
        }

        func cancel() {
            stop(because: CancellationError())
        }

        /// Timeout or cancellation: remember why, then end the process (its termination handler
        /// completes). Before `start` the reason alone is enough – `start` sees it and completes.
        private func stop(because error: Error) {
            let running: Bool = lock.withLock {
                if reason == nil { reason = error }
                return process.isRunning
            }
            guard running else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.process.isRunning == true { kill(pid, SIGKILL) }
            }
        }

        private func finished(_ process: Process) {
            stderr.fileHandleForReading.readabilityHandler = nil
            let rest = stderr.fileHandleForReading.readDataToEndOfFile()
            lock.withLock {
                stderrData.append(rest)
                guard reason == nil else { return }
                switch process.terminationReason {
                case .uncaughtSignal:
                    reason = PiperError.crashed(process.terminationStatus)
                case .exit where process.terminationStatus != 0:
                    reason = PiperError.failed(process.terminationStatus, Self.lastLine(stderrData))
                default:
                    break
                }
            }
            finishNow()
        }

        private func finishNow() {
            let (callback, error): (((Result<Void, Error>) -> Void)?, Error?) = lock.withLock {
                let callback = completion
                completion = nil
                return (callback, reason)
            }
            guard let callback else { return }
            if let error { callback(.failure(error)) } else { callback(.success(())) }
        }

        private static func lastLine(_ data: Data) -> String {
            let text = String(decoding: data, as: UTF8.self)
            let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            return String(line.trimmingCharacters(in: .whitespaces).prefix(200))
        }
    }
}
