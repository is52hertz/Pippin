# Skeleton and Transport — Execution Plan

Prerequisites resolved (`../08-17-pippin-mcp-server/addendum-2026-08-18.md` §1):
swift-sdk approved (O1); signing uses the fixed self-signed keychain identity, no
Developer ID, no notarization (O2); batch-one `tools/list` budget is 6 KB (O3).

Ordering: this child lands before `08-17-pippin-reminders-crud` and
`08-17-pippin-mail-read-search`, which consume the primitives from step 5.

## Checklist

### Step 0 — Verify the SDK surface  ✅ done 2026-08-23
- [x] Version resolved: **0.12.1** (latest tag). Every API confirmed against the
      cloned source, not documentation. Full record:
      `research/swift-sdk-surface.md`.
- [x] Throwaway probe compiles and runs under Swift 6 language mode on
      `.macOS(.v26)`.
- [x] **Stop condition cleared.** Per-request session identity *is* exposed —
      `Server.currentHandlerContext.httpContext: HTTPRequest?` inside handlers,
      and per-session `Server` construction besides. Parent A2 stands unchanged;
      no confirm-token redesign needed.
- [x] Two corrections folded into the parent `design.md` §2 and `prd.md` O1:
      the transport takes no port/host (the listener is ours — new open decision
      **O4**), and one transport serves exactly one session, so many clients means
      a `sessionID → (Server, transport)` table over one shared state core.

### Step 1 — Package skeleton  ✅ done 2026-08-23
- [x] `Package.swift`: tools `6.2` (`.macOS(.v26)` is unavailable at 6.1), five
      targets plus two test targets, `swiftLanguageModes: [.v6]`. swift-sdk pinned
      `exact: "0.12.1"`; swift-nio `from: "2.101.3"` on `PippinServer` only (O4).
      `Package.resolved` committed.
- [x] `PippinCore` import boundary enforced two ways: the dependency graph makes
      MCP and NIO unreachable, and `ImportBoundaryTests` scans the sources for
      SwiftUI / AppKit / Cocoa, which the graph cannot block. Negative case
      verified — adding `import SwiftUI` to `PippinCore` fails the suite.
- [x] Validation: `swift build` and `swift test` both green (3 tests, 2 suites).
- Carried to later steps: use `Tool.Content.text(text:annotations:_meta:)`; the
  bare `.text("…")` form is deprecated in 0.12.1.
- Deliberately deferred: `PippinApp` is a minimal `MenuBarExtra` with Quit — just
  enough for step 2 to produce a launchable bundle. The real status UI is step 8.
  `pippin-shim` exits with a "not implemented (step 7)" message.

### Step 2 — Packaging and signing  ✅ done 2026-08-23 · gate G1 passed
- [x] Adapt `setup_dev_signing.sh` from `apple-skills:guide-macos-spm-packaging`
      for the self-signed path only; make it idempotent and refuse to overwrite an
      existing identity. Drop the Developer ID and notarization branches — they
      are permanently out of scope, and dead signing code here is a live footgun.
- [x] Adapt `package_app.sh` with `MENU_BAR_APP=1`, `version.env`, and the full
      `Info.plist` key set; place `pippin-shim` inside the bundle.
- [x] Adapt `compile_and_run.sh`.
- Validation:
  ```bash
  Scripts/package_app.sh
  ls -R build/Pippin.app/Contents
  codesign -dv --verbose=4 build/Pippin.app
  ```
- **Review gate G1: PASSED.** Evidence in `research/g1-signing-verification.md`;
  the identity and its designated requirement are recorded in the repo-root
  `notice.md`. Three `rm -rf build && package_app.sh` cycles produced an
  identical `Authority`, `Identifier`, and designated requirement
  (`identifier "io.github.is52hertz.pippin" and certificate root =
  H"1ab7e0bc…775d"`), signed by `1AB7E0BC58C427092143FBADABA7F34CD607775D` every
  time. `codesign --verify --deep --strict` passes and the bundle launches.
  Also verified: with no identity present the packaging script exits 1 without
  building, re-running the signing script refuses to overwrite, and no key
  material survives under `$TMPDIR`. Caveat recorded — `spctl` proved nothing on
  this machine, where Gatekeeper assessment is disabled.

### Step 3 — Config and core error/DTO plumbing  ✅ done 2026-08-23
- [x] `Config`: defaults (writes off, escape hatch closed), snake_case wire form,
      load/save, loopback-bind validation via `inet_pton`. A corrupt file is an
      error, not a silent reset — discarding it would discard the write gates.
