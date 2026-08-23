# Pippin — Cross-Module Technical Design

Scope: the architecture shared by all modules. Per-module design lives in each
child task's `design.md` and must not contradict this file.

## 1. Architecture Overview

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│ Claude Code  │   │ Codex        │   │ other agent  │
└──────┬───────┘   └──────┬───────┘   └──────┬───────┘
       │ HTTP              │ stdio            │ HTTP
       │                   ▼                  │
       │           ┌───────────────┐          │
       │           │ pippin-shim   │  ephemeral framing state; no TCC needs
       │           └──────┬────────┘          │
       ▼                  ▼                   ▼
   ┌─────────────────────────────────────────────────┐
   │ Pippin.app  (single resident process)           │
   │  ┌───────────────────────────────────────────┐  │
   │  │ HTTP listener  127.0.0.1  (ours — O4)     │  │
   │  │  + bearer-token / Origin validators       │  │
   │  ├───────────────────────────────────────────┤  │
   │  │ Session table: sessionID → Server + tport │  │
   │  │  (swift-sdk; one pair per client)         │  │
   │  └──────────────────┬────────────────────────┘  │
   │  ┌──────────────────▼────────────────────────┐  │
   │  │ Tool Registry  (module gating, budget)    │  │
   │  └──────────────────┬────────────────────────┘  │
   │  ┌──────────────────▼────────────────────────┐  │
   │  │ Mutation Gate → Confirm-Token Store       │  │
   │  │              → Audit Log                  │  │
   │  └──────────────────┬────────────────────────┘  │
   │  ┌──────────────────▼────────────────────────┐  │
   │  │ Modules: Reminders │ Mail │ (future…)     │  │
   │  └──────────────────┬────────────────────────┘  │
   │  ┌──────────────────▼────────────────────────┐  │
   │  │ Backends: Framework │ AppleScript │ SQLite│  │
   │  └───────────────────────────────────────────┘  │
   │  SwiftUI MenuBarExtra + Settings (HIG)          │
   └─────────────────────────────────────────────────┘
