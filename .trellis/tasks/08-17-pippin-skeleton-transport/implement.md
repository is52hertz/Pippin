# Skeleton and Transport — Execution Plan

Prerequisites resolved (`../08-17-pippin-mcp-server/addendum-2026-08-18.md` §1):
swift-sdk approved (O1); signing uses the fixed self-signed keychain identity, no
Developer ID, no notarization (O2); batch-one `tools/list` budget is 6 KB (O3).

Ordering: this child lands before `08-17-pippin-reminders-crud` and
`08-17-pippin-mail-read-search`, which consume the primitives from step 5.

## Checklist

### Step 0 — Verify the SDK surface
- [ ] Resolve the swift-sdk version and confirm, against the real package:
      `StatefulHTTPServerTransport` init signature and `HTTPRequestValidator`
      shape; `StdioTransport`; `Tool` / `Tool.Annotations` / `outputSchema`;
      `Server.withMethodHandler(ListTools/CallTool)`; how
      `notifications/tools/list_changed` is emitted; how a session is identified
      (needed for confirm-token session binding).
- [ ] If session identity is not exposed per request, stop and revise the
      confirm-token design in the parent `design.md` before proceeding — session
      binding is a parent A2 requirement.
- Validation: a throwaway `swift build` against the resolved version compiles a
  minimal server.

### Step 1 — Package skeleton
- [ ] `Package.swift` with the five targets plus two test targets, `.macOS(.v26)`,
      Swift 6 language mode.
- [ ] Enforce the `PippinCore` import boundary (no SwiftUI / AppKit / MCP).
- Validation: `swift build && swift test` (trivially green).

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
- [ ] `ServerHost` actor owning server, registry, token store, audit log.
- [ ] `StatefulHTTPServerTransport` on `127.0.0.1`; port fallback to ephemeral.
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
