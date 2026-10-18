import XCTest
@testable import AppCore

/// The runner with `/bin/sh` standing in for Piper (exit codes, signals, hangs, stdin).
final class PiperRunnerTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    func testPassesTextOnStdin() async throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: out) }
        try await PiperRunner.run(executable: shell, arguments: ["-c", "cat > \"$0\"", out.path], input: "Hallo Welt\n")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "Hallo Welt\n")
    }

    func testMissingProgram() async {
        await assertThrows(.missing) {
            try await PiperRunner.run(executable: URL(fileURLWithPath: "/nonexistent/piper"), arguments: [], input: "x\n")
        }
    }

    func testExitCodeAndLastStderrLine() async {
        await assertThrows(.failed(3, "Model file doesn't exist")) {
            try await PiperRunner.run(executable: self.shell,
                                      arguments: ["-c", "echo first >&2; echo \"Model file doesn't exist\" >&2; exit 3"], input: "x\n")
        }
    }

    func testCrash() async {
        await assertThrows(.crashed(SIGABRT)) {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "kill -ABRT $$"], input: "x\n")
        }
    }

    func testTimeoutEndsTheProcess() async {
        let start = Date()
        await assertThrows(.timeout(0.5)) {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "sleep 30"], input: "x\n", timeout: 0.5)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testProgramThatIgnoresStdinDoesNotKillTheApp() async throws {
        // Exits before reading: the write into the closed pipe must not raise SIGPIPE here.
        try await PiperRunner.run(executable: shell, arguments: ["-c", "exit 0"],
                                  input: String(repeating: "x", count: 1 << 20))
    }

    func testCancellation() async {
        let task = Task {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "sleep 30"], input: "x\n", timeout: 20)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    private func assertThrows(_ expected: PiperError, _ body: @escaping () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PiperError, expected, file: file, line: line)
        }
    }

    func testMessagesAreGerman() {
        XCTAssertEqual(PiperError.timeout(20).errorDescription, "Piper hat nach 20 Sekunden keinen Ton geliefert und wurde beendet.")
        XCTAssertEqual(PiperError.voiceNotInstalled("Kerstin · niedrig").errorDescription, "Die Stimme „Kerstin · niedrig“ ist nicht geladen.")
        XCTAssertEqual(PiperError.failed(1, "").errorDescription, "Piper ist mit Fehler 1 beendet.")
    }
}
