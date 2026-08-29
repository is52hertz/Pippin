# Architecture Reuse and Safety Hardening — Technical Design

## 1. Decision Summary

| Area | Decision |
|---|---|
| MCP types, JSON-RPC, SSE, session protocol | Keep official swift-sdk |
| NIO socket host | Keep as a thin temporary adapter; make upstream replacement easy |
| stdio ↔ HTTP shim | Keep Pippin lifecycle relay over SDK transports |
| Stable `.app`, TCC identity, resident state | Keep; this is Pippin's product boundary |
| SQLite private-store reader | Keep abstraction; replace `immutable=1` opening policy |
| AppleScript runner | Keep injection-safe core; add orchard-style execution budgets |
| Destructive confirmation and capability gating | Keep Pippin implementation |
| Audit JSONL | Refine into a durable pre-mutation operation journal |
| Reminders/Mail recipes and tests | Port/reference licensed behavior, not upstream architecture |

The evidence and source links behind this table live in
`research/upstream-reuse-audit.md`.

## 2. Ownership Boundary

```text
NIO socket/framing adapter
  → swift-sdk StatefulHTTPServerTransport + Server
    → Pippin ServerHost policy/session table
      → ToolRegistry + ToolContext + module backend
```

The SDK owns the MCP wire contract. `HTTPListener` only binds loopback, converts
NIO requests, streams SDK response chunks, and closes connections. `ServerHost`
owns product policy: token identity/capabilities, one resident shared state,
visible tools, and per-client server instances.

The shim remains because swift-sdk exposes `StdioTransport` and
`HTTPClientTransport` but no transparent proxy. `ShimRelay` may supervise and
convert transport framing, but it must not decode business payloads or acquire
TCC state.

## 3. HTTP Adapter Reduction

- Frozen upstream: swift-sdk tag `0.12.1`, commit
  `a0ae212ebf6eab5f754c3129608bc5557637e605`.
- Add a source-provenance comment naming that tag/commit and the retained
  deviations.
- The package exposes only the `MCP` library. Its NIO `HTTPApp` is part of the
  non-importable `MCPConformanceServer` executable, so the multi-session socket
  host cannot be replaced by a public 0.12.1 API.
- Keep one minimal routing-only JSON peek equivalent to the conformance host's
  package-scoped `JSONRPCMessageKind`: require an object with a string method
  equal to `Initialize.name` and a string/integer request ID. Do not decode
  `Request<Initialize>` here; stricter parameter validation would change how a
  malformed initialize reaches the SDK transport. The body remains unchanged,
  and the transport owns all protocol validation and error responses.
- Align session cleanup with upstream: close/remove on DELETE only after the SDK
  transport returns HTTP 200.
- Do not remove Pippin authentication-before-routing, bearer/session pinning,
  capability resolution, shared resident primitives, structural tool gating,
  config notifications, status provider, or session expiry.
- Do not replace the SDK with Orbit's custom HTTP/JSON-RPC implementation.
- Keep direct SwiftNIO products in `Package.swift` only because the conformance
  host is not an importable library product. No second HTTP framework is added.
- Contract tests remain black-box HTTP tests so a future official adapter can
  replace NIO without changing modules or security policy.

The complete retained-deviation table is frozen in
`research/g0-sdk-host-diff.md`.

## 4. SQLite Opening Contract

`SQLiteReader` passes the ordinary path to `sqlite3_open_v2` with
`SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE`; it does not use URI mode or
claim a file owned by another process is immutable. It verifies
`sqlite3_db_readonly(handle, "main") == 1` and configures a 250 ms busy timeout.
Busy exhaustion maps to `backend_unavailable` with retry/fallback guidance.

A controlled integration fixture uses two connections in WAL mode:

1. writer creates and commits a row;
2. reader queries it;
3. writer commits a second row while reader remains open;
4. a subsequent reader statement observes it;
5. deliberate contention terminates within the configured bound.

This proves the generic primitive. The live-visibility fixture asserts that the
database actually entered WAL mode. Busy behavior is deliberately measured on a
separate rollback-journal database under an exclusive lock, because WAL readers
normally do not block a writer. A timing assertion allows up to 750 ms because
SQLite may overshoot the configured sleep budget. Mail still verifies its real
Envelope Index, WAL files, schema, and Full Disk Access in its own Step 0.

