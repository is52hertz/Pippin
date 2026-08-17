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
  server's flaky Reminders access.
- **C4 — Build target.** macOS 26 SDK, Swift 6 language mode. GUI must follow
  HIG and use standard controls and system materials (Liquid Glass comes from
  building against the macOS 26 SDK); no custom-drawn chrome.
- **C5 — Dependencies.** Exactly one third-party dependency is proposed:
  `modelcontextprotocol/swift-sdk` (official). See Open Decisions — per
  `AGENTS.md` this needs explicit user approval before use.
- **C6 — Naming.** Product name Pippin; MCP server name and tool prefix
  `pippin`. Repository directory name stays `iMCP` for now. Distinct naming
  keeps the old server installable side-by-side during transition.

## Decided Design Positions

Settled with the user before planning; children inherit these and must not
relitigate them.

1. **Delivery form:** signed `.app` bundle with a long-lived signing identity
   (Developer ID if available, otherwise a fixed self-signed keychain identity).
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
   SQLite. Shortcuts / App Intents is explicitly *not* a tier: there is no
   public API for a daemon to invoke another app's App Intents, only the
   `shortcuts run` CLI against user-pre-built shortcuts. It is a case-by-case
   patch where nothing else works, never an abstraction layer.
5. **SQLite backends are assumed breakable.** Private schema, changes across OS
   versions, needs Full Disk Access. Every SQLite backend must have a
   degradation path — fall back to AppleScript, or return an explicit
   backend-unavailable error. Never a silent empty result. Only Mail gets a
   SQLite backend in batch one.
6. **Generic escape hatch** (`script_run` + `app_dictionary`): design adopted —
   default off, App allowlist, destructive verbs never auto-approved — but
   *scheduled out of batch one*. It validates none of the three highest-risk
   items and its security design deserves its own task. `design.md` reserves its
   place.

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
      `tools/list` output is ≤ 4 KB. The long-term ceiling for the full default
      module set is ≤ 16 KB and ≤ 40 tools, with every tool description ≤ 200
      characters. Enforced by an automated test, not by review.
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

## Out of Scope (Batch Two and Later)

- `script_run` / `app_dictionary` generic AppleScript escape hatch.
- Further modules: Notes, Calendar, Messages, Finder, Safari, Music, and
  non-Apple apps.
- Mail write operations (send, move, flag).
- Any `shortcuts run` patch.
- Notarization and distribution to other machines. Local signing only.

## Open Decisions

Resolve before `task.py start` on the first child.

- [ ] **O1 — Dependency approval.** `modelcontextprotocol/swift-sdk` as the sole
      third-party dependency. It supplies the protocol types, tool annotations,
      `StatefulHTTPServerTransport` (binds `127.0.0.1`, session management, SSE,
      and an `HTTPRequestValidator` pipeline for the bearer-token and Origin
      checks) and `StdioTransport` for the shim. Writing the protocol layer by
      hand instead would be a large amount of low-value code. `AGENTS.md`
      requires explicit approval for any new dependency.
- [ ] **O2 — Signing identity.** Is a paid Apple Developer account available
      (Developer ID certificate), or should the build use a fixed self-signed
      keychain identity? Affects `Scripts/setup_dev_signing.sh` only, not
      architecture.
- [ ] **O3 — Token budget numbers.** Confirm the A3 figures (4 KB batch one /
      16 KB and 40 tools long term / 200 characters per description).

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
