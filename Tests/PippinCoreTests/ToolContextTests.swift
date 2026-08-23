import Foundation
import Testing

@testable import PippinCore

/// The two-phase delete protocol lives in one place so every destructive tool in
/// every module inherits the same guarantees. These exercise it as a module will
/// actually call it.
@Suite("Two-phase delete protocol")
struct ToolContextTests {
    private func context(
        session: String = "session-A",
        capabilities: Capabilities = .all,
        writes: Bool = true,
        auditURL: URL
    ) -> ToolContext {
        ToolContext(
            sessionID: session,
            capabilities: capabilities,
            config: Config(modules: ["reminders": .init(enabled: true, writes: writes)]),
            confirmTokens: ConfirmTokenStore(),
            audit: AuditLog(url: auditURL)
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "pippin ctx \(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "audit.jsonl")
    }

    @Test("without a token nothing is performed and a token is returned")
    func previewArmPerformsNothing() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)

        var performed = false
        let result = try await context.confirmDestructive(
            tool: "pippin_reminders_delete",
            module: "reminders",
            ids: ["R1", "R2"],
            confirmToken: nil,
            preview: { .object(["count": .int(2)]) },
            perform: { performed = true; return .object([:]) }
        )

        #expect(!performed)
        guard case .object(let fields) = result else {
            Issue.record("expected an object"); return
        }
        #expect(fields["confirmation_required"] == .bool(true))
        #expect(fields["preview"] == .object(["count": .int(2)]))
        if case .string(let token) = fields["confirm_token"] ?? .null {
            #expect(!token.isEmpty)
        } else {
            Issue.record("no confirm_token returned")
        }
        #expect(fields["expires_at"] != nil)
    }

    @Test("the returned token authorises exactly that delete")
    func confirmArmPerforms() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)
        let ids = ["R1", "R2"]

        let preview = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: nil,
            preview: { .object([:]) }, perform: { .object([:]) })
        guard case .object(let fields) = preview,
              case .string(let token) = fields["confirm_token"] ?? .null
        else { Issue.record("no token"); return }

        var performed = false
        _ = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: token,
            preview: { .object([:]) },
            perform: { performed = true; return .object(["deleted": .int(2)]) })

        #expect(performed)
    }

    @Test("a token cannot be replayed")
    func tokenIsSingleUse() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)
        let ids = ["R1"]

        let preview = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: nil,
            preview: { .object([:]) }, perform: { .object([:]) })
        guard case .object(let fields) = preview,
              case .string(let token) = fields["confirm_token"] ?? .null
        else { Issue.record("no token"); return }

        _ = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: token,
            preview: { .object([:]) }, perform: { .object([:]) })

        var performedTwice = false
        await #expect(throws: PippinError.self) {
            _ = try await context.confirmDestructive(
                tool: "t", module: "reminders", ids: ids, confirmToken: token,
                preview: { .object([:]) },
                perform: { performedTwice = true; return .object([:]) })
        }
        #expect(!performedTwice)
    }

    @Test("swapping the items after the preview does not delete them")
    func itemSwapIsRefused() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)

        let preview = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ["R1"], confirmToken: nil,
            preview: { .object([:]) }, perform: { .object([:]) })
        guard case .object(let fields) = preview,
              case .string(let token) = fields["confirm_token"] ?? .null
        else { Issue.record("no token"); return }

        // The attack: preview one harmless item, confirm a larger set.
        var performed = false
        await #expect(throws: PippinError.self) {
            _ = try await context.confirmDestructive(
                tool: "t", module: "reminders", ids: ["R1", "R2", "R3"], confirmToken: token,
                preview: { .object([:]) },
                perform: { performed = true; return .object([:]) })
        }
        #expect(!performed)
    }

    @Test("writes disabled blocks the protocol before any preview runs")
    func gateRunsFirst() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(writes: false, auditURL: url)

        var previewed = false
        let error = await #expect(throws: PippinError.self) {
            _ = try await context.confirmDestructive(
                tool: "t", module: "reminders", ids: ["R1"], confirmToken: nil,
                preview: { previewed = true; return .object([:]) },
                perform: { .object([:]) })
        }
        #expect(error?.code == .writesDisabled)
        // Not even the preview runs: a disabled module should not be touched.
        #expect(!previewed)
    }

    @Test("a read-only connection cannot reach the protocol at all")
    func readOnlyCapabilityRefused() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(capabilities: .readOnly, auditURL: url)

        let error = await #expect(throws: PippinError.self) {
            _ = try await context.confirmDestructive(
                tool: "t", module: "reminders", ids: ["R1"], confirmToken: nil,
                preview: { .object([:]) }, perform: { .object([:]) })
        }
        #expect(error?.code == .permissionDenied)
    }

    @Test("every arm of the protocol leaves an audit entry")
    func auditCoversEveryArm() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)
        let ids = ["R1"]

        let preview = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: nil,
            preview: { .object([:]) }, perform: { .object([:]) })
        guard case .object(let fields) = preview,
              case .string(let token) = fields["confirm_token"] ?? .null
        else { Issue.record("no token"); return }

        _ = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: token,
            preview: { .object([:]) }, perform: { .object([:]) })

        _ = try? await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ids, confirmToken: "bogus",
            preview: { .object([:]) }, perform: { .object([:]) })

        let outcomes = try await context.audit.entries().map(\.outcome)
        // preview (refused), delete (succeeded), bad token (refused)
        #expect(outcomes == [.refused, .succeeded, .refused])
    }

    @Test("a failing delete is recorded as failed, not silently dropped")
    func failureIsAudited() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let context = context(auditURL: url)

        let preview = try await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ["R1"], confirmToken: nil,
            preview: { .object([:]) }, perform: { .object([:]) })
        guard case .object(let fields) = preview,
              case .string(let token) = fields["confirm_token"] ?? .null
        else { Issue.record("no token"); return }

        _ = try? await context.confirmDestructive(
            tool: "t", module: "reminders", ids: ["R1"], confirmToken: token,
            preview: { .object([:]) },
            perform: { throw PippinError(.backendUnavailable, detail: "eventkit") })

        #expect(try await context.audit.entries().map(\.outcome) == [.refused, .failed])
    }

    @Test("the gate is derived from the context, never stored separately")
    func gateIsConsistent() {
        let url = temporaryURL()
        let context = context(capabilities: .readOnly, auditURL: url)
        #expect(throws: PippinError.self) { try context.gate.check(.write, module: "reminders") }
        #expect(throws: Never.self) { try context.gate.check(.read, module: "reminders") }
    }
}
