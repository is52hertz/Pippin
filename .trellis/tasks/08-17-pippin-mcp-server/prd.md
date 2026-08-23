# Pippin: macOS App-Ecosystem MCP Server

Parent task. Owns the source requirement set, the child task map, cross-child
acceptance criteria, and final integration review. This parent has no direct
implementation work; do not `task.py start` it.

## Goal

A personal, local-only MCP server that exposes macOS applications to coding
agents (Claude Code, Codex, and others) as a lean, validated, structured tool
surface — replacing hand-written AppleScript as the day-to-day way to query and
act on local app data.

Motivation: the installed third-party `iMCP` server wraps too little (no
delete, unreliable Reminders access, no Mail), and its scope is Apple-only.

## Requirements

- **R1 — Broad connectivity.** Reach as many local macOS apps as possible, not
  limited to Apple's own. Coverage grows by adding curated per-app modules.
- **R2 — Lean structured output.** Minimal structured DTOs per domain: stable
  IDs, ISO-8601 timestamps, null fields pruned, list results paginated and
  capped. Inputs are schema-validated plus semantically validated.
- **R3 — Cross-agent.** Must work on more than one harness. No dependency on
  client-specific MCP features that are unevenly implemented (notably
  `elicitation` and `sampling`).
- **R4 — Token frugality.** The always-injected tool surface is a per-request
  cost and is treated as a hard budget, not an afterthought.
- **R5 — Non-destructive by default.** Reads are the default capability; writes
  are opt-in; deletes require explicit confirmation. Behaviour under iCloud
  sync must be correct and honestly reported.
- **R6 — AppleScript replacement.** For the covered surface, Pippin should be
  the tool an agent reaches for instead of `osascript`. Anything AppleScript can
  do must eventually be reachable, via a curated module or a guarded generic
  escape hatch.

## Constraints

- **C1 — Single user, local only.** Personal tool. The server must never bind
  to an interface other than `127.0.0.1`.
- **C2 — Unsandboxed, not App Store.** Sandboxing would block Apple Events to
  arbitrary apps and Full Disk Access. Requires Automation, Full Disk Access,
  and EventKit TCC grants.
- **C3 — Stable code-signing identity is mandatory.** TCC grants are keyed to
  the binary's signature. An identity that changes per build makes every
  permission grant drift — this is the suspected root cause of the existing
  server's flaky Reminders access. Free-tier self-signed identity (O2), so the
  identity must be created once and never regenerated.
- **C4 — Build target.** macOS 26 SDK, Swift 6 language mode. GUI must follow
  HIG and use standard controls and system materials (Liquid Glass comes from
  building against the macOS 26 SDK); no custom-drawn chrome.
- **C5 — Dependencies.** Two third-party dependencies, both user-approved and
  both first-party-adjacent: `modelcontextprotocol/swift-sdk` (official MCP SDK,
  O1) and `apple/swift-nio` (HTTP/1.1 + SSE listener, O4 — the SDK ships no HTTP
  server). NIO is used only by `PippinServer`. Nothing else without a new
  decision.
- **C6 — Naming.** Product name Pippin; MCP server name and tool prefix
  `pippin`. Repository directory name stays `iMCP` for now. Distinct naming
  keeps the old server installable side-by-side during transition.

## Decided Design Positions

Settled with the user before planning; children inherit these and must not
relitigate them.

1. **Delivery form:** signed `.app` bundle with a long-lived signing identity —
   a fixed self-signed keychain identity, since no paid Apple Developer account
   is available (O2). Notarization is therefore permanently out of reach.
2. **Process topology:** exactly one resident instance owns all state. Per-client
   `stdio` spawning is rejected — it would fragment `EKEventStore` instances,
   delete-confirmation tokens, and timeout management into mutually unaware
   copies. The resident app serves localhost Streamable HTTP; a thin `stdio`
   shim provides compatibility for stdio-only clients.
3. **Tool granularity:** one tool per verb. Never a single tool with an `action`
   discriminator. Decisive reason: MCP tool annotations (`destructiveHint`,
   `readOnlyHint`) are declared per tool, so the delete-confirmation protocol
   cannot be expressed at all if a destructive verb shares a tool with reads.
   Tool count is controlled by per-module enable/disable plus terse descriptions.