- [x] `PippinError`: the parent's ten codes, each with a non-empty actionable
      hint; wire form matches the design byte for byte; absent `detail` pruned.
- [x] DTO conventions: `JSONValue` with recursive pruning that keeps `false` and
      `0`, ISO-8601 with explicit offset, opaque-cursor pagination with a
      server-side cap.
- [x] Validation: `swift test` — **47 tests in 6 suites, all passing.** Covers
      non-loopback refusal (including `localhost` and `0.0.0.0`), pruning
      (including the falsy-value trap), hint coverage across every code, and
      pagination termination end to end.

### Step 4 — Server, transport, validators  ✅ done 2026-08-23
- [x] `ServerHost` actor: shared core (config, token store, registry) plus the
      session table `sessionID → (Server, transport, token, capabilities)`, with a
      timeout sweep and DELETE close.
- [x] HTTP listener on swift-nio bound to `127.0.0.1` (O4), ephemeral-port
      fallback on conflict, SSE piped from `HTTPResponse.stream`. Loopback is
      re-checked at bind time, not just at config load.
- [x] `TokenStore`: token → `TokenIdentity { label, capabilities }`. One local
      token provisioned with all three capabilities; the capability set is
      threaded into the registry. AC11 / S9.
- [x] Bearer and Origin validators. Sessions are additionally bound to the token
      that opened them, so a broad token cannot be swapped for a narrow one
      mid-session while keeping the broad tier.
- [x] `endpoint.json` published at mode 0600, with a `pid` and an `isStale` check
      — a crash or `kill -9` leaves the file behind, so readers must verify rather
      than dial a dead port.
- [x] `pippin_status` registered and answering over the wire.
- [x] Validation — live against the packaged bundle:
      correct token `200`; wrong token `401`; absent token `401`;
      `Origin: https://evil.example.com` `403`; loopback `Origin` `200`.
      Full handshake returns `pippin_status` in `tools/list` with its annotations
      and `outputSchema`, and `tools/call` returns the structured snapshot. AC5.
      Plus the two-token capability test from AC11. `swift test`: 85 tests,
      11 suites, all passing.

### Step 5 — Core safety primitives  ✅ done 2026-08-23 · gate G2 passed
- [x] `ConfirmTokenStore`: mint / validate / consume, TTL, single-use, SHA-256
      ID-set binding (order-independent), session binding, tool binding, item cap.
- [x] `MutationGate`, `AuditLog` (JSONL, 0600, one-generation rotation, argument
      digests only).
- [x] `AppleScriptRunner`: values via `on run argv`, never interpolated;
      wall-clock timeout with SIGTERM then SIGKILL.
- [x] `SQLiteReader`: read-only + `immutable=1`, dynamic versioned-path
      resolution (numeric, so V10 beats V9), schema probe that disables the
      backend on mismatch, bound parameters only.
- [x] `BackendRouter`: ordered backends, degradation marker with a reason, and it
      throws rather than ever returning empty.
- [x] `ToolContext` — **added by the G2 review**. The six primitives were
      individually complete and collectively unusable: nothing carried
      `sessionID` into a module handler, which A2's session binding is defined in
      terms of. It also absorbs the whole two-phase delete protocol
      (`confirmDestructive`), so the guarantees hold by construction rather than
      by each module remembering five checks and three audit calls.
- [x] Validation: `swift test` — **151 tests in 18 suites, all passing.**
      Injection payloads run through real `osascript` and real SQLite and are
      inert; a 10-second script under a 600 ms timeout returns in ~0.6 s; a failed
      schema probe never yields zero rows; every routing failure throws.
- **Review gate G2: PASSED.** Frozen API surface, what the review changed, and
  the four bugs it surfaced are recorded in
  `research/g2-primitive-api-freeze.md`.

### Step 6 — Tool registry and gating  ✅ done 2026-08-23
- [x] **Already existed (landed with step 4, retained unchanged):**
      `(Config, Capabilities) → [Tool]` as a pure function, with disabled-module,
      writes-off, and caller-capability gating covered by unit tests.
- [x] **New:** one `ProductionToolCatalogue` is consumed by both `PippinApp` and
      the budget suite. It intentionally contains only `pippin_status`; no module
      stubs were added.
- [x] **New:** `ServerHost.updateConfig` validates before replacing shared state,
      re-derives each session's visible list, and sends
      `notifications/tools/list_changed` to every affected active session.
      Persistence remains owned by `Config.save` rather than the server actor.
