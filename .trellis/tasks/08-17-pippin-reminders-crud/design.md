# Reminders Module — Technical Design

Inherits `../08-17-pippin-mcp-server/design.md`.

## 1. Backend

EventKit only. No AppleScript path, no SQLite path — the framework covers every
verb in scope, and per the parent's routing ladder a framework backend wins
whenever it exists.

## 2. Tool Surface

| Tool | Kind | Annotations | Purpose |
|---|---|---|---|
| `pippin_reminders_lists` | read | `readOnlyHint` | containers: id, title, source, colour omitted |
| `pippin_reminders_search` | read | `readOnlyHint` | filters + pagination |
| `pippin_reminders_get` | read | `readOnlyHint` | full DTO for explicit IDs |
| `pippin_reminders_create` | write | — | create in a named list |
| `pippin_reminders_update` | write | `idempotentHint` | field-explicit patch |
| `pippin_reminders_complete` | write | `idempotentHint` | set/unset completion |
| `pippin_reminders_delete` | destructive | `destructiveHint` | two-phase, ID list only |

Seven tools. Descriptions ≤ 200 characters each; `delete`'s description names
`pippin_reminders_complete` as the reversible alternative.

`search` parameters: `list_id`, `completed` (tri-state: only-open / only-done /
both), `due_from`, `due_to`, `text`, `limit`, `cursor`. Semantic validation
beyond the schema: `due_from ≤ due_to`, `list_id` must exist (else `not_found`,
not an empty result), `limit` clamped to the server cap.

## 3. DTO

```json
{
  "id": "…",
  "title": "…",
  "list_id": "…",
  "due": "2026-08-18T09:00:00+08:00",
  "priority": 5,
  "completed_at": "…",
  "notes": "…",
  "recurrence": "every week on Mon",
  "url": "…"
}
```

Nulls pruned, so an open reminder with no due date carries three fields. `search`
returns `id`, `title`, `list_id`, `due`, and completion state only; `notes`,
`url`, and `recurrence` require `_get`. Recurrence is a short rendered string —
dumping `EKRecurrenceRule` as nested JSON would cost more tokens than the whole
rest of the object.

## 4. Identifier Semantics

Use EventKit's local calendar-item identifier as the tool-facing `id`.

Open item for step 0 of the execution plan: confirm the stability semantics of
the local identifier versus the external identifier under iCloud sync. Whichever
is chosen, the tool descriptions must state that IDs are session-scoped handles —
agents should re-search rather than persist an ID across a long gap, and `_get`
on a stale ID returns `not_found` rather than a wrong object.

## 5. Store Lifecycle — the Flakiness Fix

This is the substance of requirement R8. A resident process is the exact shape
that accumulates stale EventKit state, so the store lifecycle is designed rather
than incidental:

```
RemindersBackend (actor)
  ├── store: EKEventStore
  ├── observes .EKEventStoreChanged → mark stale
  └── before each operation:
        if stale     → refresh sources, clear stale
        if no access → resolve authorization first (see below)
```

Authorization resolution, with a distinct outcome per state:
- *not determined* → request full access to reminders; proceed or fail per result.
- *denied* / *restricted* → `permission_denied` with a hint naming the System
  Settings pane. Never an empty list.
- *authorized* → proceed.

Startup race: if the source list comes back empty, refresh and retry once before
concluding there is genuinely nothing. An empty result and "iCloud has not
finished loading" are indistinguishable at the API surface, and reporting the
former is the bug being fixed.

Every operation is bounded by a timeout so a wedged EventKit call cannot hold the
resident server for other clients.

## 6. Writes

`create`: build, `save(commit: true)`, re-read by identifier, return the re-read
object. If the re-read misses, return `sync_pending` with the identifier —
honest, and lets the agent retry a `_get` instead of assuming failure.

`update`: fetch, apply only the named fields, save, re-read, return. Reading the
whole object and writing it back wholesale would clobber a concurrent edit that
arrived from another device between the read and the write; field-explicit
patching keeps the blast radius to the fields the caller actually named.

`complete`: sets or clears completion. Idempotent — completing an already
completed reminder succeeds without error.

`delete`: two-phase per the parent protocol.
1. No `confirm_token` → resolve each ID to its current title and list, return
   that preview plus a token and `expires_at`. Nothing is removed. An ID that
   does not resolve is reported in the preview rather than silently dropped, so
   the user confirms against reality.
2. With `confirm_token` → validate existence, expiry, single-use, session, and
   ID-set hash; then remove and commit; then confirm each ID no longer resolves.

Reminders deletion has no undo, which is why `complete` is promoted and why the
per-call ID cap exists.

## 7. Testing

**Unit, no permissions:** DTO shaping and pruning; recurrence rendering; search
parameter validation (range order, limit clamping); the delete tool's two-phase
branching against a faked token store; registry gating with writes off.

The EventKit boundary is behind a protocol so all of the above runs without TCC
or user data. Only the protocol's real implementation needs the framework.

**Integration, `PIPPIN_INTEGRATION=1`:** operates solely on a list named
`Pippin Test`. The harness resolves that list by name and aborts the whole suite
if it is missing or if any operation would touch a different list — a
misconfigured run must fail loudly, never mutate real reminders.

Covered: full round trip; write-then-reread; external change picked up via the
change notification; each token-rejection case; permission-denied path (manual,
by revoking access).

## 8. Risks

| Risk | Handling |
|---|---|
| Identifier semantics differ from assumption | Resolved in execution step 0 before any tool is written |
| Change notification does not fire for remote edits | Fall back to refreshing sources on a bounded staleness interval |
| A write appears to succeed but is not visible | `sync_pending` rather than a success claim |
| Integration test hits a real list | Fixture-name guard aborts the suite |
| Delete has no undo | Two-phase token, ID-list-only, per-call cap, `complete` promoted, audit log |