4. **Backend routing ladder:** native framework → AppleScript → read-only
   SQLite. Shortcuts / App Intents is explicitly *not a routing tier*: there is
   no public API for a daemon to invoke another app's App Intents, only the
   `shortcuts run` CLI against user-pre-built shortcuts, so it can never be an
   abstraction layer that other capabilities route through.

   It does, however, get to be a module of its own in batch two — a
   *user-curated* one. Only shortcuts placed in one designated folder in
   Shortcuts.app (working name `AI`) are exposed; putting a shortcut in that
   folder *is* the authorization act, which keeps the list short and the
   accidental surface zero. Tools: `pippin_shortcuts_list` (folder-scoped),
   `pippin_shortcuts_run` (official CLI, one input slot, wall-clock timeout like
   every other backend), and `pippin_shortcut_create` (agent drafts the workflow
   plist → `shortcuts sign` → the user confirms the import dialog in
   Shortcuts.app; that human gate is the safety model, and since the plist action
   format is community-reverse-engineered, the tool description must say plainly
   that common actions generate reliably while complex or third-party ones
   degrade). It earns module status because the capability surface is authored by
   the user's own hands — the agent can trigger, never rewrite — and because the
   `shortcuts` CLI is the only official bridge to Focus modes, HomeKit, and the
   App-Intents-only app world that AppleScript cannot reach.
5. **SQLite backends are assumed breakable.** Private schema, changes across OS
   versions, needs Full Disk Access. Every SQLite backend must have a
   degradation path — fall back to AppleScript, or return an explicit
   backend-unavailable error. Never a silent empty result. Only Mail gets a
   SQLite backend in batch one.
6. **Generic escape hatch** (`script_run` + `app_dictionary`): design adopted —
   default off, App allowlist, destructive verbs never auto-approved — but
   *scheduled out of batch one*. It validates none of the three highest-risk
   items and its security design deserves its own task. `design.md` §14 reserves
   its place. With the Shortcuts module now covering part of the long tail
   through a channel with a human gate, its priority drops further to batch
   three; the design position itself is unchanged.
7. **Health is only reachable off-Mac.** macOS has no HealthKit, so health data
   is permanently out of reach for any process here. The gap is closed by the
   user's own companion iOS app, Exporter
   (`github.com/is52hertz/Exporter`), which exports read-only HealthKit data as
   versioned LLM-friendly JSON. Pippin's role is ingest → local accumulating
   archive → query tools. Ingest is **push-only**: "Mac pulls from iPhone over
   GET" is rejected, because iOS will not keep a background listener alive and a
   pull would routinely find nobody home. Stage one (batch two) watches a shared
   iCloud Drive folder, which leaves C1 untouched; stage two (batch four) adds a
   LAN POST endpoint once per-token permission tiers exist, and a non-2xx
   response must not advance Exporter's incremental anchor.
8. **Remote access is additive, never a change to C1.** Tunnel daemons
   (Cloudflare Tunnel, Tailscale Funnel, ngrok) connect to `127.0.0.1`
   themselves, so exposing Pippin to cloud agents never requires binding
   anything else. When built (batch four) it requires multiple bearer tokens
   with per-token permission tiers — a remote token sees read-only tools only,
   because the prompt-injection blast radius of a web agent must not include
   destructive tools — plus a default-off remote-access switch and separate
   token minting and revocation. **The one thing asked of batch one:** shape the
   token validation model so that "N tokens, each mapped to a tier" is a natural
   extension. Implementing a single token now is fine; hardcoding
   one-token-equals-full-access deeply enough to force a rework later is not.

## Child Task Map

| Child | Deliverable | Batch |
|---|---|---|
| `08-17-pippin-skeleton-transport` | Signed `.app`, HIG menu-bar GUI, resident HTTP transport + stdio shim, and the cross-cutting core primitives (config, mutation gate, confirm-token store, audit log, DTO conventions, error model, AppleScript runner) | 1 |
| `08-17-pippin-reminders-crud` | Reminders module: full CRUD over EventKit, two-phase delete, iCloud-sync-correct writes | 1 |
| `08-17-pippin-mail-read-search` | Mail module: read-only search and fetch, proving multi-backend routing and degradation | 1 |

**Ordering:** the skeleton child owns primitives the other two consume, so it
lands first. Reminders and Mail are independent of each other. This ordering is
recorded in each child's `implement.md`; parent/child linkage itself carries no
dependency semantics.

## Cross-Child Acceptance Criteria

These are the parent's own gates, verified at integration review after all three
children are checked.

- [ ] **A1 — TCC identity stability.** Across three consecutive
      rebuild-and-repackage cycles, `codesign -dv` reports an unchanged signing
      identity and a permission-dependent tool call keeps succeeding with no new
      TCC prompt.
- [ ] **A2 — Uniform two-phase delete.** Every destructive tool in every module
      uses the same protocol: a call without a confirmation token performs
      nothing and returns a preview plus a token; the token is single-use,
      TTL-bounded, bound to the exact ID set and the requesting session. No
      predicate-based or filter-based delete path exists anywhere in the tool
      surface.