- [x] **New:** reusable production-catalogue budget coverage enforces a serialized
      `tools/list` response ≤ 6 KiB, descriptions ≤ 200 characters, and the
      long-term count ceiling of 40 tools.
- [x] **Validation:** `swift build` passed; `swift test` passed with **156 tests
      in 19 suites**. A test-only synthetic catalogue proves module/write gating.
      A live SDK transport test opens three MCP sessions and their standalone SSE
      streams, then proves both affected full-capability sessions receive
      `ToolListChangedNotification` while the unaffected read-only session does
      not.
- Actual Reminders/Mail disappearance cannot be exercised until those module
  catalogues exist; it remains an integration check for their module work and
  step 9. No packaged-bundle module tool was fabricated for this step.

### Step 7 — Shim  ✅ done 2026-08-23
- [x] First follow the source-level contract in
      `research/shim-transport-surface.md` (swift-sdk 0.12.1): use raw
      `StdioTransport` + `HTTPClientTransport` rather than typed `Client` /
      `Server`, because the SDK exposes no wildcard proxy.
- [x] Read and validate `endpoint.json`. If missing, malformed, stale, or
      unreachable, launch the fixed bundle ID `io.github.is52hertz.pippin` via
      `/usr/bin/open -b`, then wait for a fresh authenticated endpoint under one
      bounded readiness deadline.
- [x] Relay JSON-RPC `Data` frames without interpreting or rewriting their
      business content, while converting stdio newline framing, HTTP POSTs, SSE
      events, and `MCP-Session-Id` framing. Preserve initialize ordering, then
      permit bounded concurrent POSTs so a long-running request cannot block
      cancellation or another request.
- [x] Hold only per-process ephemeral transport/session state. Keep the bearer
      token in memory only and never log/output it. Supervise resident liveness;
      on normal stdin EOF, use a bounded drain grace, cancel any stuck POST, and
      best-effort DELETE the MCP session before disconnect.
- [x] Distinct actionable nonzero exits for endpoint missing/malformed/stale,
      launch failure, readiness timeout, authentication failure, connection
      failure, runtime resident death, and stdio/output failure. No path hangs.
- [x] Tests: unchanged payload round-trip; session capture/reuse/termination;
      JSON, 202, POST-SSE, multi-event and split-chunk SSE; endpoint
      missing/malformed/stale; launch/readiness timeout; authentication and
      connection failure; long-running POST does not block cancellation.
- Validation this round: protocol-level tests plus a Codex stdio smoke test and
  direct-HTTP vs shim `tools/list` parity. Claude Code remains AC3's final client
  but its real smoke test is deferred to step 9 while organization access is
  externally disabled; that block is not a Pippin failure.
- Evidence: `research/step7-shim-verification.md`. `swift test` passed 172 tests
  in 22 suites. Codex launched the signed bundle's shim over stdio and called
  `pippin_status`; the direct-HTTP parity test observed the same `tools/list`.

### Step 8 — GUI
- [ ] `MenuBarExtra`: server status, port, session count, permission rows with
      real states, module toggles.
- [ ] `Settings` scene.
- [ ] Buttons opening the relevant System Settings panes.
- Validation: consult `apple-skills:hig` and `apple-skills:ios-liquid-glass`,
      then review against them. AC7, AC10.

### Step 9 — Integration and full-scope check
- [ ] Connect Claude Code over HTTP and over the shim; confirm identical tool
      lists. AC3. External prerequisite: restore Claude Code organization access
      or provide an Anthropic API key; until then, retain the protocol-level and
      Codex smoke evidence without marking AC3 complete.
- [ ] Two concurrent clients, one process, shared state, config change observed
      by both. AC4.
- [ ] Three rebuild-repackage cycles with no fresh TCC prompt. AC2.
- [ ] Re-run the whole acceptance list; record results in the manual checklist
      derived from `Test/templates-test-checklist.html`.

## Validation Commands

```bash
swift build
swift test
Scripts/package_app.sh
codesign -dv --verbose=4 build/Pippin.app
spctl --assess --type execute --verbose build/Pippin.app
```

## Rollback Points

- After step 2: packaging is independent of server code; a bad packaging change
  reverts without touching Swift sources.
- After step 5 (gate G2): the last point where primitive APIs are cheap to
  change. Past here, changes ripple into both module children.
- Steps 7 and 8 are independent of each other; either can revert alone.

## Notes

- Every permission-dependent validation runs against the packaged bundle, never
  `swift run`.
- Do not add module tools here, not even a stub. `pippin_status` is the only tool
  in scope.
