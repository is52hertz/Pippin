import Foundation
import Testing

@testable import PippinCore

@Suite("Mutation gate")
struct MutationGateTests {
    private func gate(
        enabled: Bool = true,
        writes: Bool = true,
        capabilities: Capabilities = .all
    ) -> MutationGate {
        MutationGate(
            config: Config(modules: ["reminders": .init(enabled: enabled, writes: writes)]),
            capabilities: capabilities
        )
    }

    @Test("a permitted write passes both gates")
    func allows() throws {
        try gate().check(.write, module: "reminders")
    }

    @Test("writes disabled refuses with writes_disabled")
    func writesDisabled() {
        let error = #expect(throws: PippinError.self) {
            try gate(writes: false).check(.write, module: "reminders")
        }
        #expect(error?.code == .writesDisabled)
    }

    @Test("reads still work when writes are disabled")
    func readsSurviveWritesOff() throws {
        try gate(writes: false).check(.read, module: "reminders")
    }

    @Test("a disabled module refuses everything")
    func disabledModule() {
        let error = #expect(throws: PippinError.self) {
            try gate(enabled: false).check(.read, module: "reminders")
        }
        #expect(error?.code == .notFound)
    }

    @Test("an unknown module refuses")
    func unknownModule() {
        #expect(throws: PippinError.self) { try gate().check(.read, module: "nope") }
    }

    @Test("a read-only token cannot write even when the module allows it")
    func capabilityIsRequired() {
        let error = #expect(throws: PippinError.self) {
            try gate(capabilities: .readOnly).check(.write, module: "reminders")
        }
        #expect(error?.code == .permissionDenied)
    }

    @Test("config wins over capability")
    func configBeatsCapability() {
        // The token says the caller may destroy; the module says no writes. The
        // conservative side wins.
        #expect(throws: PippinError.self) {
            try gate(writes: false, capabilities: .all).check(.destructive, module: "reminders")
        }
    }
}

@Suite("Audit log")
struct AuditLogTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "pippin audit \(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "audit.jsonl")
    }

    @Test("a mutation attempt is recorded as one line")
    func recordsEntry() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)

        await log.record(tool: "pippin_reminders_delete", module: "reminders", ids: ["R1"], outcome: .succeeded)
        let entries = try await log.entries()

        #expect(entries.count == 1)
        #expect(entries.first?.tool == "pippin_reminders_delete")
        #expect(entries.first?.ids == ["R1"])
        #expect(entries.first?.outcome == .succeeded)
    }

    @Test("refusals are recorded too")
    func recordsRefusals() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)

        // A refused delete is exactly the event worth finding later.
        await log.record(tool: "t", outcome: .refused, error: PippinError(.confirmationInvalid, detail: "items"))
        let entries = try await log.entries()
        #expect(entries.first?.outcome == .refused)
        #expect(entries.first?.error == "items")
    }

    @Test("argument values are never written, only a digest")
    func argumentsAreDigested() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)

        await log.record(tool: "t", outcome: .succeeded, arguments: ["note": "my private medical note"])

        // The audit trail must not become a second copy of the user's data.
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("my private medical note"))
        #expect(raw.contains("argumentsDigest"))
    }

    @Test("the digest is stable regardless of key order")
    func digestIsCanonical() {
        #expect(AuditLog.digest(["a": "1", "b": "2"]) == AuditLog.digest(["b": "2", "a": "1"]))
        #expect(AuditLog.digest(["a": "1"]) != AuditLog.digest(["a": "2"]))
    }

    @Test("the log file is not world-readable")
    func filePermissions() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await AuditLog(url: url).record(tool: "t", outcome: .succeeded)

        let mode = try FileManager.default
            .attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o600)
    }

    @Test("entries accumulate in order")
    func appends() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let log = AuditLog(url: url)

        for index in 0..<5 {
            await log.record(tool: "tool-\(index)", outcome: .succeeded)
        }
        #expect(try await log.entries().map(\.tool) == (0..<5).map { "tool-\($0)" })
    }

    @Test("an unwritable location never fails the caller's operation")
    func writeFailureIsSwallowed() async {
        // Losing an audit line is bad; refusing the delete the user asked for
        // because of it is worse.
        let log = AuditLog(url: URL(fileURLWithPath: "/dev/null/impossible/audit.jsonl"))
        await log.record(tool: "t", outcome: .succeeded)
    }
}

@Suite("Backend routing")
struct BackendRouterTests {
    private func backend(
        _ name: String,
        available: Bool = true,
        result: Result<String, PippinError> = .success("value")
    ) -> Backend<String> {
        Backend(
            name: name,
            isAvailable: { available },
            run: {
                switch result {
                case .success(let value): return value
                case .failure(let error): throw error
                }
            }
        )
    }

    @Test("the first available backend answers, undegraded")
    func firstBackendWins() async throws {
        let routed = try await BackendRouter.route(
            [backend("sqlite"), backend("applescript")], capability: "search")
        #expect(routed.backend == "sqlite")
        #expect(!routed.degraded)
        #expect(routed.reason == nil)
    }

    @Test("an unavailable backend is skipped and the answer is marked degraded")
    func skipsUnavailable() async throws {
        let routed = try await BackendRouter.route(
            [backend("sqlite", available: false), backend("applescript")], capability: "search")

        #expect(routed.backend == "applescript")
        // Visibly degraded rather than silently slow.
        #expect(routed.degraded)
        #expect(routed.reason?.contains("sqlite") == true)
    }

    @Test("a failing backend falls through to the next")
    func failsOver() async throws {
        let routed = try await BackendRouter.route(
            [
                backend("sqlite", result: .failure(PippinError(.backendUnavailable, detail: "schema"))),
                backend("applescript"),
            ],
            capability: "search"
        )
        #expect(routed.backend == "applescript")
        #expect(routed.degraded)
    }

    @Test("when everything fails it throws — it never returns nothing")
    func neverSilentlyEmpty() async {
        // Criterion A7. An empty result is indistinguishable from a true answer,
        // which is what makes this the worst possible failure mode.
        let error = await #expect(throws: PippinError.self) {
            try await BackendRouter.route(
                [
                    backend("sqlite", result: .failure(PippinError(.permissionDenied, detail: "fda"))),
                    backend("applescript", result: .failure(PippinError(.appNotRunning, detail: "Mail"))),
                ],
                capability: "search"
            )
        }
        // The first real failure is surfaced: it carries the actionable hint.
        #expect(error?.code == .permissionDenied)
    }

    @Test("all backends unavailable throws with the names")
    func allUnavailable() async {
        let error = await #expect(throws: PippinError.self) {
            try await BackendRouter.route(
                [backend("sqlite", available: false), backend("applescript", available: false)],
                capability: "search"
            )
        }
        #expect(error?.code == .backendUnavailable)
        #expect(error?.hint.contains("sqlite") == true)
    }

    @Test("no backends at all is an error, not an empty answer")
    func noBackends() async {
        await #expect(throws: PippinError.self) {
            try await BackendRouter.route([Backend<String>](), capability: "search")
        }
    }
}
