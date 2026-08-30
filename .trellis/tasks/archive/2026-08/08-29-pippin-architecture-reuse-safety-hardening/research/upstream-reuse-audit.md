# Research: upstream reuse and safety audit

- Query: Audit current Pippin against the exact `swift-sdk` 0.12.1 checkout, local `Refer/iMCP` commit `b84f266`, local `Refer/orbit-mcp` commit `8b37369`, and relevant primary upstream sources; decide what to keep, replace, or use only as reference for protocol hosting, app integrations, TCC, permissions, mutations, and audit safety.
- Scope: mixed (local source audit plus primary upstream repositories and vendor documentation)
- Date: 2026-08-29 (Asia/Singapore)

## Executive conclusion

The architecture should continue to use `modelcontextprotocol/swift-sdk` as the sole owner of MCP JSON-RPC decoding/dispatch, Streamable HTTP/SSE framing, protocol validation, and per-session transport state. Version 0.12.1 does **not** expose an importable socket-host adapter: its reusable `MCP` library stops at framework-neutral `HTTPRequest -> HTTPResponse`, while the NIO listener and multi-session `HTTPApp` live only in the `MCPConformanceServer` executable target. Pippin's NIO adapter is therefore justified in the short term, but it should stay minimal and should be proposed upstream as a reusable library product rather than becoming a second protocol implementation.

Orbit is not a protocol replacement. Its inspected checkout manually implements HTTP parsing, JSON-RPC dispatch, protocol-version negotiation, and session lifecycle, and the checkout contains no license file or license grant. It is useful as behavioral reference only; code must not be copied from it.

The immediate safety changes supported by evidence are:

1. Remove SQLite `immutable=1` before using `SQLiteReader` against a live Mail database.
2. Extend Pippin's AppleScript runner with orchard-style per-app serialization lanes, bounded queue wait, bounded output, and whole-process-group TERM-to-KILL cleanup.
3. Make the audit availability policy explicit. Recommended policy: fail open for preview/refusal records because no mutation occurs; fail closed before actual write/destructive operations if an `attempted` record cannot be durably appended; if the completion record fails after a mutation, report the mutation's real outcome plus an `audit_degraded` condition and latch unhealthy audit status rather than pretending the mutation did not occur.
4. Retain the stable signed app identity, resident shared state, bearer capability gating, one tool per verb, call-time visibility recheck, and two-phase destructive confirmation.

Only `pippin_status` is currently a production tool. Reminders and Mail code discussed below is future integration guidance, not an assertion that those production tools exist.

## Evidence labels

- **Direct evidence** means a fact observed in the inspected source, dependency lock, repository metadata, or vendor documentation.
- **Recommendation** means an architectural or safety conclusion derived from that evidence. Recommendations are not descriptions of current behavior.

## Inspected revisions, dates, and license constraints

