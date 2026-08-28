# Mail Module — Execution Plan

Prerequisites: `08-17-pippin-skeleton-transport` past review gate G2 and
`08-29-pippin-architecture-reuse-safety-hardening` completed (`SQLiteReader`,
AppleScript execution budgets, `BackendRouter`, and error model settled).
Independent of the Reminders child after those shared prerequisites.

## Checklist

### Step 0 — Verify the Mail data reality on this machine
- [ ] Locate the versioned Mail directory and the Envelope Index file; confirm the
      globbing strategy finds it.
- [ ] With Full Disk Access granted to the packaged app, open the database
      read-only and dump the schema of the tables the search needs.
- [ ] Verify read-only access works while Mail is running (does it hold a lock?).
- [ ] Record the exact tables and columns the probe will assert.
- [ ] Confirm the AppleScript surface for accounts, mailboxes, and message fetch,
      and measure how slow an AppleScript search actually is on this mailbox — that
      measurement is the justification for the SQLite primary and belongs in the
      task record.
- Validation: schema dump and timing numbers written into this task's `research/`
      directory. If read-only access while Mail runs proves impossible, revise
      `design.md` §4 before writing code.

### Step 1 — Backend protocols and output shapes
- [ ] Define protocols for both backends in `PippinModules` so every routing and
      degradation case is testable with fakes.
- [ ] Search-row and message DTOs, using core pruning and ISO-8601 conventions.
- [ ] Snippet capping and body capping with an explicit truncation marker.
- Validation: `swift test` — shaping, capping, truncation marker. No permissions.

### Step 2 — Routing and degradation, fakes only
- [ ] Wire `BackendRouter` for the three capabilities per `design.md` §1.
- [ ] Implement every branch: primary available; probe failed → fallback; probe
      failed and Mail not running → `backend_unavailable`; timeout.
- [ ] Degraded-response marker set exactly when a fallback served the request.
- Validation: `swift test` covering all branches, including the dedicated
      assertion that a failed probe never yields a zero-row success. AC11.
- **Review gate G1:** this step is the whole point of the task. Review the
      degradation matrix before either real backend exists — if it is wrong here,
      real backends will paper over it with plausible-looking empty results.

### Step 3 — Envelope Index backend
- [ ] Dynamic versioned-path resolution; no hard-coded version. AC4.
- [ ] Read-only open; parameterized queries only. AC5.
- [ ] Startup schema probe with a recorded reason on failure; expose availability
      and reason through `pippin_status`. AC10.
- [ ] Map file-open failure to `backend_unavailable` with a Full Disk Access hint.
- Validation: live search with FDA granted (AC1); revoke FDA and confirm AC2;
      corrupt the probe expectation and confirm AC3.

### Step 4 — AppleScript backend
- [ ] `pippin_mail_accounts` and mailbox enumeration.
- [ ] Message fetch for `pippin_mail_get`.
- [ ] Fallback search path.
- [ ] `app_not_running` when Mail is not running; never launch Mail from a read.
      AC6.
- [ ] Wall-clock timeout on every call; verify other clients are served while one
      call is pending. AC7.
- Validation: live fetch; quit Mail and re-test; artificially slow a call to force
      the timeout path.

### Step 5 — Tool registration
- [ ] Register the three tools, `readOnlyHint: true`, descriptions ≤ 200
      characters.
- [ ] Semantic validation: date-range ordering, mailbox existence → `not_found`,
      `limit` clamped.
- Validation: `swift test`; re-run the `tools/list` byte-budget test with Mail
      enabled; 50-result search against the byte ceiling. AC8, AC9.

### Step 6 — Integration and full-scope check
- [ ] `PIPPIN_INTEGRATION=1` read-only suite asserting shape and non-emptiness
      only, never specific message content.
- [ ] Manual pass: AC2 (revoke FDA), AC3 (bad probe), AC6 (Mail quit), AC7
      (timeout).
- [ ] Re-run every acceptance criterion.
- [ ] **Decision point:** if the SQLite backend proved unstable in practice,
      default it off, keep AppleScript as primary for search, and record the
      decision plus its performance cost in the task. That is an acceptable
      outcome, not a failure.

## Validation Commands

```bash
swift build && swift test
PIPPIN_INTEGRATION=1 swift test
Scripts/package_app.sh && Scripts/compile_and_run.sh
```

## Rollback Points

- After step 2: routing and degradation are fake-backed and independent of both
  real backends; either backend can be rewritten without touching it.
- Step 3 and step 4 are independent; the SQLite backend can be reverted entirely
  and the module still works through AppleScript, only slower. That is by design
  and is the module's rollback story.

## Notes

- Read-only module. Do not add send, move, flag, or delete, and do not add a
  destructive tool of any kind.
- Full Disk Access is granted to `Pippin.app`, not to the terminal or the client.
  All permission-dependent validation runs against the packaged bundle.