The measured fixture and primary-documentation rationale are frozen in
`research/g0-sqlite-live-read.md`.

## 5. AppleScript Execution Budgets

Introduce one core coordinator keyed by target bundle identifier. Each key has a
single execution lane; different keys are independent. A request carries:

```swift
targetBundleID: String
queueTimeout: Duration
operationTimeout: Duration
maximumOutputBytes: Int
```

Repository-authored script source still goes through stdin and caller values
through argv. Queue timeout begins before process launch; operation timeout begins
after launch. stdout and stderr are drained concurrently into bounded buffers so
a full pipe cannot deadlock or allocate without limit.

Launch with Darwin `posix_spawn`, not Foundation `Process` followed by a raced
`setpgid`. Set `POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT` and pgroup
zero so process-group creation is atomic with spawn; configure all pipe `dup2`
and close operations through spawn file actions. The returned child PID is also
the process-group ID and the direct child is always reaped with `waitpid`.

On timeout, cancellation, or output overflow, signal `-processGroupID` with
TERM, wait 200 ms, then KILL the still-live group. Close every descriptor on every
path. This behavior was reproduced three times with a descendant that ignored
TERM; details are frozen in `research/g0-darwin-process-groups.md`.

## 6. Durable Mutation Intent

The existing `AuditLog` is a mode-0600 local operation journal, not a
tamper-evident audit system. Refine its API into two semantics:

- best-effort entries for reads, previews, and refusals where no mutation occurs;
- required durable intent for every mutating `perform`.

Add one `ToolContext.performMutation` owner for the journal sequence. Ordinary
write tools call it directly. `confirmDestructive` preserves preview and token
validation, consumes a valid token, then delegates the confirmed `perform` arm
to the same owner. Its `perform` closure returns `[String: JSONValue]`, reserving
two optional top-level fields for journal-health metadata.

The mutation owner executes in this order:

```text
validate mutation gate (and consume confirmation token when destructive)
→ append durable mutation intent
→ perform mutation
→ append outcome
→ return the real operation result plus honest journal health
```

Required intent and outcome appends propagate setup, rotation, open, write, and
`FileHandle.synchronize()` failures. They recover an unterminated tail before
appending and synchronize directory metadata after file creation or rotation.
Add `Outcome.intent` and an optional UUID
`operationID`; the intent and its outcome share that ID, while older JSONL lines
remain decodable. If the intent append fails, `perform` is never called. Use the
existing `backend_unavailable` code with `detail: "audit_log"` rather than
expanding the parent's stable error-code set. The intent entry ensures every
mutation is represented even if the process dies before the outcome append.

If `perform` completes but outcome append fails, do not return a generic failure
that could cause an Agent to retry an already-applied mutation. Merge the exact
fields below into the real object result:

```json
{
  "audit_degraded": true,
  "audit_hint": "Mutation succeeded. Audit outcome unavailable; do not retry. Later mutations stay blocked until audit storage recovers."
}
```

Latch journal health unavailable. Mutations already carrying a synchronized
intent may finish; no later `perform` begins until its own required intent append
and synchronize succeeds as a single-attempt recovery probe. A successful
outcome from an already-in-flight mutation does not clear the latch. If the probe
fails, reject with the same `backend_unavailable` / `audit_log` error and perform
nothing.

The record schema, crash windows, recovery semantics, and exact wire envelope
are frozen in `research/g0-mutation-journal-contract.md`.

Do not log bearer/confirmation tokens or argument values. Explicit affected IDs
remain because the Reminders child requires them and the file is private mode.

## 7. Upstream Reuse Policy

- Official SDK: direct dependency and sole MCP protocol implementation.
- MIT projects (`iMCP`, orchard-mcp, macos-mcp, mcp-apple-reminders,
  mac-mcp-server): port only focused behavior/tests with source attribution.
- Orbit inspected checkout: behavior comparison only unless a license is added.
- Upstream AppleScript interpolation, ad-hoc signing, per-client state, private
  ReminderKit, action-multiplexed tools, and unconfirmed deletes are rejected.

## 8. Compatibility and Rollback

No public tool surface changes. Existing endpoint format, bearer token,
Streamable HTTP, stdio shim, and `pippin_status` output remain compatible.

Each implementation step is separately reviewable. SQLite, AppleScript, and
journal changes can be reverted independently. If HTTP adapter reduction changes
wire behavior, revert that step rather than compensating in the shim or modules.
