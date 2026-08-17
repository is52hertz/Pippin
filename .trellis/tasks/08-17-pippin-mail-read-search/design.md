# Mail Module — Technical Design

Inherits `../08-17-pippin-mcp-server/design.md`.

## 1. Capability-to-Backend Map

Routing is declared per capability. This is the module that demonstrates why the
parent's ladder is per capability rather than per app:

| Capability | Primary | Fallback | If all fail |
|---|---|---|---|
| accounts / mailboxes | AppleScript | — | `app_not_running` or `timeout` |
| search | Envelope Index (SQLite, read-only) | AppleScript | `backend_unavailable` |
| message fetch | AppleScript | — | `app_not_running` or `timeout` |

Search goes to SQLite because an AppleScript search across a real mailbox is slow
enough to be unusable and can block Mail's own UI. Fetch goes to AppleScript
because it is a single-item operation where the cost is acceptable and the
correctness is much better than reassembling a message from private storage.

## 2. Tool Surface

| Tool | Purpose | Output |
|---|---|---|
| `pippin_mail_accounts` | accounts and their mailboxes | id, name, per-account mailbox names |
| `pippin_mail_search` | find messages | summary rows + `next_cursor` |
| `pippin_mail_get` | one message | headers + body, size-capped |

Three tools, all read-only. `search` parameters: `account_id`, `mailbox`, `from`,
`to`, `subject_contains`, `date_from`, `date_to`, `unread_only`, `limit`,
`cursor`. Semantic validation: date range ordering, mailbox existence →
`not_found` rather than an empty result, `limit` clamped to the server cap.

## 3. Output Shape

Search row — deliberately minimal, because search results are the high-volume
output in this module:

```json
{
  "id": "…",
  "subject": "…",
  "from": "name <addr>",
  "date": "2026-08-17T09:12:00+08:00",
  "unread": true,
  "snippet": "first ~140 chars…"
}
```

`pippin_mail_get` adds recipients, mailbox, and the body. Body is capped at a
configured byte size with an explicit `"truncated": true` marker — a silently cut
body is worse than a marked one, because the agent will reason over it as if
complete.

## 4. Envelope Index Backend

- Resolve the versioned directory by globbing `~/Library/Mail/V*/` and selecting
  the highest version present. No hard-coded version anywhere (AC4).
- Open read-only. Never write, never migrate, never `VACUUM`.
- Queries parameterized; caller input never interpolated into SQL (AC5).
- **Schema probe at startup:** verify that the specific tables and columns the
  queries depend on exist, and that a trivial query returns without error. Record
  the probe result. On failure, disable the backend with a reason string, and
  surface that reason through `pippin_status` (AC10).
- Full Disk Access is required. Its absence typically surfaces as a file-open
  failure, which must map to `backend_unavailable` with a hint naming the System
  Settings pane — never to an empty result set (AC2).

Mail may hold the database while running; read-only access is expected to be
tolerable, but concurrent-access behaviour is an explicit step-0 verification, not
an assumption.

## 5. AppleScript Backend

- All calls go through the skeleton's `AppleScriptRunner`: parameters passed as
  Apple Event arguments, never interpolated into script text, and every call
  bounded by a wall-clock timeout.
- If Mail is not running, return `app_not_running` with a hint. Do not launch Mail
  as a side effect of a read — an agent's read should not open an application on
  the user's screen.
- Timeout maps to `timeout`. Because the resident server is shared, a pending
  Mail call must not block other clients; the backend runs off the actor's
  critical path with only its own state serialized (AC7).

## 6. Degradation Semantics

The single rule this module exists to prove: **absence of permission or presence
of schema drift is an error, never an empty result.**

```
search:
  SQLite backend available?      → use it
  probe failed / FDA missing?    → AppleScript fallback available and Mail running?
                                     yes → use it, and mark the response degraded
                                     no  → backend_unavailable + hint
```

A degraded response carries a marker so the caller knows results may be narrower
than the primary backend would return. Silence about degradation would let an
agent conclude "no such mail exists" from "we could not look properly".

## 7. Testing

**Unit, no permissions, no real mail — the bulk of coverage:** both backends
behind protocols and faked. Cases: primary available; probe failed → fallback;
probe failed and Mail not running → `backend_unavailable`; FDA missing →
fallback or error but never empty; timeout → `timeout`; date-range and limit
validation; snippet and body capping; degraded marker present exactly when a
fallback served the request (AC11).

A dedicated test asserts that a failed probe never yields a zero-row success —
this is the specific bug class the module is designed against.

**Integration, `PIPPIN_INTEGRATION=1`:** read-only throughout, so there is no
fixture-mutation risk. Runs against the real mailbox but asserts only shape and
non-emptiness, never specific message content.

**Manual:** revoke Full Disk Access and confirm AC2; quit Mail and confirm AC6;
point the probe at a wrong expectation and confirm AC3.

## 8. Risks

| Risk | Handling |
|---|---|
| Envelope Index schema differs from expectation | Startup probe; disable with a recorded reason; fallback |
| Schema changes on a future OS update | Same probe path; the module degrades instead of breaking |
| Mail locks the database | Verified in step 0; read-only open; fall back on failure |
| FDA missing and mistaken for "no mail" | AC2 plus the never-empty-on-failure test |
| Mail AppleScript hangs | Wall-clock timeout, off the shared critical path |
| SQLite path proves too unstable to keep | Legitimate outcome: default the backend off and keep AppleScript; decide within this task |
