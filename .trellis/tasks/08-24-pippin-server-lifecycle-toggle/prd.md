# Pippin: Persistent Server Lifecycle Toggle

Child of `08-17-pippin-mcp-server`. This task is deliberately separate from the
skeleton task's Step 8 visual redesign: the UI may preview the control while the
app is development-only, but only this task may make it interactive.

## Goal

Add one persistent, global **MCP Server** switch. Turning it off stops Pippin's
local MCP listener and invalidates its live access material while leaving the
signed menu-bar app resident, so the user can turn the server back on without
relaunching or reauthorizing Apple data sources.

## Requirements

- **L1 — Persistent preference.** Store one global server-enabled preference.
  A fresh installation defaults to enabled; an explicit off choice survives app
  quit, relaunch, and rebuilds that preserve the existing config directory.
- **L2 — Resident app.** Turning the server off does not quit `Pippin.app` and
  does not change its signing identity, module configuration, write gates, or
  TCC grants.
- **L3 — Conservative stop.** An off transition stops accepting requests,
  closes active MCP sessions, removes `endpoint.json`, invalidates the current
  bearer token, and invalidates all outstanding confirmation tokens. No old
  endpoint, session, bearer token, or confirmation token may become valid after
  the server is re-enabled.
- **L4 — Fresh start.** An on transition creates a fresh listener, bearer token,
  and `endpoint.json` under the existing loopback-only and mode-0600 rules. It
  must not request TCC access merely because the server is enabled.
- **L5 — One authoritative state.** Menu bar and Settings controls reflect and
  mutate the same runtime/config state. Transitions are serialized, idempotent,
  and expose `starting`, `running`, `stopping`, `stopped`, and `failed` states
  rather than optimistic UI-only state.
- **L6 — Explicit shim result.** A shim launched while the signed app is alive
  but the server is intentionally disabled exits non-zero with a distinct,
  actionable diagnostic. It must not report a generic launch/readiness timeout.
  The disabled-state signal must contain no bearer token or Apple data.
- **L7 — Preserve the trust boundary.** Enabling never widens the bind beyond
  loopback. Disabling never changes module/write gates. The shim remains free of
  shared business state, safety decisions, TCC handles, and Apple data.
- **L8 — No fake compatibility.** Existing direct HTTP and stdio clients keep
  the same protocol when enabled. No client-specific lifecycle API or harness
  assumption is introduced.

## Acceptance Criteria

- [ ] **AC1** With no saved preference, the packaged app starts the server and
      publishes a valid mode-0600 endpoint.
- [ ] **AC2** Turning the switch off leaves the menu-bar app running but stops
      the listener, closes all sessions, and removes `endpoint.json`.
- [ ] **AC3** Off persists across app relaunch. Turning it on again starts a
      fresh endpoint without a new TCC prompt.
- [ ] **AC4** The old bearer token, old MCP session ID, and every old confirm
      token are rejected after an off/on cycle.
- [ ] **AC5** Menu bar and Settings show the same transition and failure state;
      repeated or concurrent toggle requests cannot create two listeners or
      leave a half-started server.
- [ ] **AC6** The shim distinguishes intentional disablement from missing,
      malformed, stale, authentication-failed, and readiness-timeout endpoints;
      every case is actionable and bounded.
- [ ] **AC7** Module enabled/write configuration is byte-for-byte unchanged by
      an off/on cycle, and no permission-dependent source is opened merely to
      toggle the server.
- [ ] **AC8** Direct HTTP and shim `tools/list` remain identical after re-enable,
      and two clients still share one resident app process.
- [ ] **AC9** `swift build`, `swift test`, signed packaging, and a three-cycle
      off/on stress test pass without changing the fixed signing identity.

## Non-Requirements

- No Step 8 visual redesign; this task wires the already-approved control.
- No per-module lifecycle changes, remote access, multiple-token management UI,
  launch-at-login feature, auto-update, or client auto-configuration.
- No new third-party dependency and no signing-identity work.

## Product Decisions

- The disabled control is allowed to appear as a read-only placeholder during
  the skeleton's visual phase because Pippin remains development-only until this
  task lands. Shipping a nonfunctional interactive control remains prohibited.
- Server off means **service unavailable by explicit user choice**, not app quit
  and not startup failure.
- The app stays resident so the user retains one obvious recovery path.
