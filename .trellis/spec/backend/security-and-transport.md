# Security and Transport

## Scenario: Local MCP Request and Destructive Tool Call

### 1. Scope / Trigger

The service is local but still handles untrusted MCP requests and tool arguments.
Preserve every independent guard; do not rely on an earlier layer having run.

This contract applies when changing `HTTPListener`, `ServerHost`, `ToolRegistry`,
`ToolContext`, bearer capabilities, session handling, or a destructive tool.

### 2. Signatures

- `HTTPListener.start() async throws -> Int` binds and returns the actual port.
- `ServerHost.handle(_ request: HTTPRequest) async -> HTTPResponse` owns
  authentication and session routing.
- `ToolRegistry.tools(config:capabilities:) -> [Tool]` derives the visible tool
  surface by absence.
- `ToolContext.confirmDestructive(tool:module:ids:confirmToken:preview:perform:)`
  owns both arms of the delete protocol.

### 3. Contracts

- `Config.validate` and `HTTPListener.start` both enforce literal IPv4/IPv6
  loopback with `Config.isLoopback`; hostnames and non-loopback binds are invalid.
- `ServerHost.handle` authenticates the bearer token before session lookup.
  `validationPipeline` then applies bearer, Origin, Accept, Content-Type,
  protocol-version, and session validators in that order.
- A session remains bound to the token and capabilities that opened it.
  `ToolRegistry.tools` filters by capability, module enablement, and write gate;
  `ServerHost.call` re-checks visibility to reject stale cached tool lists.
- `ConfirmTokenStore` binds destructive confirmation to tool, session, exact ID
  set, expiry, and single use. `ToolContext.confirmDestructive` centralizes the
  preview/consume/audit sequence and caps explicit unique IDs at 50.
- `AppleScriptRunner` accepts repository-authored script text only. Untrusted
  values travel through `on run argv` process arguments; every run has a timeout
  and uses a killable `/usr/bin/osascript` subprocess.
- `SQLiteReader.query` binds values and accepts only repository-authored SQL.

The published endpoint is private mode `0600`. Bearer and confirmation tokens
may exist in memory where their transport protocol requires them, but they must
never appear in logs, errors, status tools, UI, or audit records.

### 4. Validation and Error Matrix

| Condition | Required result |
|---|---|
| Missing or unknown bearer token | HTTP `401` before routing |
| Non-loopback `Origin` | HTTP `403` |
| Non-loopback bind configuration | startup/configuration error |
| Unknown or closed MCP session | protocol-appropriate not-found response |
| Tool hidden by module/capability gates | absent from `tools/list`; stale call rejected |
| Destructive call without token | no mutation; preview plus `confirmation_required` |
| Expired, replayed, wrong-session, wrong-tool, or changed-ID token | `confirmation_invalid`; no mutation |

### 5. Good / Base / Bad Cases

- Good: a full-capability local token sees enabled write tools; a matching
  single-use confirmation token authorizes exactly the previewed IDs.
- Base: a read-only token sees only read tools, and a module with writes off
  contributes no mutating tools.
- Bad: a client reuses another session's token, changes the ID set after preview,
  or calls a tool cached before it was disabled; every case must fail closed.

### 6. Tests Required

- `Tests/PippinServerTests/ServerHostTests.swift`: authentication, Origin,
  session binding, stale calls, concurrent clients, and DELETE lifecycle.
- `Tests/PippinServerTests/ToolRegistryTests.swift`: module/write/capability
  visibility and deterministic ordering.
- `Tests/PippinCoreTests/ConfirmTokenTests.swift` and
  `ToolContextTests.swift`: TTL, single use, exact ID set, tool/session binding,
  no-mutation preview, and audit outcomes.
- Re-run `ToolSurfaceBudgetTests` whenever production tools change.

### 7. Wrong vs Correct

Wrong: expose every tool and return `writes_disabled` only after the agent calls
it, or accept `confirm: true` as deletion authorization.

Correct: remove unavailable tools in `ToolRegistry`, re-check visibility in
`ServerHost.call`, and route every destructive operation through
`ToolContext.confirmDestructive`.

## Adapter Boundary

`HTTPListener` is an adapter: exact-path matching, repeated-header joining, SSE
chunk flushing, and NIO event-loop writes stay there; authentication, session
routing, and tool decisions stay in `ServerHost`. HTTP serving must not hop onto
the SwiftUI main actor.

## Avoid

- Never widen the listener to `0.0.0.0`, a hostname, or LAN interfaces.
- Never interpolate caller input into AppleScript or SQL.
- Never authorize a destructive action by a Boolean flag or reusable token.
- Never expose a disabled tool and rely only on execution-time refusal.
- Never publish endpoint metadata before the listener is accepting connections.
