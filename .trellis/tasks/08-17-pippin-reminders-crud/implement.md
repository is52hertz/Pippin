# Reminders Module — Execution Plan

Prerequisite: `08-17-pippin-skeleton-transport` past review gate G2, so the core
primitives (`ConfirmTokenStore`, `MutationGate`, `AuditLog`, DTO conventions,
error model, registry) have settled APIs.

## Checklist

### Step 0 — Resolve EventKit unknowns
- [ ] Confirm the authorization API for Reminders on the target OS and the exact
      set of authorization states to branch on.
- [ ] Confirm identifier stability: local calendar-item identifier versus
      external identifier under iCloud sync. Pick the tool-facing `id` and record
      the choice in `design.md` §4.
- [ ] Confirm which change-notification signal fires for edits made in the
      Reminders app and for edits arriving from another device.
- [ ] Create the `Pippin Test` list in Reminders by hand for later integration
      runs.
- Validation: a scratch executable inside the packaged bundle prints
      authorization state, sources, and one reminder's identifiers.

### Step 1 — Backend protocol and DTO
- [ ] Define the EventKit-facing protocol in `PippinModules` so tools are
      testable without TCC.
- [ ] Reminder DTO plus list DTO, using the core pruning and ISO-8601
      conventions.
- [ ] Recurrence-to-short-string rendering.
- Validation: `swift test` — pruning, ISO-8601, recurrence rendering. No
      permissions required.

### Step 2 — Read tools
- [ ] `pippin_reminders_lists`, `pippin_reminders_search`,
      `pippin_reminders_get`.
- [ ] Semantic validation: due-range ordering, `list_id` existence →
      `not_found`, `limit` clamped to the server cap.
- [ ] Pagination with an opaque cursor; `next_cursor` present only when more
      results exist.
- Validation: `swift test` against the faked backend; then live reads against
      real data. AC10.

### Step 3 — Store lifecycle and permission handling
- [ ] `RemindersBackend` actor: store ownership, change-notification observation,
      staleness flag, refresh-before-operation.
- [ ] Authorization resolution branching per state, each with its own error code
      and hint.
- [ ] Empty-sources retry-once on startup.
- [ ] Per-operation timeout.
- Validation: AC7 and AC8 live — edit a reminder in the Reminders app while the
      server runs and confirm the next read reflects it without restart; revoke
      access in System Settings and confirm `permission_denied` with a hint rather
      than an empty list.
- **Review gate G1:** this step is requirement R8, the known-flakiness fix.
      Review it explicitly before moving to writes — if the mechanism here is
      wrong, every write inherits the same staleness bug.

### Step 4 — Non-destructive writes
- [ ] `pippin_reminders_create` — save, re-read, return re-read object, or
      `sync_pending`.
- [ ] `pippin_reminders_update` — field-explicit patch only.
- [ ] `pippin_reminders_complete` — idempotent set/clear.
- [ ] Audit-log entry per mutation.
- Validation: `swift test` for patch semantics (unnamed fields untouched); live
      round trip. AC1, AC2, AC9.

### Step 5 — Two-phase delete
- [ ] `pippin_reminders_delete` with preview arm and confirm arm.
- [ ] Preview reports unresolvable IDs rather than dropping them.
- [ ] Per-call ID cap.
- [ ] Post-delete verification that each ID no longer resolves.
- Validation: `swift test` for all four rejection cases against the real token
      store; live delete of a test-fixture reminder. AC3, AC4.
- [ ] Grep the module for any delete path taking a predicate, filter, or search
      result. There must be none. AC5.

### Step 6 — Registration and gating
- [ ] Register all seven tools with descriptions ≤ 200 characters and correct
      annotations.
- [ ] Confirm writes-off leaves only the three read tools in `tools/list`.
- Validation: `swift test` for gating; live toggle in Settings. AC6.
- [ ] Re-run the `tools/list` byte-budget test with Reminders enabled.

### Step 7 — Integration suite and full-scope check
- [ ] `PIPPIN_INTEGRATION=1` suite scoped to the `Pippin Test` list, with the
      fixture-name guard that aborts if the list is missing or if an operation
      would touch another list.
- Validation: `PIPPIN_INTEGRATION=1 swift test`; confirm the suite is skipped
      without the variable, and that removing the fixture list aborts rather than
      falling through. AC11.
- [ ] Re-run every acceptance criterion end to end.

## Validation Commands

```bash
swift build && swift test
PIPPIN_INTEGRATION=1 swift test          # requires the "Pippin Test" list
Scripts/package_app.sh && Scripts/compile_and_run.sh
```

## Rollback Points

- After step 2: reads are self-contained; writes can be abandoned without
  reverting reads.
- Before step 5: everything up to here is non-destructive. The delete tool is the
  single riskiest commit in the task and reverts on its own.

## Notes

- All permission-dependent validation runs against the packaged, signed bundle.
- Do not extend scope to Calendar events, subtasks, or attachments. Reminders
  verbs only.
