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

### Step 2 — Packaging and signing
- [ ] Adapt `setup_dev_signing.sh` from `apple-skills:guide-macos-spm-packaging`
      for the self-signed path only; make it idempotent and refuse to overwrite an
      existing identity. Drop the Developer ID and notarization branches — they
      are permanently out of scope, and dead signing code here is a live footgun.
- [ ] Adapt `package_app.sh` with `MENU_BAR_APP=1`, `version.env`, and the full
      `Info.plist` key set; place `pippin-shim` inside the bundle.
- [ ] Adapt `compile_and_run.sh`.
- Validation:
  ```bash
  Scripts/package_app.sh
  ls -R build/Pippin.app/Contents
  codesign -dv --verbose=4 build/Pippin.app
  ```
- **Review gate G1:** signature identity recorded. Repackage twice more and
  confirm the identity is unchanged (AC2 first half).

### Step 3 — Config and core error/DTO plumbing
- [ ] `Config` with defaults, load/save, loopback-bind validation.
- [ ] `PippinError` with the parent's code set; every code carries a hint.
- [ ] DTO conventions: null pruning, ISO-8601 encoding, cursor pagination.
- Validation: `swift test --filter PippinCoreTests` covering non-loopback refusal,
  pruning, and hint coverage.

### Step 4 — Server, transport, validators
> **Blocked on parent open decision O4** (how the HTTP listener is provided).
> Steps 1–3 and gate G1 are unaffected; do those first.

- [ ] `ServerHost` actor owning the *shared* core — registry, token store, audit
      log, confirm-token store, config — plus the session table
      `sessionID → (Server, StatefulHTTPServerTransport)`. One `Server` is built
      per connecting client and injected with the shared core; the transport
      itself carries no cross-client state.
- [ ] HTTP listener bound to `127.0.0.1` per O4; port fallback to ephemeral.
      Route by the `Mcp-Session-Id` header; an `initialize` without one mints a
      session. Pipe `HTTPResponse.stream` to the client for SSE. Sweep sessions
      past a timeout, and close on DELETE.
- [ ] `TokenStore`: token → capability set. Provision one token with the full
      set; thread the capability set through to the registry. AC11 / S9.
- [ ] Bearer-token and Origin validators.
- [ ] Publish `endpoint.json` at mode `0600`.
- [ ] Register `pippin_status`.
- Validation: `curl` the endpoint with correct token (succeeds), wrong token
      (401), and a non-loopback `Origin` (rejected). AC5. Plus the two-token unit
      test from AC11, asserting different tool lists per capability set.

### Step 5 — Core safety primitives
- [ ] `ConfirmTokenStore`: mint / validate / consume, TTL, single-use, ID-set
      hash binding, session binding.
- [ ] `MutationGate`, `AuditLog` (JSONL, rotation, argument digests only).
- [ ] `AppleScriptRunner`: Apple Event argument passing, wall-clock timeout, no
      string interpolation of caller input.
- [ ] `SQLiteReader`: read-only open, dynamic versioned-path resolution, schema
      probe that disables the backend on mismatch.
- [ ] `BackendRouter`: ordered backends and degradation policy.
- Validation: `swift test` — token lifecycle cases, an injection-attempt test
      proving the payload is inert, a schema-probe-failure test proving the
      backend disables rather than returning zero rows. AC9.
- **Review gate G2:** the module children depend on these signatures. Review the
  primitive APIs here before module work starts; changing them later means
  reworking both module tasks.

### Step 6 — Tool registry and gating
- [ ] `(Config, Capabilities) → [Tool]` as a pure function.
- [ ] Gating: disabled module contributes nothing; writes-off contributes
      read-only tools only.
- [ ] Emit `notifications/tools/list_changed` on config change.
- [ ] `tools/list` byte-budget test against the parent A3 figure (6 KB batch one;
      the skeleton alone should be far under it, so the test's job here is to
      exist and be wired, ready for the module children to push against).
- Validation: `swift test`; then live — toggle a module and confirm the client's
      tool list changes without restarting. AC6.

### Step 7 — Shim
- [ ] `pippin-shim`: read `endpoint.json`, launch the app if needed, bounded
      readiness poll, dumb bidirectional frame forwarding.
- [ ] Distinct actionable errors for each terminal failure path.
- Validation: register the shim with Claude Code, list tools; then test each
      failure path (delete `endpoint.json`, kill the app, block launch). AC8.

### Step 8 — GUI
- [ ] `MenuBarExtra`: server status, port, session count, permission rows with
      real states, module toggles.
- [ ] `Settings` scene.
- [ ] Buttons opening the relevant System Settings panes.
- Validation: consult `apple-skills:hig` and `apple-skills:ios-liquid-glass`,
      then review against them. AC7, AC10.

### Step 9 — Integration and full-scope check
- [ ] Connect Claude Code over HTTP and over the shim; confirm identical tool
      lists. AC3.
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