```

The `.app` is the only process that touches user data, so it is the only process
that needs TCC grants — which is exactly why the identity must be stable.

## 2. Process and Transport Topology

**One resident process, one shared state core, one `Server` per client.**
Rationale (from the requirement set): per-client stdio spawning fragments
`EKEventStore` instances, confirmation tokens, and timeout state into copies that
cannot see each other.

The earlier phrasing here said "one resident instance" and named a transport
initialiser that does not exist. Corrected against swift-sdk 0.12.1 source — see
`../08-17-pippin-skeleton-transport/research/swift-sdk-surface.md`:

- `StatefulHTTPServerTransport` takes **no port and no host**. It is a
  framework-agnostic `HTTPRequest → HTTPResponse` handler; the listener is ours to
  supply. How we supply it is open decision **O4**.
- Each transport instance owns exactly one MCP session and refuses a second
  `initialize`. Serving several agents therefore means a session table —
  `sessionID → (Server, transport)` — with a fresh `Server` per connecting client,
  which is the SDK's own supported pattern.
- The single-instance requirement is unchanged; it just lands one level down. All
  state whose fragmentation motivated it — `EKEventStore` and module backends,
  `ConfirmTokenStore`, `AuditLog`, `MutationGate`, `Config`, `TokenStore` — lives
  in a process-level core injected into every per-session `Server`. Only the
  server object, its transport, its handlers, and the caller's resolved capability
  set are per-session.
- Session identity is available inside tool handlers via the
  `Server.currentHandlerContext` task-local (`httpContext: HTTPRequest?`), and
  more simply still by capturing it when the per-session `Server` is built. This
  is what criterion A2's confirm-token session binding rests on; it is confirmed
  present.
- Session management and SSE framing come from the SDK; an SSE response arrives as
  `HTTPResponse.stream(AsyncThrowingStream<Data, Error>)` for the listener to pipe.
- Compatibility transport: `pippin-shim`, a separate tiny executable that speaks
  `StdioTransport` to the client and forwards to the resident HTTP endpoint. It
  does not interpret or rewrite JSON-RPC payload business content, but it must
  convert newline, HTTP POST, SSE, and session-header framing. It therefore holds
  per-connection ephemeral endpoint/session/in-flight state, including the
  bearer token in memory only; all of it disappears on exit. It holds no shared
  or persistent business state, security decisions, Apple data, or TCC handles.

**Endpoint discovery.** The app writes
`~/Library/Application Support/Pippin/endpoint.json` (mode `0600`) containing the
bound port and the bearer token. The shim reads it. If the app is not running,
the shim launches it by bundle identifier and waits for readiness with a bounded
timeout, then fails with an actionable message rather than hanging.

Storing the token in a `0600` file rather than the Keychain is deliberate: a
separate binary reading a Keychain item triggers its own authorization prompts,
and the file already sits inside the user's own protected home directory on a
single-user machine. Recorded as an accepted tradeoff.

**Two mandatory HTTP validators:**
1. Bearer token match — reject with 401 otherwise.
2. `Origin` header absent, or localhost — reject otherwise. This blocks
   DNS-rebinding from a browser on the same machine, the one real attack surface
   a localhost HTTP listener adds.

## 3. TCC Identity and Packaging

SwiftPM cannot emit an `.app` bundle, and an `NSApplication`-based menu bar app
needs one (activation policy, `LSUIElement`, `Info.plist` usage strings, and a
stable signature for TCC). Therefore: SwiftPM builds the binaries, a packaging
script assembles and signs the bundle.

The `apple-skills` plugin's `guide-macos-spm-packaging` skill provides directly
usable templates — `setup_dev_signing.sh` (create a stable dev signing
identity), `package_app.sh` (assemble bundle, `MENU_BAR_APP=1` emits
`LSUIElement`), `compile_and_run.sh` (dev loop). Adapt these rather than writing
packaging from scratch.

`Info.plist` must carry: `LSUIElement=true`, `NSAppleEventsUsageDescription`,
`NSRemindersFullAccessUsageDescription`, and a stable `CFBundleIdentifier`.
Not sandboxed, so no entitlements file is needed for EventKit or Apple Events.

**Never run the server via `swift run`** for anything permission-dependent — the
raw build product has a different (or absent) signature and will re-prompt or
silently fail. Only the packaged, signed bundle is a supported run path.

## 4. Backend Routing Ladder

```
1. Native framework   (EventKit, Contacts, MapKit, …)   preferred
2. AppleScript        (Apple Events, via osascript)     when no framework
3. Read-only SQLite   (private app stores)              only for speed, w/ fallback
```

Selection is per *capability*, not per app: Mail search uses SQLite while Mail
body fetch uses AppleScript. A module declares, per capability, an ordered list
of backends plus what to do when all fail.

**AppleScript rules (non-negotiable):**
- Agent-supplied values are never interpolated into script text. Parameters go
  through Apple Event arguments (`osascript … -e 'on run argv'` style). String
  interpolation here is a script-injection hole with the full privileges of the
  resident app.
- Every invocation carries a wall-clock timeout. Apple Events default to two
  minutes; a hung Mail query would otherwise wedge the resident server for every
  client. Timeout surfaces as an explicit error.
- Reads prefer non-AppleScript backends where available, because `osascript`
  spawn cost plus target-app work is orders of magnitude slower than a framework
  call and can block the target app's UI.

**SQLite rules:** open read-only, resolve versioned paths dynamically (e.g.
`~/Library/Mail/V*/`), and probe the expected tables and columns at startup.
A failed probe disables that backend and records why; it never degrades into
returning zero rows.

## 5. Tool Surface and Token Budget

The tool list is injected into every request on every client, so it is the
dominant recurring cost of "broad connectivity". Controls:

- **One tool per verb** — required for per-tool `destructiveHint` / `readOnlyHint`.
- **Module gating** — only enabled modules contribute tools. Disabled means
  absent from `tools/list`, not present-and-erroring (parent criterion A6).
- **Write gating** — a module with writes disabled contributes only its
  read-only tools.
- **Terse descriptions** — ≤ 200 characters, no examples, no prose. The input
  schema carries the detail.
- **`outputSchema`** where the shape is stable, so the agent need not be told
  the shape in prose.
- Config changes emit `notifications/tools/list_changed`.

Budget is asserted by a test that serializes `tools/list` and compares byte
counts against the parent's A3 figures.

## 6. Data Shape Conventions

Uniform across modules:

- Stable opaque string IDs, round-trippable back into `_get` tools.
- ISO-8601 with offset for all timestamps; no locale-formatted dates.
- Null and empty fields pruned from output entirely.
- List tools take `limit` (with a server-side hard cap) and return an opaque
  `next_cursor` only when more results exist.
- Summaries in list results, full payloads only from `_get` — e.g. Mail search
  returns subject/from/date/snippet; the body requires `pippin_mail_get`.
- Derived or verbose structures are collapsed to a short human-readable string
  rather than dumped as nested objects (recurrence rules, for example).

## 7. Mutation Safety Model

**Write gate.** Per module, from config. Off by default. Enforced at registry
level (tools absent) and re-checked at call time.

**Two-phase delete.** One destructive tool per module, with a
`confirm_token` parameter:

- Called *without* `confirm_token`: performs nothing. Returns the resolved
  preview of exactly what would be deleted, plus a `confirm_token` and its
  `expires_at`.
- Called *with* `confirm_token`: validates that the token exists, has not
  expired, has not been used, originated from the same MCP session, and that the
  submitted ID set hashes identically to the one the token was minted for. Only
  then does it delete.
- Annotations: `destructiveHint: true`, `readOnlyHint: false`,
  `idempotentHint: false`.
- Deletes accept explicit ID lists only. No predicate, filter, or "delete all
  matching" form exists (parent criterion A2).
- Item count per destructive call is capped.

The preview arm lives on the destructive tool rather than in a separate
read-only tool. Clients that gate destructive tools will therefore prompt on the
preview too — conservative in the right direction, and it avoids doubling the
tool count.

This design deliberately does not use MCP `elicitation` for confirmation: it is
not implemented across the clients in scope. Human confirmation is delivered by
the client's own tool-approval UI, which every target client has.

**Prefer non-destructive equivalents.** Where an app models a softer outcome,
expose it as its own non-destructive tool so an agent naturally reaches for it —
completing a reminder instead of deleting it, moving mail to Trash instead of
erasing it. Tool descriptions point at the softer verb.

**Audit log.** Every mutation attempt appends one JSON line to
`~/Library/Application Support/Pippin/audit.jsonl`: timestamp, tool, affected
IDs, outcome, and a digest of arguments. Size-capped with rotation. Cheap, and
it is the only forensic trail for "what did the agent just do".

## 8. iCloud Sync Model

- **Never hold a long-lived framework store across requests without
  invalidation.** A resident process is exactly the shape that accumulates stale
  state. Refresh on change notification (e.g. `EKEventStoreChanged`) or use a
  fresh store per request.
- **Every write re-reads.** After committing, fetch the object back by
  identifier and return that canonical form. If the re-read fails, report
  `sync_pending` rather than claiming success.
- **Account availability is a real startup race.** An empty source/account list
  right after launch usually means iCloud has not loaded yet, not that the user
  has no data. Refresh and retry once before reporting empty.
- No claim is made that a write is visible on the user's other devices. That is
  outside the process's knowledge and must not be implied in tool output.

## 9. Configuration

`~/Library/Application Support/Pippin/config.json`:

```json
{
  "modules": {
    "reminders": { "enabled": true, "writes": false },
    "mail":      { "enabled": true, "writes": false }
  },
  "escape_hatch": { "enabled": false, "allowed_apps": [] },
  "http": { "port": 0, "bind": "127.0.0.1" }
}
```

Written and edited by the Settings window; hand-editing is also supported. A
change re-derives the tool registry and emits `tools/list_changed`. `bind` is
validated to be a loopback address and rejected otherwise — constraint C1 is
enforced in code, not by convention.

## 10. Error Model

Tool failures return `isError: true` with a compact machine-readable body — kept
short because errors are tokens too:

```json
{"error":{"code":"backend_unavailable","detail":"envelope_index","hint":"grant Full Disk Access to Pippin.app"}}
```

Codes: `permission_denied`, `backend_unavailable`, `app_not_running`,
`timeout`, `not_found`, `invalid_argument`, `confirmation_required`,
`confirmation_invalid`, `writes_disabled`, `sync_pending`.

Every code carries an actionable `hint` where a user action can fix it. A
missing permission must never surface as an empty result set (criterion A7).

## 11. Security Boundary

The trust boundary is the loopback HTTP listener. Beyond it:

- Bind loopback only, enforced in code.
- Bearer token plus Origin validation on every request.
- Agent-supplied input is validated at the boundary and never reaches a shell,
  a script body, or a SQL string by interpolation. SQLite access is parameterized
  and read-only; AppleScript access is parameterized via Apple Event arguments.
- No arbitrary code execution path in batch one. The escape hatch that would
  introduce one is deferred and lands default-off behind an allowlist.
- No secrets in logs or tool output. The audit log records argument digests, not
  argument values.

## 12. Testing Strategy

The project profile in `AGENTS.md` requires tests, but most behaviour here is
gated by TCC and bound to the user's real data. Tests split in three:

**Unit (`swift-testing`), no permissions needed — the bulk of coverage:**
DTO pruning and shaping; input validation; AppleScript argument escaping;
backend routing decisions and degradation; confirm-token lifecycle (TTL,
single-use, ID-set binding, session binding); registry gating (writes off ⇒ tool
absent); `tools/list` byte budget; loopback-bind validation.

**Integration, opt-in via `PIPPIN_INTEGRATION=1`:** runs against dedicated
fixtures only — a Reminders list named `Pippin Test`, a dedicated Mail mailbox.
The harness refuses to run against any container not matching the test-fixture
name, so a misconfigured run cannot touch real data.

**Manual checklist:** TCC prompt behaviour across rebuilds, GUI/HIG review,
cross-agent smoke (criterion A5). Use the existing
`Test/templates-test-checklist.html` template.

## 13. Repository Layout

```
Package.swift
version.env
Scripts/            setup_dev_signing.sh, package_app.sh, compile_and_run.sh
Sources/
  PippinCore/       config, DTO conventions, error model, mutation gate,
                    confirm-token store, audit log, AppleScript runner,
                    SQLite reader, backend routing
  PippinModules/    per-app modules (Reminders, Mail, …)
  PippinServer/     MCP server wiring, transport, validators, tool registry
  PippinApp/        SwiftUI MenuBarExtra + Settings; hosts the server (→ .app)
  pippin-shim/      stdio ⇄ HTTP bridge executable
Tests/
```

## 14. Reserved: Generic Escape Hatch (Batch Three)

Design position is settled; implementation is deferred. It will add two tools to
`PippinModules`:

- `pippin_script_run` — parameterized AppleScript execution against an
  allowlisted target app. `openWorldHint: true`, `destructiveHint: true`,
  default disabled via `escape_hatch.enabled`.
- `pippin_app_dictionary` — returns a trimmed `sdef` scripting dictionary for an
  allowlisted app so an agent can discover available commands. Read-only.

It needs no new core primitives beyond what batch one builds (allowlist check,
audit log, AppleScript runner, timeout), so deferring it costs no rework. The
security review it requires — arbitrary Apple Events carry the resident app's
full privileges — is what justifies its own task.