- [ ] **A3 — Tool surface budget.** With batch-one modules enabled, serialized
      `tools/list` output is ≤ 6 KB. The long-term ceiling for the full default
      module set is ≤ 16 KB and ≤ 40 tools, with every tool description ≤ 200
      characters. Enforced by an automated test, not by review.

      The batch-one figure was raised from 4 KB to 6 KB (O3). 4 KB across 11
      tools is ≈ 370 bytes per tool, but a `create`/`update` tool's input schema
      alone — seven or eight typed, described parameters — realistically costs
      600–800 bytes. The tighter figure would have been met by cutting parameter
      descriptions, which directly degrades the agent's call accuracy, i.e. by
      trading away the thing the budget exists to protect.
- [ ] **A4 — Single-owner state.** Two clients connected concurrently observe
      consistent state; the shim holds no state of its own; only one process
      holds EventKit / Apple Event / SQLite handles.
- [ ] **A5 — Cross-agent smoke.** Claude Code and Codex each complete one read
      and one guarded write end to end, one through HTTP and one through the shim.
- [ ] **A6 — Non-destructive default is structural.** With writes disabled for a
      module, its mutating tools are *absent from `tools/list`* — not present and
      erroring. Absence is what keeps them out of the token budget and out of the
      agent's consideration.
- [ ] **A7 — Honest failure.** Every backend-unavailable condition (missing
      permission, schema drift, app not running, Apple Event timeout) surfaces as
      an explicit error with an actionable hint. No silent empty results.

## Out of Scope for Batch One

Everything here is scheduled, not rejected — see Roadmap. Permanent non-goals are
listed separately at the end of the Roadmap.

- `script_run` / `app_dictionary` generic AppleScript escape hatch (batch three).
- Further modules: Calendar, Contacts, Shortcuts, Screen Time, Health, Clipboard
  and OCR, Spotlight, Notes, Messages, Safari, Finder, Music, and non-Apple apps.
- Mail write operations (send, move, flag) — batch three.
- Multiple bearer tokens and per-token permission tiers — batch four. Batch one
  only has to avoid foreclosing them (Decided Position 8).
- Remote access and cloud-agent connectors — batch four.
- Notarization and distribution to other machines. Local self-signing only, and
  permanently so (O2).

## Resolved Decisions

O1–O3 answered by the user in `addendum-2026-08-18.md` §1.

- [x] **O1 — Dependency approved.** `modelcontextprotocol/swift-sdk` as the sole
      third-party dependency. It supplies the protocol types, tool annotations,
      `StatefulHTTPServerTransport` (session management, SSE framing, and an
      `HTTPRequestValidator` pipeline for the bearer-token and Origin checks) and
      `StdioTransport` for the shim. Corrected 2026-08-23 against the 0.12.1
      source: the transport does **not** bind a socket — it has no port or host
      parameter and is an `HTTPRequest → HTTPResponse` handler. The listener is
      ours to provide, which is what O4 decides.
- [x] **O2 — Free-tier self-signed identity.** No paid Apple Developer account,
      so `Scripts/setup_dev_signing.sh` takes the fixed self-signed keychain
      identity path. Developer ID and notarization are out of reach and out of
      scope. Consequence beyond signing: WeatherKit is unavailable to this
      project, since it requires a paid account.
- [x] **O3 — Budget approved with the batch-one figure raised to 6 KB.** See A3
      for the reasoning. Long-term figures unchanged.

- [x] **O4 — HTTP listener: swift-nio.** Raised 2026-08-23 by step-0
      verification (`../08-17-pippin-skeleton-transport/research/swift-sdk-surface.md`).
      swift-sdk ships no HTTP server, so C5's "exactly one dependency" cannot be
      read as "no listener work". Three options, all compatible with everything
      else already decided:

      1. **swift-nio + NIOHTTP1** — what the SDK's own conformance server uses.
         Battle-tested HTTP/1.1 and SSE. Costs a second declared dependency,
         though `swift-nio` is *already* in `Package.resolved` transitively via
         swift-sdk, so it adds a manifest line and a build, not a new package in
         the resolution graph.
      2. **Network.framework (`NWListener`)** — zero new dependencies, first-party,
         already linked by any macOS app. Costs hand-written HTTP/1.1 request
         parsing and SSE chunk framing: a few hundred lines we then own and must
         keep correct, on the process's one network-facing surface.
      3. **Defer the HTTP listener; ship stdio first.** Batch one exposes only
         `StdioTransport`, one process per client. Cheapest path to a working
         Reminders slice, but it forfeits the single-resident-process property
         that the shared `EKEventStore`, confirm-token store, and audit log were
         designed around — i.e. it defers the architecture, not just the code.

      **Answered 2026-08-23: option 1, swift-nio.** Rationale accepted — SSE
      streaming plus `Last-Event-ID` resumability is real protocol surface to hand
      -write, and it sits on the process's only externally reachable port; option
      3 would have forced a transport rewrite in batch two. C5 is amended: the
      dependency set is `modelcontextprotocol/swift-sdk` **and** `apple/swift-nio`,
      the latter used only by `PippinServer` for the HTTP/1.1 + SSE listener.
