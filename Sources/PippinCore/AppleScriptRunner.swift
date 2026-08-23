import Foundation

/// Runs AppleScript with caller-supplied values passed as arguments, never as
/// script text, under a wall-clock timeout.
///
/// Two non-negotiables from the design, both load-bearing:
///
/// 1. **No interpolation.** Agent-supplied values reach the script through
///    `on run argv`, as process arguments. Interpolating them would be a script
///    injection hole with the full privileges of the resident app — which holds
///    every TCC grant the user has given.
/// 2. **Always a timeout.** Apple Events default to two minutes, and this is a
///    resident process serving several clients. One hung Mail query must not
///    wedge the server for everyone else.
///
/// `osascript` as a subprocess rather than `NSAppleScript` in-process: a hung
/// script has to be killable, and an in-process API gives no way to do that.
public struct AppleScriptRunner: Sendable {
    /// Deliberately shorter than the Apple Event default of two minutes. A tool
    /// call that has not returned in fifteen seconds has failed as far as an
    /// agent conversation is concerned.
    public static let defaultTimeout: Duration = .seconds(15)

    private let executable: URL

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/osascript")) {
        self.executable = executable
    }

    /// Runs `script`, passing `arguments` as `argv`.
    ///
    /// - Parameter script: Trusted text, authored in this repository. Never
    ///   assembled from caller input.
    /// - Parameter arguments: Untrusted values. Delivered as process arguments,
    ///   so their content cannot change the script's structure.
    public func run(
        script: String,
        arguments: [String] = [],
        timeout: Duration = AppleScriptRunner.defaultTimeout
    ) async throws -> String {
        let process = Process()
        process.executableURL = executable
        // "-" reads the script from stdin, which keeps it out of the argument
        // vector entirely; everything after it is argv for `on run argv`.
        process.arguments = ["-"] + arguments

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw PippinError(
                .backendUnavailable,
                detail: "osascript",
                hint: "Could not run osascript. This is unexpected on macOS; check the system installation."
            )
        }

        input.fileHandleForWriting.write(Data(script.utf8))
        try? input.fileHandleForWriting.close()

        // Drain both pipes on their own threads. `readDataToEndOfFile` blocks
        // until the child closes the descriptor, so reading it inline would block
        // this task and the timeout below would never get to run — the watchdog
        // would only fire after the thing it was watching had already finished.
        // A script that outgrows the pipe buffer also deadlocks without this.
        let outputTask = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let errorTask = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }

        // A flag rather than a raced return value: terminating the process makes
        // the wait task finish too, so whichever task `next()` happens to return
        // first says nothing about *why* the process ended. The flag is set
        // before the signal, so it is already true by the time the wait returns.
        let watchdog = TimeoutFlag()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task.detached {
                        process.waitUntilExit()
                        continuation.resume()
                    }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return   // cancelled: the process finished first
                }
                guard process.isRunning else { return }
                watchdog.fire()
                process.terminate()
                // osascript blocked in `delay` does not always act on SIGTERM.
                // Give it a moment, then stop asking.
                try? await Task.sleep(for: .milliseconds(200))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            await group.next()
            group.cancelAll()
        }

        let timedOut = watchdog.didFire

        let outputData = await outputTask.value
        let errorData = await errorTask.value

        if timedOut {
            throw PippinError(
                .timeout,
                detail: "applescript",
                hint: "The app did not respond within \(timeout). Retry, or narrow the request."
            )
        }

        guard process.terminationStatus == 0 else {
            throw Self.error(from: String(decoding: errorData, as: UTF8.self))
        }

        // Only the trailing newline osascript appends is removed. Trimming all
        // whitespace would silently alter values — a subject or note may
        // legitimately begin or end with a space.
        var text = String(decoding: outputData, as: UTF8.self)
        while text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }
        return text
    }

    /// Maps osascript's stderr onto the error model.
    ///
    /// A missing Automation grant and a not-running app are the two failures a
    /// user can actually act on, so they must not arrive as a generic failure —
    /// and neither may ever surface as an empty result (criterion A7).
    static func error(from stderr: String) -> PippinError {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        // -1743: the user has not granted Automation control of the target app.
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("Not authorized") {
            return PippinError(
                .permissionDenied,
                detail: "automation",
                hint: "Grant Pippin control of this app in System Settings › Privacy & Security › Automation, then retry."
            )
        }
        // -600 / -609: the target application is not running.
        if text.contains("-600") || text.contains("-609")
            || text.localizedCaseInsensitiveContains("Application isn't running")
        {
            return PippinError(
                .appNotRunning,
                detail: "target",
                hint: "Open the app and retry. Pippin does not launch apps on your behalf."
            )
        }
        return PippinError(
            .backendUnavailable,
            detail: "applescript",
            hint: text.isEmpty ? "The script failed with no diagnostic." : String(text.prefix(200))
        )
    }
}

/// Records that the watchdog fired, so the outcome does not depend on which
/// racing task finishes first.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() {
        lock.lock()
        defer { lock.unlock() }
        fired = true
    }

    var didFire: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}
