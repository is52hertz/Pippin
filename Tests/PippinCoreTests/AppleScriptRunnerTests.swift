import Foundation
import Testing

@testable import PippinCore

/// These run real `osascript`. Nothing here talks to another application, so no
/// Automation grant is involved and the suite works on a clean machine.
@Suite("AppleScript runner")
struct AppleScriptRunnerTests {
    private let runner = AppleScriptRunner()

    private let echoFirst = """
        on run argv
            return item 1 of argv
        end run
        """

    @Test("arguments arrive as values")
    func passesArguments() async throws {
        let output = try await runner.run(script: echoFirst, arguments: ["hello"])
        #expect(output == "hello")
    }

    @Test("all arguments are delivered in order")
    func passesAllArguments() async throws {
        let script = """
            on run argv
                set AppleScript's text item delimiters to "|"
                return argv as text
            end run
            """
        #expect(try await runner.run(script: script, arguments: ["a", "b", "c"]) == "a|b|c")
    }

    // MARK: The reason this API exists

    @Test("a payload that would be code if interpolated comes back as text", arguments: [
        #""" & (do shell script "echo pwned") & """#,
        #"; do shell script "touch /tmp/pippin-injection-proof"; "#,
        "\" & (system attribute \"HOME\") & \"",
        "end run\non run argv\nreturn \"hijacked\"\nend run",
    ])
    func injectionPayloadsAreInert(payload: String) async throws {
        let marker = "/tmp/pippin-injection-proof"
        try? FileManager.default.removeItem(atPath: marker)

        let output = try await runner.run(script: echoFirst, arguments: [payload])

        // Returned verbatim: the payload never became part of the script's
        // structure, because it was never in the script text at all.
        #expect(output == payload)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test("a quote-heavy argument survives unchanged")
    func quotesSurvive() async throws {
        let awkward = #"He said "hi" \ then 'left' -- now"#
        #expect(try await runner.run(script: echoFirst, arguments: [awkward]) == awkward)
    }

    // MARK: Timeouts

    @Test("a hung script is killed and reported as a timeout")
    func timeoutFires() async {
        let sleeper = """
            on run argv
                delay 10
                return "finished"
            end run
            """
        let started = Date()
        let error = await #expect(throws: PippinError.self) {
            try await runner.run(script: sleeper, timeout: .milliseconds(600))
        }
        #expect(error?.code == .timeout)
        // The point is that it does not wedge the resident server for everyone
        // else, so it must actually return early rather than run to completion.
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test("a script that finishes inside the timeout is not killed")
    func fastScriptSurvives() async throws {
        #expect(try await runner.run(script: echoFirst, arguments: ["quick"], timeout: .seconds(10)) == "quick")
    }

    @Test("output larger than a pipe buffer does not deadlock")
    func largeOutput() async throws {
        // Reading after waitUntilExit would hang here: the script blocks writing
        // while we block waiting.
        let script = """
            on run argv
                set out to ""
                repeat 200 times
                    set out to out & "0123456789012345678901234567890123456789012345678901234567890123456789"
                end repeat
                return out
            end run
            """
        #expect(try await runner.run(script: script, timeout: .seconds(20)).count == 200 * 70)
    }

    // MARK: Error mapping

    @Test("a failing script becomes a backend error, never an empty result")
    func failureIsAnError() async {
        let broken = "this is not applescript at all"
        let error = await #expect(throws: PippinError.self) {
            try await runner.run(script: broken)
        }
        // Criterion A7: a failure must never look like "there is nothing".
        #expect(error != nil)
    }

    @Test("a missing Automation grant maps to permission_denied with the pane to open")
    func mapsAutomationDenial() {
        let error = AppleScriptRunner.error(from: "execution error: Not authorized to send Apple events to Mail. (-1743)")
        #expect(error.code == .permissionDenied)
        #expect(error.hint.contains("Automation"))
    }

    @Test("a not-running app maps to app_not_running", arguments: [
        "execution error: Mail got an error: Application isn't running. (-600)",
        "execution error: (-609)",
    ])
    func mapsNotRunning(stderr: String) {
        #expect(AppleScriptRunner.error(from: stderr).code == .appNotRunning)
    }

    @Test("an unrecognised failure still carries a diagnostic")
    func unknownFailureKeepsDetail() {
        let error = AppleScriptRunner.error(from: "execution error: something novel happened (-1728)")
        #expect(error.code == .backendUnavailable)
        #expect(error.hint.contains("novel"))
    }
}
