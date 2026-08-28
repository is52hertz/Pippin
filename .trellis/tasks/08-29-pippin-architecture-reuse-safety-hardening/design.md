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

- Compare `HTTPListener` and session setup against the exact 0.12.1 conformance
  `HTTPApp.swift` before editing.
- Add a source-provenance comment naming tag/commit and the retained deviations.
- Remove local parsing or state that the public SDK already performs. Do not
  replace the SDK with Orbit's custom HTTP/JSON-RPC implementation.
- Keep direct SwiftNIO products in `Package.swift` only because the conformance
  host is not an importable library product. No second HTTP framework is added.
- Contract tests remain black-box HTTP tests so a future official adapter can
  replace NIO without changing modules or security policy.

## 4. SQLite Opening Contract

`SQLiteReader` opens the ordinary path with `SQLITE_OPEN_READONLY`; it does not
claim a file owned by another process is immutable. URI mode is retained only if
an actual supported parameter requires it. Configure a short, documented busy
timeout and map exhaustion to `backend_unavailable` with retry/fallback guidance.

A controlled integration fixture uses two connections in WAL mode:

1. writer creates and commits a row;
2. reader queries it;
3. writer commits a second row while reader remains open;
4. a subsequent reader statement observes it;
5. deliberate contention terminates within the configured bound.

This proves the generic primitive. Mail still verifies its real Envelope Index,
WAL files, schema, and Full Disk Access in its own Step 0.

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

Step 0 must verify a race-safe, dependency-free process-group launch/termination
strategy on Darwin. On timeout or cancellation, terminate the group, wait a
short grace period, then kill the group. If Foundation `Process` cannot establish
that guarantee safely, stop at the review gate rather than pretending direct-PID
kill covers descendants.

## 6. Durable Mutation Intent

The existing `AuditLog` is a mode-0600 local operation journal, not a
tamper-evident audit system. Refine its API into two semantics:

- best-effort entries for reads, previews, and refusals where no mutation occurs;
- required durable intent for every mutating `perform`.

Add one `ToolContext.performMutation` owner for the journal sequence. Ordinary
write tools call it directly. `confirmDestructive` preserves preview and token
validation, then delegates the confirmed `perform` arm to the same owner.

The mutation owner executes in this order:

```text
validate mutation gate (and consume confirmation token when destructive)
→ append durable mutation intent
→ perform mutation
→ append outcome
→ return the real operation result plus honest journal health
```

If the intent append fails, `perform` is never called. Use the existing
`backend_unavailable` code with `detail: "audit_log"` rather than expanding the
parent's stable error-code set. The intent entry ensures every mutation is
represented even if the process dies before the outcome append.

If `perform` completes but outcome append fails, do not return a generic failure
that could cause an Agent to retry an already-applied mutation. Return the real
mutation result with an `audit_degraded` marker, latch journal health as
unavailable, and reject later mutations until a bounded health probe succeeds.
Gate G0 freezes the compact wire envelope before implementation.

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
