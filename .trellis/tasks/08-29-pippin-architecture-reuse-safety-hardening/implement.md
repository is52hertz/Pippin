# Architecture Reuse and Safety Hardening — Execution Plan

Prerequisite for the Reminders and Mail children. This task changes shared
primitives only and adds no production module tools.

## Step 0 — Freeze upstream and OS contracts · Gate G0

- [ ] Re-check the exact swift-sdk 0.12.1 `StatefulHTTPServerTransport`,
      `HTTPClientTransport`, `StdioTransport`, conformance `HTTPApp`, and package
      products against `research/upstream-reuse-audit.md`.
- [ ] Diff Pippin's listener/session host against the conformance host and list
      every retained deviation with its Pippin policy reason.
- [ ] Verify SQLite read-only/WAL/busy semantics against SQLite primary docs and
      a scratch fixture; freeze the target open flags and timeout.
- [ ] Verify a race-safe Darwin process-group creation and kill strategy without
      adding a dependency. Stop if the guarantee cannot be implemented honestly.
- [ ] Freeze the shared mutation-journal order, recovery probe, and compact
      post-mutation `audit_degraded` envelope without adding an error code.
- **G0:** update `design.md` with measured/verified details and obtain review
  before production edits.

## Step 1 — Minimize the HTTP host adapter

- [ ] Add exact upstream provenance and retained-deviation notes.
- [ ] Remove only protocol/session/framing behavior demonstrably duplicated by
      a public SDK API; keep socket adaptation and Pippin policy.
- [ ] Preserve bearer/Origin handling, token-session pinning, session cleanup,
      standalone SSE notifications, and shared resident state.
- Validation: focused `PippinServerTests`, direct HTTP initialize/tools/list,
  notification, and DELETE checks.

## Step 2 — Correct SQLite live-read semantics

- [ ] Remove `immutable=1` and implement the G0 read-only/busy policy.
- [ ] Add a WAL writer/reader fixture proving committed-change visibility and a
      bounded contention failure.
- [ ] Preserve dynamic version resolution, schema probe, bound values, and
      explicit error/degradation behavior.
- Validation: `SQLiteReaderTests`, `BackendRouterTests`, and source search proving
  no production `immutable=1` remains.

## Step 3 — Add AppleScript host-app budgets

- [ ] Add per-target-App lanes and bounded queue wait.
- [ ] Add bounded stdout/stderr capture without pipe deadlock.
- [ ] Implement operation timeout/cancellation cleanup for the entire process
      group using the verified G0 strategy.
- [ ] Keep stdin script/argv argument separation and existing error mapping.
- Validation: same-target serialization, different-target concurrency, queue
  timeout, operation timeout, oversized output, cancellation, injection payload,
  and no-surviving-child tests.

## Step 4 — Make mutation intent durable

- [ ] Split best-effort non-mutation entries from required mutation-intent append.
- [ ] Add one `ToolContext.performMutation` sequence for ordinary writes and
      confirmed destructive operations.
- [ ] Route `ToolContext.confirmDestructive` through that owner after token
      validation, then append outcome.
- [ ] Fail closed with existing `backend_unavailable` / `audit_log` semantics if
      intent cannot be written.
- [ ] On post-mutation outcome failure, return the real result with the frozen
      `audit_degraded` marker and block later mutations until recovery.
- [ ] Preserve token consumption, exact-ID binding, and private file modes.
- Validation: unwritable intent performs nothing; success/failure/crash-window
  simulations retain the intent; existing confirmation and rotation tests pass.

## Step 5 — Full-scope gate

- [ ] Confirm `ProductionToolCatalogue` still exposes only `pippin_status`.
- [ ] Run `swift build`, `swift test`, `git diff --check`, direct HTTP/shim parity,
      and tools/list budget checks.
- [ ] Package the signed app without touching the identity and confirm no new TCC
      prompt is triggered by these primitive-only changes.
- [ ] Run independent `trellis-check`; update code specs only for durable
      contracts learned during implementation.
- [ ] Re-run AC1–AC10 and record evidence in this task's `research/` directory.
