# Pippin: Architecture Reuse and Safety Hardening

Child of `08-17-pippin-mcp-server`. This is a batch-one prerequisite for the
Reminders and Mail vertical slices. It converts the 2026-08-29 upstream audit
into bounded implementation work without widening Pippin's product surface.

## Goal

Remove protocol-hosting duplication where the official Swift SDK already owns
the behavior, retain only the listener/session policy Pippin genuinely needs,
and harden the shared SQLite, AppleScript, and mutation-journal primitives before
real Apple data modules depend on them.

## Requirements

- **R1 — Official SDK owns MCP protocol behavior.** JSON-RPC encoding, MCP
  message types, Streamable HTTP validation, SSE framing, resumability, and
  transport-session semantics remain delegated to `modelcontextprotocol/swift-sdk`
  0.12.1. Pippin must not fork or independently reimplement them.
- **R2 — The HTTP host adapter stays thin and replaceable.** Retain SwiftNIO only
  for socket binding and conversion between NIO messages and SDK
  `HTTPRequest`/`HTTPResponse`. Record provenance from the SDK conformance
  server. Authentication policy, capability resolution, resident shared state,
  and tool dispatch remain Pippin-owned. If the official SDK later exposes an
  importable host adapter, replacement must not require module changes.
- **R3 — Live private SQLite stores are opened honestly.** Remove
  `immutable=1`. Use a true read-only connection with bounded busy behavior and
  verify WAL/change visibility while another connection writes. Schema probes,
  bound values, dynamic `V*` path resolution, explicit degradation, and the
  no-silent-empty rule remain unchanged.
- **R4 — AppleScript execution is host-app safe.** Preserve stdin script text,
  argv parameters, and wall-clock timeout. Add per-target-App serialization,
  bounded queue wait, bounded stdout/stderr capture, and cleanup that terminates
  the whole spawned process group. One wedged Mail call must not leak processes,
  exhaust memory, or block unrelated host apps.
- **R5 — Mutation logging has an explicit guarantee.** Every mutating execution
  requires a durable intent record before `perform` runs. If the journal cannot
  accept that record, the mutation fails closed with an actionable existing
  `PippinError` code. If the mutation succeeds but its outcome append fails, the
  response must truthfully report that the mutation occurred, carry an
  `audit_degraded` marker that does not invite retry, and block later mutations
  until journal health recovers. The design must not call the local JSONL file
  tamper-proof or compliance-grade auditing.
- **R6 — Pippin-specific safety stays.** Keep the stable signed `.app`, one
  resident state owner, endpoint credential privacy, token-to-capability
  resolution, tool-per-verb annotations, structural tool gating, and the
  session/tool/exact-ID-bound two-phase confirmation protocol.
- **R7 — Reuse is evidence- and license-aware.** MIT-licensed upstreams may
  inform tests or be ported with attribution. Orbit's inspected checkout has no
  license file and is design reference only. No copied upstream protocol stack
  replaces the official SDK.
- **R8 — No feature expansion.** This task adds no Reminders or Mail production
  tool, no UI, no app/server enable-disable lifecycle behavior, no signing
  change, and no new third-party dependency. MCP session cleanup may be aligned
  with the pinned SDK conformance host when the observable behavior is covered
  by protocol regression tests.

## Non-Requirements

- No upgrade beyond swift-sdk 0.12.1 in this task.
- No removal of the resident HTTP topology or stdio shim.
- No upstream issue or pull request as an acceptance dependency; the design may
  prepare a minimal proposal for later submission.
- No Mail schema/query implementation and no EventKit module implementation.
- No generic AppleScript or Accessibility escape hatch.

## Acceptance Criteria

- [x] **AC1** Source review confirms all JSON-RPC, SSE, protocol-version, and MCP
      transport-session behavior is supplied by swift-sdk; retained Pippin code
      is limited to host adaptation and product policy, with provenance comments
      and regression tests.
- [x] **AC2** Direct HTTP and shim initialize, `tools/list`, notifications, and
      session DELETE continue to pass unchanged; only `pippin_status` is present
      in the production catalogue.
- [x] **AC3** `SQLiteReader` contains no `immutable=1`; a test proves a read-only
      reader observes committed WAL-backed changes from a concurrent writer, and
      lock contention fails within a documented bound rather than hanging.
- [x] **AC4** Existing SQLite schema-probe, bound-parameter, dynamic-version,
      read-only, and no-silent-empty tests remain passing.
- [x] **AC5** AppleScript calls targeting the same App serialize; calls targeting
      different Apps may proceed independently. Queue timeout, operation timeout,
      output overflow, cancellation, and child-process cleanup have deterministic
      tests that never invoke TCC data.
- [x] **AC6** No AppleScript argument is interpolated into source and no captured
      output above the configured ceiling is retained or returned.
- [x] **AC7** Any mutating call against an unwritable journal performs no
      mutation. Successful and failed attempts leave an intent entry with IDs
      plus an outcome when outcome append succeeds. A post-mutation outcome-log
      failure reports the real mutation result with `audit_degraded`, does not
      suggest retry, and prevents later mutations until recovery.
- [x] **AC8** Existing confirmation-token guarantees remain unchanged: TTL,
      single-use, exact ID set, requesting session, tool binding, and item cap.
- [x] **AC9** No new dependency, production tool, TCC prompt, signing identity,
      UI behavior, or externally bound listener is introduced.
- [x] **AC10** `swift build`, `swift test`, `git diff --check`, direct-HTTP/shim
      parity, and an independent `trellis-check` pass.

## Constraints and Notes

- Read `research/upstream-reuse-audit.md` before implementation.
- This task must land before `08-17-pippin-reminders-crud` and
  `08-17-pippin-mail-read-search`. It need not wait for the skeleton's externally
  blocked Claude Code AC3 because it preserves the existing transport contract.
- Full Disk Access verification against Mail remains in the Mail child. This
  task proves generic live-WAL read correctness using controlled fixtures.
- `Refer/` is user-provided, untracked evidence. Never modify, commit, or delete
  it.
