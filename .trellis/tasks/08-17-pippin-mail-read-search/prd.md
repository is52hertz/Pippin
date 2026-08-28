# Pippin: Mail Read and Search Vertical Slice

Child of `08-17-pippin-mcp-server`. Read the parent's `prd.md` and `design.md`
first.

## Goal

Read-only Mail access — list accounts and mailboxes, search messages, fetch a
message — implemented over two backends so the parent's routing-and-degradation
model is proven on the one case that actually needs it.

Mail is the second module because it is the capability the installed server
lacks entirely ("cannot get mail"), and because it is the only batch-one module
where the fast path is a private SQLite store and the correct path therefore
requires a real fallback. Reminders proves writes and deletes; Mail proves
routing.

## Requirements

- **R1 — Read-only module.** No send, no move, no flag, no delete. Writes are
  out of scope, so this module has no destructive surface at all.
- **R2 — Tool set.** `pippin_mail_accounts`, `pippin_mail_search`,
  `pippin_mail_get`. All `readOnlyHint: true`.
- **R3 — Two backends, explicit routing.** Search prefers the Mail Envelope Index
  SQLite store because AppleScript search over a real mailbox is slow enough to
  be unusable; message fetch uses AppleScript (or the on-disk message file).
  Routing is declared per capability, not per module.
- **R4 — Degradation is mandatory, silence is forbidden.** When the SQLite backend
  is unavailable — Full Disk Access missing, versioned path not found, schema
  probe failed — the capability either falls back to AppleScript or returns
  `backend_unavailable` with an actionable hint. A missing permission must never
  produce an empty result set.
- **R5 — Schema drift is assumed.** The Envelope Index schema is private and
  changes across OS versions. A startup probe verifies the tables and columns
  actually used; a failed probe disables the backend and records why.
- **R6 — Token-lean by construction.** Search returns subject, sender, date, and
  a short snippet. Message bodies are only ever returned by `pippin_mail_get`,
  one message at a time, with a size cap and explicit truncation marker.
- **R7 — Bounded work.** Every AppleScript call to Mail carries a wall-clock
  timeout; a hung Mail query must not hold the resident server for other clients.

## Non-Requirements

- No Mail writes of any kind. Scheduled for batch three (send, move, flag), under
  the same two-phase protocol.
- No full-text indexing of our own, and no Spotlight backend in this slice.
- No attachment extraction.
- No other mail clients.

## Acceptance Criteria

- [ ] **AC1** With Full Disk Access granted, `pippin_mail_search` returns results
      from the SQLite backend, and `pippin_mail_get` returns a body.
- [ ] **AC2** With Full Disk Access revoked, search does not return an empty
      list: it either serves results via the AppleScript fallback or returns
      `backend_unavailable` with a hint naming the pane to grant access in.
- [ ] **AC3** Pointing the schema probe at a deliberately wrong expectation
      disables the SQLite backend at startup, records the reason, and routes to
      the fallback — it does not crash and does not return zero rows.
- [ ] **AC4** The versioned Mail data directory is resolved dynamically; a
      hard-coded version path appears nowhere in the source.
- [ ] **AC5** SQLite is opened read-only and every query is parameterized. No
      query is assembled by string interpolation of caller input.
- [ ] **AC6** With Mail not running, an AppleScript-backed call returns
      `app_not_running` with a hint, rather than silently launching Mail or
      hanging.
- [ ] **AC7** An artificially slowed AppleScript call hits the timeout and returns
      `timeout`; other clients' requests are served normally while it is pending.
- [ ] **AC8** A 50-result search is checked against a byte ceiling; snippets are
      length-capped; `limit` above the server cap is clamped.
- [ ] **AC9** `pippin_mail_get` caps body size and marks truncation explicitly.
- [ ] **AC10** `pippin_status` reports the Mail SQLite backend's availability and,
      when unavailable, the reason.
- [ ] **AC11** Unit tests cover routing decisions and every degradation branch
      with both backends faked — no permissions and no real mail required.

## Constraints and Notes

- Depends on `08-17-pippin-skeleton-transport` gate G2 and on
  `08-29-pippin-architecture-reuse-safety-hardening` replacing the live-SQLite
  opening policy and adding AppleScript execution budgets. Do not start
  implementation before both.
- Independent of `08-17-pippin-reminders-crud`; either may land first after the
  shared hardening prerequisite.
- Full Disk Access must be granted to `Pippin.app` itself. This is a second,
  separate TCC grant from Automation and is the most likely source of confusing
  failures — hence AC2 and AC10.
- Reading the Envelope Index is explicitly a best-effort optimisation, not a
  contract. If it proves too unstable in practice, the correct outcome is to keep
  the AppleScript path and disable the SQLite backend by default — that decision
  belongs to this task, not a future one.
