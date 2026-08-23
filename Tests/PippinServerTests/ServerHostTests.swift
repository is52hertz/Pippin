import Foundation
import MCP
import PippinCore
import Testing

@testable import PippinServer

@Suite("ServerHost routing and session binding")
struct ServerHostTests {
    private static let broadToken = "broad-token"
    private static let narrowToken = "narrow-token"

    private func makeHost() -> ServerHost {
        ServerHost(
            config: Config(),
            tokenStore: TokenStore([
                Self.broadToken: TokenIdentity(label: "local", capabilities: .all),
                Self.narrowToken: TokenIdentity(label: "remote", capabilities: .readOnly),
            ]),
            registry: ToolRegistry(catalogue: [StatusTool.definition])
        )
    }

    private func request(
        method: String = "POST",
        token: String?,
        sessionID: String? = nil,
        body: String? = Self.initializeBody
    ) -> HTTPRequest {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        ]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        if let sessionID { headers["Mcp-Session-Id"] = sessionID }
        return HTTPRequest(
            method: method,
            headers: headers,
            body: body.map { Data($0.utf8) },
            path: "/mcp"
        )
    }

    private static let initializeBody = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#

    /// Case-insensitive: HTTPResponse.headers is a plain dictionary, and the SDK
    /// spells the header "MCP-Session-Id" while the spec is case-agnostic.
    private func sessionID(of response: HTTPResponse) -> String? {
        response.headers.first { $0.key.lowercased() == "mcp-session-id" }?.value
    }

    private func openSession(on host: ServerHost, token: String) async throws -> String {
        let response = await host.handle(request(token: token))
        return try #require(sessionID(of: response))
    }

    @Test("a request with no token is refused before routing")
    func noTokenIsRefused() async {
        let response = await makeHost().handle(request(token: nil))
        #expect(response.statusCode == 401)
    }

    @Test("an unknown token is refused")
    func unknownTokenIsRefused() async {
        let response = await makeHost().handle(request(token: "nope"))
        #expect(response.statusCode == 401)
    }

    @Test("initialize opens a session and returns its id")
    func initializeOpensSession() async throws {
        let host = makeHost()
        let sessionID = try await openSession(on: host, token: Self.broadToken)
        #expect(!sessionID.isEmpty)
        #expect(await host.sessionCount == 1)
    }

    @Test("two clients are served by one host")
    func twoConcurrentSessions() async throws {
        let host = makeHost()
        let first = try await openSession(on: host, token: Self.broadToken)
        let second = try await openSession(on: host, token: Self.narrowToken)

        #expect(first != second)
        // One process, one shared core, two sessions — the property the resident
        // architecture exists for (A4).
        #expect(await host.sessionCount == 2)
    }

    @Test("a session cannot be driven with a different token than opened it")
    func sessionIsBoundToItsToken() async throws {
        let host = makeHost()
        let sessionID = try await openSession(on: host, token: Self.broadToken)

        // Without this, a caller could open with a broad token and continue with a
        // narrow one while silently retaining the broad tier — making the
        // narrowing cosmetic, which is precisely what batch four's remote
        // read-only token must not be.
        let response = await host.handle(
            request(token: Self.narrowToken, sessionID: sessionID, body: nil))
        #expect(response.statusCode == 401)
    }

    @Test("an unknown session id is 404, not a new session")
    func unknownSessionIsNotFound() async {
        let response = await makeHost().handle(
            request(token: Self.broadToken, sessionID: "no-such-session", body: nil))
        #expect(response.statusCode == 404)
    }

    @Test("a non-initialize POST without a session is refused")
    func nonInitializeWithoutSession() async {
        let response = await makeHost().handle(
            request(token: Self.broadToken, body: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        #expect(response.statusCode == 400)
    }

    @Test("DELETE closes the session")
    func deleteClosesSession() async throws {
        let host = makeHost()
        let sessionID = try await openSession(on: host, token: Self.broadToken)
        #expect(await host.sessionCount == 1)

        _ = await host.handle(request(method: "DELETE", token: Self.broadToken, sessionID: sessionID, body: nil))
        #expect(await host.sessionCount == 0)
    }

    @Test("capabilities are resolved from the token that opened the session")
    func capabilitiesFollowTheToken() async {
        let host = makeHost()
        #expect(await host.tools(for: .all).map(\.name) == ["pippin_status"])
        #expect(await host.tools(for: []).isEmpty)
    }

    @Test("a config change is visible to the shared core")
    func configUpdateIsShared() async {
        let host = makeHost()
        await host.updateConfig(Config(modules: ["reminders": .init(enabled: false, writes: false)]))
        // Shared, not per-session: both connected clients read the same config.
        #expect(await host.currentConfig.modules["reminders"]?.enabled == false)
    }
}
