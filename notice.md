# Project Notice — Pippin

Durable, cross-task facts. Session progress does not belong here.

## Signing identity — do not regenerate

Pippin.app is signed with a self-signed local identity. macOS keys TCC grants to
the code signature, so replacing this certificate silently invalidates every
permission the user has granted — it produces no error, only later failures that
look like bugs.

```
Identity    Pippin Local Signing
SHA-1       1AB7E0BC58C427092143FBADABA7F34CD607775D
Bundle ID   io.github.is52hertz.pippin
Created     2026-08-23, validity 7300 days
```

The designated requirement TCC matches on:

```
identifier "io.github.is52hertz.pippin"
  and certificate root = H"1ab7e0bc58c427092143fbadaba7f34cd607775d"
```

Only two things are pinned: the bundle identifier and the certificate. The
binary's hash is not, so rebuilding freely is safe. Changing either of the two is
not, and neither is recoverable except by re-granting every permission by hand.

`Scripts/setup_dev_signing.sh` refuses to overwrite an existing identity and has
no `--force`. That is deliberate; do not add one.

## Packaging

- `Scripts/package_app.sh` → `build/Pippin.app`. Requires the identity above and
  **fails hard** if it is missing or ambiguous. There is no ad-hoc fallback, by
  design — an ad-hoc signature has no stable designated requirement.
- Hardened runtime is deliberately off. It exists to satisfy notarization, which
  is permanently out of scope (no paid Apple Developer account), and enabling it
  would impose an entitlement requirement on the Apple Events this app sends.
- Never validate permission-dependent behaviour via `swift run`. A bare
  executable has a different signature and bundle identity and does not inherit
  the app's TCC grants. Use `Scripts/compile_and_run.sh`.

## Dependencies

Two, both user-approved: `modelcontextprotocol/swift-sdk` (pinned `exact:
"0.12.1"` — pre-1.0, and its transport contract has been mapped in detail) and
`apple/swift-nio` (the MCP SDK ships no HTTP listener). Adding a third needs a
decision.

`PippinCore` must not import SwiftUI, AppKit, or the MCP SDK. The package graph
blocks the SDK and NIO; `Tests/PippinCoreTests/ImportBoundaryTests.swift` covers
the system frameworks.

## Tool surface

- `ProductionToolCatalogue` is the one production catalogue. App modules add
  their `ToolDefinition`s there; the app and the automated token-budget checks
  both consume that same source, so registration and budget accounting cannot
  drift apart.
- Tool visibility is derived purely from `(Config, Capabilities)`. A disabled
  module contributes nothing; writes-off contributes read-only tools only.
  Never add a present-but-refusing tool as a substitute for absence — it would
  remain in the recurring token budget and in the agent's candidate set.
- `ServerHost.updateConfig` validates before changing shared state and emits
  `notifications/tools/list_changed` only to sessions whose visible tool list
  actually changed. Persistence remains `Config.save`'s responsibility.
- Automated ceilings: serialized batch-one `tools/list` ≤ 6 KiB, each tool
  description ≤ 200 characters, and the long-term default catalogue ≤ 40 tools.

## Stdio shim transport

- `PippinShim` relays raw `Data` between swift-sdk 0.12.1's `StdioTransport`
  and `HTTPClientTransport`. Do not insert typed SDK `Client`/`Server` actors:
  they consume lifecycle messages and cannot transparently proxy unknown tools.
- The shim converts newline, HTTP POST, SSE-event, and `MCP-Session-Id` framing
  without decoding or rewriting JSON-RPC business content. It sequences the
  first two frames for initialize/initialized, then allows at most four POSTs
  concurrently.
- All shim state is scoped to one process/stdio connection. The endpoint,
  bearer token, session ID, SSE state, and requests are memory-only; the token
  must never enter logs, diagnostics, arguments, or environment variables.
  `PippinShim` must not import or access Apple/TCC data frameworks.
- Endpoint recovery validates a mode-0600 file, literal loopback host, port, and
  live PID, then launches only bundle ID `io.github.is52hertz.pippin`. Startup
  waits are bounded; the `open` helper escalates TERM→KILL rather than hanging.
- On stdin EOF, accepted POSTs receive a two-second drain grace. The shim then
  cancels any remainder, sends best-effort authenticated DELETE for the session,
  and disconnects. Preserve the timeout and the regression tests when changing
  lifecycle code.

## Secrets

The repository is public. `.gitignore` denies keys, certificates, keychains,
provisioning profiles, `build/`, and `endpoint.json` (which carries the server's
bearer token at runtime). `setup_dev_signing.sh` exports nothing; key material
lives only in a mode-0700 temp directory and is wiped by a trap.
