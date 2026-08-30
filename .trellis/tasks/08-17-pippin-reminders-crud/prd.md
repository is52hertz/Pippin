# Pippin: Reminders Full CRUD Vertical Slice

Child of `08-17-pippin-mcp-server`. Read the parent's `prd.md` and `design.md`
first.

## Goal

The first real module: complete Reminders access over EventKit — list, search,
get, create, update, complete, delete — with the two-phase delete protocol and
correct behaviour under iCloud sync.

Reminders is chosen as the first module because it exercises every hard part at
once: a framework backend, writes, the only genuinely destructive verb in batch
one, and iCloud sync. It is also the specific thing that fails today on the
installed server ("sometimes can't connect to Reminders"), so reproducing and
fixing that failure is in scope.

## Requirements

- **R1 — Tool set, one tool per verb.** Read-only: `pippin_reminders_lists`,
  `pippin_reminders_search`, `pippin_reminders_get`. Writes:
  `pippin_reminders_create`, `pippin_reminders_update`,
  `pippin_reminders_complete`. Destructive: `pippin_reminders_delete`.
- **R2 — Correct annotations.** Read tools `readOnlyHint: true`. `complete` is a
  write but non-destructive and idempotent. `delete` is
  `destructiveHint: true, idempotentHint: false`.
- **R3 — Lean output.** Minimal reminder DTO; nulls pruned; recurrence collapsed
  to a short string rather than a nested object; search paginated with a
  server-side hard cap.
- **R4 — Two-phase delete.** Uses the parent's protocol via the skeleton's
  `ConfirmTokenStore`. Explicit ID lists only, count-capped, no predicate delete.
- **R5 — `complete` is the promoted alternative to `delete`.** Its own
  non-destructive tool, and `delete`'s description points at it, so an agent
  clearing a finished task reaches for the reversible verb.
- **R6 — Update is field-explicit.** Only the fields the caller names change.
  No read-modify-write of the whole object, which would silently clobber
  concurrent edits from another device.
- **R7 — iCloud correctness.** No long-lived unrefreshed `EKEventStore`. Every
  write re-reads and returns the canonical object, or reports `sync_pending`.
  An empty source list right after launch is treated as "not loaded yet" and
  retried once, not reported as "no data".
- **R8 — Reproduce and fix the known flakiness.** Identify why Reminders access
  intermittently fails (candidates: stale store in a resident process, access
  state not-determined versus denied, iCloud sources not yet loaded, missing
  full-access request on macOS 14+) and handle each explicitly with a distinct
  error code and hint.

## Non-Requirements

- No Calendar events. Same framework, different module, separate task.
- No subtasks/nested reminders, no attachments, no location-based alarms in this
  slice — add only if EventKit makes them trivial and they cost no extra tools.
- No bulk import.

## Acceptance Criteria

- [ ] **AC1** Full round trip against the `Pippin Test` list: create → get →
      update → search finds it → complete → delete.
- [ ] **AC2** Every write returns the object re-read from the store, not the
      locally constructed one.
- [ ] **AC3** `pippin_reminders_delete` without a token performs nothing and
      returns a preview plus token and expiry. With a valid token it deletes.
- [ ] **AC4** Delete is refused with a distinct error for each of: expired token,
      reused token, token from another session, ID set differing from the one the
      token was minted for.
- [ ] **AC5** No code path exists that deletes by predicate, filter, or search
      result — only by explicit ID list, count-capped.
- [ ] **AC6** With the module's writes disabled, `create`/`update`/`complete`/
      `delete` are absent from `tools/list`; the read tools still work.
- [ ] **AC7** Permission states are distinguished: not-determined triggers the
      request; denied returns `permission_denied` with a hint; neither returns an
      empty result set.
- [ ] **AC8** A reminder changed in the Reminders app while the server is running
      is reflected on the next read without restarting the server.
- [ ] **AC9** Every mutation appears in the audit log with affected IDs and
      outcome.
- [ ] **AC10** `search` output stays lean: a 50-result search is checked against a
      byte ceiling, and `limit` above the server cap is clamped, not honoured.
- [ ] **AC11** Integration tests refuse to run against any list other than the
      test fixture, and are skipped unless `PIPPIN_INTEGRATION=1`.

## Constraints and Notes

- Depends on `08-17-pippin-skeleton-transport` gate G2 and on
  `08-29-pippin-architecture-reuse-safety-hardening` completing the durable
  destructive-intent contract. Do not start implementation before both.
- macOS 14+ requires the full-access Reminders authorization request; the
  Info.plist usage description ships in the skeleton child.
- Relevant skills: `apple-skills:eventkit`, `apple-skills:swift-testing`.