## Relationship to Task `00-bootstrap-guidelines`

`AGENTS.md` still carries TODO placeholders (Product, Project Phase, Coding
Standards, Data integrity & concurrency) and every file under `.trellis/spec/` is
an unfilled template. That is the pre-existing `00-bootstrap-guidelines` task's
scope, not this one's.

Those placeholders are best filled *from* this design rather than guessed at
beforehand — the source of truth, module boundaries, and security boundary this
project needs are exactly what the parent `design.md` settles. Sensible
sequencing: land the skeleton child, then close `00-bootstrap-guidelines` using
the now-concrete architecture. Until then, the child tasks' context manifests
deliberately reference the parent's artifacts instead of the empty spec files.

## Roadmap

From `addendum-2026-08-18.md` §7. Batches two and later are **route-level only** —
child tasks get created when the work actually starts, per Trellis. The full
official-interface inventory this roadmap rests on (tiers A–D: public frameworks,
sanctioned AppleScript dictionaries, official CLIs, private databases) is in the
addendum §6 and is the reference for what is reachable at all.

Ordering logic: batch two is official-channel, read-heavy horizontal scaling.
Write expansion and the escape hatch concentrate in batch three because they all
share batch one's safety primitives. Everything needing token tiers lands
together in batch four, so the security mechanism is never half-built.

**Batch 1 — planned, task-level (this task tree):**
skeleton/transport · Reminders CRUD · Mail read/search.

**Batch 2 — high value, low risk:**
- Calendar (EventKit; shares most of the Reminders module's code — the cheapest
  module in the whole roadmap)
- Contacts
- Shortcuts module (Decided Position 4)
- **Screen Time — schedule early.** Its source
  (`~/Library/Application Support/Knowledge/knowledgeC.db`) has a ~4-week rolling
  retention, verified: `/app/usage` 8 302 rows and `/app/webUsage` 911 rows over
  2026-07-21 → 2026-08-17, with older data unrecoverable. The module is a
  read-only parse plus a daily job appending new events into Pippin's own
  archive — the only way to retain history past the rolling window. **Every day
  this is not running is data permanently lost**, which is why it is scheduled
  ahead of easier modules. Timestamps are Core Data epoch
  (`unix = value + 978307200`). Falls under `design.md` §4 SQLite discipline.
- Health stage 1: iCloud-folder ingest from Exporter + archive + query tools
  (Decided Position 7)
- Clipboard and screenshot OCR (NSPasteboard / ScreenCaptureKit / Vision)
- Spotlight file search

**Batch 3 — write expansion and the escape hatch:**
- Mail writes (send, move, flag) under the same two-phase protocol
- Notes; Messages send (send-only — reading history is a Tier-D database path,
  deferred to batch four)
- Safari (tabs, current page), Finder, Music
- Small System-Settings module through official channels only: appearance,
  volume, Wi-Fi; Focus via the Shortcuts module
- Generic escape hatch `script_run` + `app_dictionary` (`design.md` §14, own
  security review)

**Batch 4 — network and fragile backends, all gated on token tiers:**
- Token tiers and the remote-access switch (Decided Position 8)
- Health stage 2: LAN POST ingest from Exporter
- Cloud-agent connectors via tunnel
- Tier-D long tail: Messages history read, Safari history — the most fragile
  backends, deliberately last

**Permanent non-goals:** Health read on-Mac (no HealthKit on macOS; only ever via
Exporter) · Keychain and passwords (technically reachable, excluded by policy) ·
FaceTime, Podcasts, TV, Books (no framework, no dictionary) · general System
Settings control (only the small official subset above; UI-scripting the Settings
app is rejected as too fragile) · WeatherKit (needs a paid account, O2) ·
notarization and distribution.

### Evidence and Companion Files

- `addendum-2026-08-18.md` — the side session's decisions, the Screen Time
  measurements, and the tier A–D inventory. Kept in this task folder as reference.
- Screen Time snapshot already taken by hand:
  `~/Documents/ScreenTime-Backups/2026-08-17/` (~62 MB, verified). A plain copy
  of `knowledgeC.db` plus its `-wal` and `-shm` passes `PRAGMA integrity_check`.
- Full Disk Access is a hard gate on that database — without it, even listing the
  directory fails with `Operation not permitted`, observed directly. That is
  empirical support for constraints C2 and C3.
- Repo-root `exporter-issues-draft.md` is the user's staging file for the Exporter
  repo's issues. **Do not commit it and do not delete it.**