| Source | Exact inspected revision / date | License or reuse constraint | Direct evidence |
|---|---|---|---|
| Current Pippin working tree | local HEAD `64d5fef79d36c18ddd895c781c9833dd8571413e`; committer timestamp 2026-08-29 01:46:51 +0800; working-tree contents inspected 2026-08-29 | No license conclusion was needed for Pippin's own code. This audit did not use Git operations or inspect dirty-state ownership. | `.git/HEAD`, `.git/refs/heads/feat/pippin-skeleton-transport`, local commit object metadata |
| `modelcontextprotocol/swift-sdk` | version `0.12.1`, revision [`a0ae212`](https://github.com/modelcontextprotocol/swift-sdk/commit/a0ae212ebf6eab5f754c3129608bc5557637e605), committed 2026-04-29 | [LICENSE at the inspected revision](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/LICENSE) describes an MIT-to-Apache-2.0 transition: new/relicensed code is Apache-2.0 and unrelicensed contributions remain MIT. Preserve applicable notices and verify provenance before copying nontrivial source. Depending on the published library is simpler than copying conformance-host code. | `Package.resolved:50-56`; checkout `.git/HEAD`; checkout `LICENSE:1-9` |
| `mattt/iMCP` local reference | [`b84f266`](https://github.com/mattt/iMCP/commit/b84f266a7649125a407feb3c303570f1798e04dc), committed 2026-05-07, message `Release 1.4.1` | [MIT](https://github.com/mattt/iMCP/blob/b84f266a7649125a407feb3c303570f1798e04dc/LICENSE.md); attribution/license notice required for copied substantial portions. Prefer behavior/reference over copying. | `Refer/iMCP/.git/refs/heads/main`; `Refer/iMCP/LICENSE.md:1-21` |
| `rusudinu/orbit-mcp` local reference | [`8b37369`](https://github.com/rusudinu/orbit-mcp/commit/8b373696d2f26fe50dae22eaa886415a873c128d), committed 2026-07-26 | **No license found** in the inspected checkout: no `LICENSE`, `LICENSE.md`, SPDX marker, or license grant. Public visibility is not permission to copy. Reference behavior only. | `Refer/orbit-mcp/.git/refs/heads/main`; repository-wide license search returned only incidental words, not a grant |
| `l22-io/orchard-mcp` primary GitHub source | [`0de0967`](https://github.com/l22-io/orchard-mcp/commit/0de0967a1d298286f0101aec230ea86aaada8404), committed 2026-06-19 | [MIT](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/LICENSE). Reimplement the safety contract in Swift; copying source would require preserving MIT notice. | GitHub repository/commit API and source at the pinned revision |
| `krmj22/macos-mcp` primary GitHub source | [`ab3922a`](https://github.com/krmj22/macos-mcp/commit/ab3922ae08f28699c9685d1bd6df3ff776b8d9db), committed 2026-08-20 | [MIT](https://github.com/krmj22/macos-mcp/blob/ab3922ae08f28699c9685d1bd6df3ff776b8d9db/LICENSE). Private Mail schema and hard-coded path are empirical reference, not a stable API contract. | GitHub repository/commit API and source at the pinned revision |
| `rex/mcp-apple-reminders` primary GitHub source | [`3c26918`](https://github.com/rex/mcp-apple-reminders/commit/3c26918641dee9235f34be281b926c8cd8fbce81), committed 2026-06-11 | [MIT](https://github.com/rex/mcp-apple-reminders/blob/3c26918641dee9235f34be281b926c8cd8fbce81/LICENSE), but its native EventKit helper separately records borrowed MIT code and its private ReminderKit helper has third-party notices. Public EventKit patterns are referenceable; private frameworks remain brittle and should not be adopted. | helper header and `docs/SECURITY-REVIEW.md` at pinned revision |
| `laststance/mac-mcp-server` primary GitHub source | repository now resolves to `ryota-murakami/mac-mcp-server`; [`10ee0a1`](https://github.com/ryota-murakami/mac-mcp-server/commit/10ee0a1b65def1ef8cf1d6255d90aebbd72), committed 2026-06-19 | GitHub repository metadata and README identify MIT. Its broad AppleScript/JXA tool surface is a comparison point only; it provides no reason to expose generic script execution in Pippin. | [repository](https://github.com/laststance/mac-mcp-server) primary page and commit metadata |

External “latest” revisions above are snapshots actually inspected on 2026-08-29, not floating recommendations to track `main`.

## Files found

### Current Pippin

- `Package.swift` — pins SDK 0.12.1 exactly, adds SwiftNIO only to `PippinServer`, and keeps `PippinCore` transport-independent.
- `Package.resolved` — resolves SDK 0.12.1 to `a0ae212...` and SwiftNIO 2.101.3 to `0b18836...`.
- `Sources/PippinServer/HTTPListener.swift` — loopback NIO socket adapter converting NIO messages to SDK HTTP types.
- `Sources/PippinServer/ServerHost.swift` — resident multi-session owner, bearer/session binding, official SDK server/transport composition, tool dispatch, and capability-aware tool visibility.
- `Sources/PippinServer/ProductionToolCatalogue.swift` — single production catalogue; currently contains only `StatusTool.definition`.
- `Sources/PippinServer/ToolRegistry.swift` — pure `(Config, Capabilities)` visibility projection with module/write filtering.
- `Sources/PippinShim/PippinShimRuntime.swift` — composes official SDK `StdioTransport` with the shim relay.
- `Sources/PippinShim/ShimRelay.swift` — raw-frame stdio-to-HTTP relay, bounded concurrent POSTs, session DELETE, and shutdown draining.
- `Sources/PippinCore/SQLiteReader.swift` — read-only SQLite wrapper currently adding `immutable=1`.
- `Sources/PippinCore/AppleScriptRunner.swift` — repository-script/argv boundary and timeout-driven child termination; currently lacks output cap and whole-process-group cleanup.
- `Sources/PippinCore/AuditLog.swift` — privacy-minimized JSONL mutation log; currently silently fail-open.
- `Sources/PippinCore/ToolContext.swift` and `ConfirmToken.swift` — centralized two-phase destructive protocol and exact, single-use, session-bound confirmation tokens.
- `Sources/PippinServer/SystemPermissionProvider.swift` and `PermissionActions.swift` — passive permission inspection separated from explicit user-initiated prompting/opening actions.
- `Sources/PippinApp/Runtime/ServerRuntime.swift` — resident host/listener lifecycle and endpoint publication.
- `Scripts/package_app.sh`, `Scripts/setup_dev_signing.sh`, and `version.env` — stable bundle/signing identity and hard refusal of ad-hoc fallback or silent certificate replacement.

### Exact SDK 0.12.1 checkout

- `.build/checkouts/swift-sdk/Package.swift` — public `MCP` library target excludes NIO; NIO belongs only to conformance executable target.
- `.build/checkouts/swift-sdk/Sources/MCP/Base/Transports/HTTPServer/StatefulHTTPServerTransport.swift` — official Streamable HTTP, SSE, session, validation, and resumability owner.
- `.build/checkouts/swift-sdk/Sources/MCP/Server/Server.swift` — official JSON-RPC decode, lifecycle, request dispatch, and handler registration owner.
- `.build/checkouts/swift-sdk/Sources/MCP/Base/Transports/StdioTransport.swift` — official stdio framing transport.
- `.build/checkouts/swift-sdk/Sources/MCP/Base/Transports/HTTPClientTransport.swift` — official Streamable HTTP client transport used by the shim.
- `.build/checkouts/swift-sdk/Sources/MCPConformance/Server/HTTPApp.swift` — NIO socket and multi-session example that is internal to an executable target, not an importable product.

### Local references

- `Refer/iMCP/App/Controllers/ServerController.swift` — official SDK over a custom Network transport plus per-client connection approval UI flow.
- `Refer/iMCP/App/Services/Reminders.swift` — direct EventKit reminders implementation and permission behavior.
- `Refer/iMCP/CLI/main.swift` — custom network-to-stdio bridge with nonstandard heartbeat handling; not a Streamable HTTP shim replacement.
- `Refer/orbit-mcp/Orbit MCP/MCPHTTPServer.swift` — manual HTTP parser/listener.
- `Refer/orbit-mcp/Orbit MCP/MCPRequestHandler.swift` — manual subset JSON-RPC/MCP/session implementation.
- `Refer/orbit-mcp/Orbit MCP/RemindersService.swift` — EventKit CRUD reference.
- `Refer/orbit-mcp/Orbit MCP/MailService.swift` — in-process `NSAppleScript` Mail implementation, including direct input interpolation and unbounded execution.
- `Refer/orbit-mcp/Orbit MCP/AppState.swift` and `MenuBarView.swift` — menu-bar lifecycle, permission onboarding, service switches, bearer token, and local endpoint UX reference.

## Direct findings

### 1. Official SDK owns protocol, SSE, and per-session transport state

- `StatefulHTTPServerTransport` explicitly implements Streamable HTTP session IDs, POST SSE responses, GET SSE, DELETE termination, and resumability (`StatefulHTTPServerTransport.swift:4-31`). It parses/classifies JSON-RPC and validates requests before routing them (`:163-243`), owns session creation and SSE continuation routing (`:246-309`), and handles GET resumability (`:312-340` and following).
- `Server` owns MCP lifecycle and JSON-RPC message decoding/dispatch rather than the socket adapter. Its receive loop decodes batches, responses, requests, and notifications and sends protocol errors (`Server.swift:223-267`).
- Pippin uses those owners directly: it creates one official `StatefulHTTPServerTransport` and `Server` per session (`Sources/PippinServer/ServerHost.swift:194-223`), registers official `ListTools` and `CallTool` handlers (`:235-254`), and delegates established requests to `transport.handleRequest` (`:140-159`).

**Conclusion (direct evidence):** Pippin is not reimplementing JSON-RPC/SSE inside its NIO adapter; those responsibilities remain in the official SDK.

### 2. SDK 0.12.1 exposes no importable socket-host adapter

- The package publishes one library, `MCP`, whose target dependencies do not include SwiftNIO (`.build/checkouts/swift-sdk/Package.swift:16-48`).
- NIOCore/NIOPosix/NIOHTTP1 appear only in `MCPConformanceServer`, an executable target (`:60-70`).
- The SDK's reusable transport documentation explicitly tells consumers to supply their own HTTP framework handler and convert its `HTTPRequest`/`HTTPResponse` values (`StatefulHTTPServerTransport.swift:21-31`).
- A NIO listener, socket bootstrap, multi-session table, and thin HTTP adapter do exist in `Sources/MCPConformance/Server/HTTPApp.swift:12-61,103-138,148-267,269-340`, but `HTTPApp` and its initializers are internal and the file belongs to the executable target.
- Pippin's `HTTPListener` performs the same missing role: bind loopback NIO, exact-path match, translate headers/body, delegate to `ServerHost`, and stream response chunks (`Sources/PippinServer/HTTPListener.swift:9-14,45-94,97-169,171-223`).

**Conclusion (direct evidence):** the official SDK owns JSON-RPC/SSE/session semantics but exposes no importable socket-host adapter in 0.12.1.

**Recommendation:** retain Pippin's adapter short-term, keep it limited to socket lifecycle and NIO↔SDK type conversion, and upstream a reusable host adapter/library proposal based on the SDK's conformance `HTTPApp`. Do not move auth/session/tool policy into `HTTPListener`, and do not fork the SDK's transport logic.

### 3. Pippin's stdio↔HTTP shim is correctly raw and SDK-backed

- `PippinShimRuntime` instantiates the SDK's `StdioTransport` (`Sources/PippinShim/PippinShimRuntime.swift:54-67`).
- `ShimRelay` instantiates the SDK's `HTTPClientTransport`, adds the bearer only as an HTTP header, and never constructs a typed SDK `Client` or decodes business JSON-RPC (`Sources/PippinShim/ShimRelay.swift:18-49`).
- It forwards the first two frames sequentially to preserve initialize/initialized ordering, then admits at most four HTTP POSTs (`:4-9,65-68,194-219,246-291`).
- It forwards response frames raw from the SDK HTTP transport to SDK stdio (`:222-244`), drains accepted requests for two seconds on stdin EOF, cancels remaining work, sends best-effort authenticated DELETE, and disconnects (`:98-157,174-191,334-355`).
- iMCP's CLI bridge is tied to its custom TCP discovery/heartbeat protocol (`Refer/iMCP/CLI/main.swift:324-434,493-561`), so it is not a drop-in Streamable HTTP shim.

**Recommendation:** keep the shim. Reuse official transport primitives, preserve raw `Data`, process-local token/session state, initialize ordering, bounded concurrency, drain timeout, and DELETE cleanup. Do not replace it with iMCP's network CLI or a typed client/server proxy.

### 4. Orbit is not a protocol replacement

- Orbit calls itself a “Minimal MCP server” and imports only Foundation and Network in its listener (`Refer/orbit-mcp/Orbit MCP/MCPHTTPServer.swift:1-13`). It implements an HTTP request parser, buffering limits, socket loop, CORS/origin checks, auth, and responses itself (`:25-31,43-169,200-260` and following).
- Its request handler explicitly implements only “a small slice” of MCP and manually tracks phases, protocol versions, sessions, JSON parsing, and error responses (`Refer/orbit-mcp/Orbit MCP/MCPRequestHandler.swift:1-15,16-54,56-74,84-163`).
- No SDK package dependency is present in the Xcode project. Its protocol code would duplicate and narrow the official SDK contract.
- The checkout has no license grant.

**Recommendation:** do not copy or import Orbit's protocol layer. Use it only to compare product behavior such as local-only binding, service toggles, token UX, EventKit operations, and menu-bar lifecycle.

### 5. Stable signed app and resident state are load-bearing

- Pippin fixes bundle ID `io.github.is52hertz.pippin` and signing identity `Pippin Local Signing`; comments explain TCC is keyed to that identity (`version.env:1-11`).
- Packaging refuses ad-hoc signing because it would silently invalidate TCC grants and signs both shim and app with the resolved stable identity (`Scripts/package_app.sh:3-10,25-51,107-122`).
- Signing setup refuses replacement and has no force path; private key material is temporary and wiped (`Scripts/setup_dev_signing.sh:3-19,45-64`).
- `ServerRuntime` owns one resident `ServerHost` and listener, publishes endpoint metadata only after the listener is ready, and tears all state down together (`Sources/PippinApp/Runtime/ServerRuntime.swift:26-35,57-95,130-142`).
- `ServerHost` shares one confirmation-token store, audit log, and AppleScript runner across sessions while keeping official SDK server/transport and resolved capabilities per session (`Sources/PippinServer/ServerHost.swift:6-15,36-65`).

**Recommendation:** keep the stable signed app, long-lived certificate/bundle ID, and resident shared-state model. A per-client subprocess architecture would fragment TCC identity/state and weaken replay/audit guarantees.

### 6. Capability gating, tool-per-verb, and two-phase destructive confirmation should stay

- Sessions bind both the bearer token and capabilities that opened them; switching tokens on an existing session fails (`Sources/PippinServer/ServerHost.swift:36-45,131-177`).
- `ToolRegistry` derives visibility from capability, module enablement, and module write setting, hiding unavailable tools rather than advertising refusals (`Sources/PippinServer/ToolRegistry.swift:20-30,38-65`).
- `ServerHost.call` rechecks visibility at call time to defeat stale cached tool lists (`Sources/PippinServer/ServerHost.swift:277-315`).
- `ConfirmTokenStore` limits destructive calls to 50 unique explicit IDs, binds tokens to exact ID set, tool and session, expires them after 120 seconds, and consumes them once (`Sources/PippinCore/ConfirmToken.swift:4-13,27-33,44-67,70-125`).
- `ToolContext.confirmDestructive` centralizes preview/no-mutation, token issuance, consumption, perform, and audit outcomes (`Sources/PippinCore/ToolContext.swift:50-97`).
- Orbit's single `allowDestructive` toggle hides/rejects a class of tools but directly executes delete once enabled (`Refer/orbit-mcp/Orbit MCP/MCPRequestHandler.swift:330-340,437-442,636-641`); it has no equivalent exact-item, single-use confirmation.
- `rex/mcp-apple-reminders` uses MCP elicitation on cascading deletes and logs destructive operations, but its own audit says protection depends on client support and stdio trust ([security review lines 55-96 and 115-122](https://github.com/rex/mcp-apple-reminders/blob/3c26918641dee9235f34be281b926c8cd8fbce81/docs/SECURITY-REVIEW.md#L55-L122)). Pippin's two-call token protocol is client-agnostic and stronger for the intended client set.

**Recommendation:** keep capability-based absence, call-time recheck, one tool per verb, and two-phase confirmation. Do not collapse verbs into a generic action tool, replace exact-ID confirmation with `confirm: true`, or depend solely on MCP elicitation.

### 7. Only `pippin_status` is currently production

- `ProductionToolCatalogue.definitions` contains exactly one entry, `StatusTool.definition` (`Sources/PippinServer/ProductionToolCatalogue.swift:1-11`).
- `ServerHost.call` has only `StatusTool.name` plus the not-found default (`Sources/PippinServer/ServerHost.swift:294-315`).
- `StatusTool.name` is `pippin_status` (`Sources/PippinServer/StatusTool.swift:52-61`).
- `Sources/PippinModules/PippinModules.swift` contains only the module namespace; no production Reminders or Mail tool is registered.

**Direct finding:** `pippin_status` is the only production tool at the inspected revision.

### 8. Remove `immutable=1` for live Mail databases

- Current `SQLiteReader` constructs `file:<path>?immutable=1` while also using `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI` (`Sources/PippinCore/SQLiteReader.swift:22-30`).
- SQLite's official URI documentation says `immutable=1` tells SQLite the file cannot change, disables locking and change detection, and may yield incorrect results or `SQLITE_CORRUPT` if the file changes: [SQLite URI filename documentation](https://www.sqlite.org/uri.html#recognized_query_parameters).
- Mail owns and actively modifies Envelope Index and may use WAL. Therefore the “immutable” assertion is false for the target workload; read-only intent is already expressed by `SQLITE_OPEN_READONLY`.
- The project spec already records this as a known limitation and forbids propagation to actively modified stores (`.trellis/spec/backend/database-guidelines.md:19-31`).
- `krmj22/macos-mcp` is useful only as empirical schema/backend evidence: it runs `/usr/bin/sqlite3 -readonly` with timeout and output cap, but hard-codes `V10` and interpolates escaped SQL ([`sqliteMailReader.ts:23-30,42-69,118-125,231-276`](https://github.com/krmj22/macos-mcp/blob/ab3922ae08f28699c9685d1bd6df3ff776b8d9db/src/utils/sqliteMailReader.ts#L23-L276)). Those two practices are weaker than Pippin's runtime version resolution and bound parameters.

**Recommendation:** remove `immutable=1`; retain `SQLITE_OPEN_READONLY` (optionally a correctly escaped `mode=ro` URI if URI options remain), runtime `V*` resolution, schema probe, serialized reader queue, bound values, terminal-step checking, explicit degraded fallback, and integration tests while Mail writes to a WAL-backed store. Never copy the hard-coded `V10` path or string-built SQL.

### 9. Reminders should use resident EventKit, with references used selectively

- Apple states `EKEventStore` is the supported access path and full access is required to read reminders: [Apple “Accessing the event store”](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).
- iMCP keeps a shared `EKEventStore`, checks `.fullAccess`, uses predicates/fetch callbacks for reads, and saves with EventKit (`Refer/iMCP/App/Services/Reminders.swift:8-20,23-57,94-193,196-299`). This is a useful native Swift baseline.
- Orbit also uses direct EventKit CRUD and does not need an external helper (`Refer/orbit-mcp/Orbit MCP/RemindersService.swift:31-51,176-216`), but its unlicensed code is reference-only.
- `rex/mcp-apple-reminders` demonstrates rich date, recurrence, alarm, and identifier handling in an EventKit helper and records exact borrowed-source attribution ([`rem_eventkit.swift:1-23,26-48,104-147,152-193,215-227`](https://github.com/rex/mcp-apple-reminders/blob/3c26918641dee9235f34be281b926c8cd8fbce81/src/mcp_apple_reminders/_native/src/rem_eventkit.swift#L1-L227)). Its private ReminderKit tier is explicitly subject to macOS breakage and should not be adopted.

**Recommendation:** implement Reminders directly in Pippin's signed resident process with one shared EventKit owner, public APIs only, passive status separate from explicit access request, bounded date/result scopes, and tool-per-verb safety. Use iMCP/orchard/rex/Orbit to build test cases and data-shape coverage, not as protocol or source-code dependencies.

### 10. AppleScript execution needs orchard-style isolation while preserving Pippin's injection boundary

- Pippin passes untrusted values as `osascript` argv and repository-authored script through stdin, preventing caller values from changing script structure (`Sources/PippinCore/AppleScriptRunner.swift:3-17,30-52,64-73`).
- It applies a 15-second watchdog and TERM-to-KILL escalation to the direct child (`:19-22,75-106`), bounds arbitrary stderr in errors to 200 characters (`:135-165`), and drains stdout/stderr concurrently.
- Missing controls: no maximum stdout/stderr bytes, no per-app serialization/queue timeout, and `kill(process.processIdentifier, SIGKILL)` targets only the immediate child, not any descendants (`:98-103,108-132`).
- Orbit is a negative example: Mail fields are escaped then interpolated into script text (`Refer/orbit-mcp/Orbit MCP/MailService.swift:255-303`), and `NSAppleScript.executeAndReturnError` runs in-process with no enforceable timeout (`:360-386`).
- orchard assigns every operation a named app lane, operation timeout, queue timeout, and output-byte budget ([`src/safety.ts:3-28,29-128`](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/src/safety.ts#L3-L128)); it serializes each lane and rejects waiters whose queue budget expires ([`:149-226`](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/src/safety.ts#L149-L226)).
- orchard starts the bridge detached, kills the negative PID to signal the whole process group, escalates TERM to KILL even if the parent exits first, and terminates on output overflow ([`src/bridge.ts:56-77,128-217`](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/src/bridge.ts#L56-L217)). Its safety audit requires broad scopes to be refused before host-app work starts ([`docs/app-safety-audit.md:3-26`](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/docs/app-safety-audit.md#L3-L26)).

**Recommendation:** preserve Pippin's stdin-script/argv-value boundary and error mapping, then add:

1. One lane per target app (`mail`, `notes`, etc.), not one global lane, so unrelated apps can progress while calls to the same Apple Events target cannot interleave.
2. A short bounded queue wait that refuses work before touching an already-busy app.
3. Per-operation execution timeout and stdout/stderr byte caps; stop reading and kill the process group on overflow.
4. A new child process group and TERM→grace→KILL of the entire group, with escalation surviving immediate parent exit so `osascript` descendants cannot remain orphaned.
5. Scope validation before lane acquisition/process creation and bounded response projection after parsing.

This can be implemented with Darwin/Foundation primitives already available; no new dependency is justified by the evidence.

### 11. Permission UX should stay passive-by-default and user initiated

- Passive status uses `EKEventStore.authorizationStatus`, checks whether Mail is already running, calls `AEDeterminePermissionToAutomateTarget(..., askUserIfNeeded: false)`, and performs a narrow effective Mail-directory read probe (`Sources/PippinServer/SystemPermissionProvider.swift:7-37,39-89,92-120`).
- Prompting/opening actions are a separate protocol and are reachable only through explicit app actions (`Sources/PippinServer/PermissionActions.swift:6-22,61-76`). Reminders requests full access only on the explicit action (`:98-109`); Mail Automation asks only in the explicit action and off the caller actor (`:133-149`).
- Apple documents `authorizationStatus(for:)` for state and `requestFullAccessToReminders` for prompting: [EventKit authorization documentation](https://developer.apple.com/documentation/eventkit/ekauthorizationstatus).
- iMCP's approval window is useful UX reference for explaining access and explicit allow/deny (`Refer/iMCP/App/Views/ConnectionApprovalView.swift:4-60`), while Pippin's capability token is the stronger authorization primitive.
- Orbit's menu-bar flow deliberately explains permissions before prompting (`Refer/orbit-mcp/Orbit MCP/AppState.swift:201-210`) and separates Mail send opt-in, but its bearer token is persisted and displayed in generated config (`:95-114,225-242`), unlike Pippin's stricter ephemeral endpoint-token handling.

**Recommendation:** keep passive status incapable of prompting or launching apps, retain state-specific user-initiated actions and honest “Mail Data” effective-access wording, and retain the stable signed app as the TCC subject. Use iMCP/Orbit only for interaction-copy and onboarding-flow ideas.

### 12. Audit logging policy is currently implicit fail-open and must be explicit

- `AuditLog.record` returns `Void`; JSON encoding, directory creation, rotation, file creation, open, seek, and write failures are swallowed (`Sources/PippinCore/AuditLog.swift:55-76,78-101`).
- The current comment explicitly chooses availability over logging (`:97-100`). This is a **direct finding**: current mutation auditing is fail-open.
- Audit entries avoid argument values by hashing arguments, but store explicit IDs, tool/module, outcome, and an error projection; file/directory modes are 0600/0700 and size rotates at 5 MiB (`:17-32,46-53,63-96,104-116`).
- `ToolContext.confirmDestructive` records preview/refusal after minting, and records success/failure only after `perform`; it has no pre-mutation durable attempt record (`Sources/PippinCore/ToolContext.swift:64-95`).

**Recommendation — explicit policy:**

- Preview/refusal/no-mutation events: fail open, return the intended response, and expose audit degradation through resident status/operational logging without including private arguments.
- Actual write and destructive execution: append a durable `attempted` record before calling `perform`; if that append cannot be completed, fail closed and do not mutate.
- Completion append after mutation: the operation cannot truthfully be rolled back merely because logging failed. Return/record the real mutation outcome plus `audit_degraded`, latch audit health as degraded, and block subsequent mutations until the sink recovers or the user explicitly changes policy.
- Make `record` throwing (or return a typed result), define rotation/write atomicity and durability expectations, and test disk-full, permission, rotation, and post-mutation append failures.
- Do not put bearer/confirmation tokens, request bodies, AppleScript output, SQLite rows, mail/reminder content, or raw argument values in the log.

This policy is a recommendation, not current behavior. If product requirements choose full fail-open availability instead, that choice must be explicit in configuration/spec and surfaced in status; silent swallowing must not remain the policy mechanism.

## Keep / Replace / Reference matrix

| Area | Decision | Keep | Replace / minimize | Reference only | Evidence-based rationale |
|---|---|---|---|---|---|
| MCP protocol | **Keep** | Exact official `swift-sdk` 0.12.1 for JSON-RPC, lifecycle, methods, validation, SSE, and session transport | Remove/avoid any manual JSON-RPC or MCP subset implementation | Orbit protocol handler; iMCP's older/custom network transport | SDK already owns protocol correctness; Orbit duplicates only a subset and is unlicensed. |
| HTTP listener / session hosting | **Keep + minimize/upstream** | SDK `StatefulHTTPServerTransport` per session and Pippin `ServerHost` for bearer-bound multi-session resident state | Keep `HTTPListener` as thin NIO adapter only; upstream an importable SDK host adapter and delete local overlap if one lands | SDK conformance `HTTPApp` structure; Orbit local parser only for negative comparison | SDK library has no socket host, while conformance executable proves the missing adapter shape. |
| stdio↔HTTP shim | **Keep** | SDK `StdioTransport` + `HTTPClientTransport`, raw frame relay, initialize ordering, four-POST cap, two-second drain, DELETE | Avoid typed SDK Client/Server proxy and custom protocol decode | iMCP CLI for lifecycle test ideas only | Current relay preserves unknown tools/messages and delegates framing to official transports. |
| TCC / signing | **Keep** | Stable bundle ID/certificate, signed resident app, hard failure without identity, no ad-hoc fallback | Do not rotate/regenerate identity or validate TCC behavior through bare `swift run` | orchard app-bundle fallback and iMCP/Orbit app packaging as operational references | TCC grants follow code identity; per-run identity churn silently invalidates permissions. |
| Reminders | **Reference, then implement natively** | Public EventKit in Pippin resident app, shared store/owner, explicit access request | No private ReminderKit, subprocess identity, or copied unlicensed Orbit code | iMCP EventKit flow; orchard bounds; rex edge cases/attribution; Orbit behavior | Public EventKit is the supported API and matches Pippin's stable TCC subject. |
| Mail | **Replace unsafe SQLite flag; reference backends** | Runtime version resolution, read-only open, schema probe, bound parameters, explicit degraded fallback | Remove `immutable=1`; do not hard-code `V10`; do not copy interpolated SQL or broad AppleScript scans | krmj22 schema/Gmail labels; orchard scopes/locators/lanes; Orbit product verbs | Live Mail DB changes make immutable false; official SQLite warns of wrong results/corruption. |
| AppleScript execution | **Keep boundary, replace runtime hardening** | Repository-authored script via stdin, untrusted argv, timeout, structured errors | Add per-app lane, queue timeout, output caps, process-group TERM→KILL; avoid in-process `NSAppleScript` | orchard safety implementation; krmj22/laststance error/permission cases; Orbit as negative example | Current immediate-child kill and unbounded output leave orphan/resource risks. |
| Permission UX | **Keep** | Passive non-prompting provider, explicit user action performer, state-specific recovery, honest Mail Data probe | Do not prompt/launch from status or infer global FDA; do not expose tokens in status/UI | iMCP approval window; Orbit rationale-first menu flow | Existing separation makes automated/status calls side-effect free. |
| Destructive writes | **Keep** | Capability-gated absence, call-time recheck, tool-per-verb, exact-ID two-phase confirmation, single use/session/tool/TTL binding | Do not use generic action tool, one global destructive Boolean, `confirm: true`, or client-dependent elicitation alone | rex elicitation and logging; Orbit toggle as weaker comparison | Pippin's independent layers survive stale tool lists and cross-client confirmation gaps. |
| Audit logging | **Replace implicit semantics** | Privacy-minimized JSONL fields, permissions, bounded rotation, shared resident owner | Replace swallowed `Void` failures with explicit typed policy; fail closed before real mutations, surface post-mutation audit degradation | rex MCP logging as supplementary UX only, not durable local audit | Current code is silently fail-open and records no durable pre-mutation attempt. |

## Related specs

- `.trellis/spec/backend/security-and-transport.md` — loopback/auth/session validation, capability filtering, two-phase destructive protocol, thin adapter boundary.
- `.trellis/spec/backend/database-guidelines.md` — private live SQLite rules and existing `immutable=1` limitation.
- `.trellis/spec/backend/logging-guidelines.md` — operational-log privacy exclusions; distinct from durable mutation audit semantics.
- `.trellis/spec/backend/error-handling.md` — actionable backend/permission failures and bounded arbitrary diagnostics.
- `.trellis/spec/backend/directory-structure.md` — core/module/server/app ownership boundaries.
- `.trellis/spec/backend/quality-guidelines.md` — strict concurrency and required safety-path tests.
- `.trellis/spec/guides/code-reuse-thinking-guide.md` — single production catalogue, visibility owner, and confirmation owner.
- `.trellis/spec/guides/cross-layer-thinking-guide.md` — end-to-end transport, settings, private-store, and safety flow.
- `.trellis/spec/frontend/state-management.md` and `presentation-guidelines.md` — resident source of truth and permission/status presentation boundaries.

## External references

- [swift-sdk 0.12.1 commit](https://github.com/modelcontextprotocol/swift-sdk/commit/a0ae212ebf6eab5f754c3129608bc5557637e605)
- [swift-sdk 0.12.1 package target graph](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/Package.swift)
- [swift-sdk stateful HTTP server transport](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/Sources/MCP/Base/Transports/HTTPServer/StatefulHTTPServerTransport.swift)
- [swift-sdk conformance-only NIO `HTTPApp`](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/Sources/MCPConformance/Server/HTTPApp.swift)
- [SQLite URI `immutable` semantics](https://www.sqlite.org/uri.html#recognized_query_parameters)
- [SQLite read-only WAL guidance](https://www.sqlite.org/wal.html#read_only_databases)
- [Apple EventKit event-store access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Apple `EKAuthorizationStatus`](https://developer.apple.com/documentation/eventkit/ekauthorizationstatus)
- [Apple `AEDeterminePermissionToAutomateTarget`](https://developer.apple.com/documentation/coreservices/1444540-aedeterminepermissiontoautomatetar)
- [iMCP inspected commit](https://github.com/mattt/iMCP/tree/b84f266a7649125a407feb3c303570f1798e04dc)
- [Orbit inspected commit](https://github.com/rusudinu/orbit-mcp/tree/8b373696d2f26fe50dae22eaa886415a873c128d)
- [orchard safety profiles/lanes](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/src/safety.ts)
- [orchard bridge process cleanup](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/src/bridge.ts)
- [orchard app safety audit](https://github.com/l22-io/orchard-mcp/blob/0de0967a1d298286f0101aec230ea86aaada8404/docs/app-safety-audit.md)
- [krmj22 Mail SQLite reader](https://github.com/krmj22/macos-mcp/blob/ab3922ae08f28699c9685d1bd6df3ff776b8d9db/src/utils/sqliteMailReader.ts)
- [krmj22 JXA/AppleScript executor](https://github.com/krmj22/macos-mcp/blob/ab3922ae08f28699c9685d1bd6df3ff776b8d9db/src/utils/jxaExecutor.ts)
- [rex EventKit helper](https://github.com/rex/mcp-apple-reminders/blob/3c26918641dee9235f34be281b926c8cd8fbce81/src/mcp_apple_reminders/_native/src/rem_eventkit.swift)
- [rex security review](https://github.com/rex/mcp-apple-reminders/blob/3c26918641dee9235f34be281b926c8cd8fbce81/docs/SECURITY-REVIEW.md)
- [laststance/mac-mcp-server repository](https://github.com/laststance/mac-mcp-server)

## Caveats / Not Found

- No license file or license grant was found in local `Refer/orbit-mcp` at `8b373696...`; treat all Orbit code as all-rights-reserved for reuse purposes unless the owner adds a license.
- SDK license text describes a transition rather than one uniform license for every historical contribution. This audit does not provide legal advice; dependency use is lower-friction than copying conformance source, and copied code needs provenance/notice review.
- Mail's Envelope Index schema is private and undocumented. The external repositories provide observations, not a compatibility promise. Schema probes, OS-version integration tests, and a truthful degraded fallback remain mandatory.
- `krmj22/macos-mcp` hard-codes `V10` and interpolates escaped SQL; those are specifically **not** recommended patterns.
- `rex/mcp-apple-reminders` includes private ReminderKit behavior and borrowed native source with separate notices; only public EventKit behavior should influence Pippin.
- The `laststance/mac-mcp-server` owner URL redirects to `ryota-murakami/mac-mcp-server`; it was inspected only for broad product/permission/AppleScript comparison because orchard supplied the stronger process-safety evidence.
- The research subtask itself modified only this research file. Planning
  integration into PRD/design/implement and parent/child ordering was performed
  separately by the main session; `Refer/` remained untouched.
