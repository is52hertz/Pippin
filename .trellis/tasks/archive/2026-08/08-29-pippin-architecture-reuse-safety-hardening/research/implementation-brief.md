# Implementation Brief: Reuse and Safety Hardening

This is the injection-sized implementation companion to
`upstream-reuse-audit.md`. Read the full audit when provenance, licensing, or a
specific upstream behavior matters.

## Fixed Scope

- Shared primitives and host adapter only: `PippinCore`, `PippinServer`, and
  their tests.
- No Reminders/Mail production tool, UI, lifecycle switch, signing change, SDK
  upgrade, or new dependency.
- `ProductionToolCatalogue` must still contain only `pippin_status`.

## Keep / Replace / Reference

| Area | Required action |
|---|---|
| JSON-RPC, MCP types, SSE, protocol validation, transport session | Keep official swift-sdk 0.12.1 exclusively |
| SwiftNIO listener | Keep temporarily as a thin socket/type adapter; document SDK conformance provenance |
| `ServerHost` | Keep Pippin token/capability policy and resident shared state; remove only proven SDK duplication |
| stdio shim | Keep raw relay over SDK `StdioTransport` and `HTTPClientTransport` |
| Stable signed app/TCC owner | Keep unchanged |
| SQLite abstraction | Keep probe/binding/version/fallback; replace `immutable=1` |
| AppleScript runner | Keep stdin script + argv values; add per-App lane and resource/process budgets |
| Tool gating/two-phase confirmation | Keep unchanged |
| JSONL audit | Replace silent fail-open mutation semantics with durable intent |
| Upstream app integrations | Reference or port licensed behavior/tests only |

Orbit commit `8b37369` has no license grant and is behavior reference only.
iMCP `b84f266`, orchard `0de0967`, macos-mcp `ab3922a`,
mcp-apple-reminders `3c26918`, and mac-mcp-server `10ee0a1` are MIT at the
inspected revisions; preserve attribution for any substantial port.

## Protocol and Host Boundary

The official SDK owns JSON-RPC decode/dispatch, Streamable HTTP validation, SSE,
resumability, and one transport session. Its public `MCP` library exposes
framework-neutral `HTTPRequest -> HTTPResponse`; the NIO host and multi-session
`HTTPApp` are in a non-importable conformance executable.

Therefore:

- keep `HTTPListener` for loopback bind and NIO↔SDK conversion;
- keep `ServerHost` for token/session pinning, capabilities, tool policy, and
  shared resident primitives;
- do not port Orbit's HTTP parser or MCP subset;
- retain direct black-box HTTP/shim tests so a future official host adapter can
  replace local NIO without touching modules.

## SQLite Contract

SQLite documents that `immutable=1` disables locking/change detection and can
return wrong results or corruption errors if the file changes. Mail owns and
actively modifies Envelope Index, so the assertion is false.

- Open an ordinary path with `SQLITE_OPEN_READONLY`.
- Freeze a short busy timeout during Step 0.
- Preserve dynamic `V*` resolution, startup schema probe, bound caller values,
  complete terminal-step checking, and explicit fallback/error behavior.
- Test one long-lived read-only connection observing later committed WAL writes,
  plus bounded contention.

## AppleScript Contract

- Repository-authored script source stays on stdin; caller values stay in argv.
- Serialize calls per target bundle ID, not globally.
- Bound queue wait, operation time, stdout, and stderr.
- On timeout/cancellation/output overflow, terminate the entire child process
  group with TERM, grace, then KILL.
- Step 0 must verify a race-safe Darwin process-group strategy without a new
  dependency; stop at G0 if that cannot be guaranteed.

## Mutation Journal Contract

- Reads, previews, and refusals may remain best-effort because they do not mutate.
- Every ordinary write and confirmed destructive operation uses one shared
  `ToolContext.performMutation` owner.
- Append durable intent before `perform`; failure maps to existing
  `backend_unavailable` with `detail: "audit_log"` and performs nothing.
- Append outcome afterward.
- If outcome append fails after mutation, return the real mutation result with a
  compact `audit_degraded` marker, do not invite retry, latch journal unhealthy,
  and reject later mutations until a bounded recovery probe succeeds.
- Keep explicit affected IDs and private file modes; never log credentials,
  argument values, AppleScript output, or Apple data.

## Required Gates

1. **G0:** verify exact SDK surface, listener deviations, SQLite flags/busy/WAL,
   Darwin process-group strategy, and `audit_degraded` wire envelope.
2. HTTP adapter tests: initialize, tools/list, notification, DELETE, bearer,
   Origin, token-session binding, direct/shim parity.
3. SQLite tests: read-only, WAL visibility, bounded contention, schema drift,
   bound injection payload, dynamic version, no silent empty.
4. AppleScript tests: same-App serialization, different-App concurrency, queue
   timeout, operation timeout, output cap, cancellation, no surviving child.
5. Journal tests: unwritable intent performs nothing; intent survives every
   mutation path; post-outcome failure is truthful and blocks later writes.
6. Final: `swift build`, `swift test`, `git diff --check`, signed packaging with
   unchanged identity/no fresh TCC prompt, and independent `trellis-check`.
