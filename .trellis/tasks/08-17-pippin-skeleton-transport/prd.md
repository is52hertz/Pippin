# Pippin: .app Skeleton and Transport Layer

Child of `08-17-pippin-mcp-server`. Read the parent's `prd.md` and `design.md`
first — the decided design positions there are inherited, not up for revision.

## Goal

Stand up the process that everything else lives inside: a signed, TCC-stable
`Pippin.app` that hosts one resident MCP server, serves loopback Streamable
HTTP, ships a stdio shim for stdio-only clients, presents a HIG-compliant menu
bar UI, and provides the cross-cutting primitives the module tasks consume.

This child exists to retire the two highest-risk unknowns in the whole project —
TCC identity stability and the transport topology — before any module code is
written against them.

## Requirements

- **S1 — SwiftPM project skeleton.** `Package.swift` with the target layout from
  the parent design (`PippinCore`, `PippinModules`, `PippinServer`, `PippinApp`,
  `pippin-shim`), Swift 6 language mode, macOS 26 SDK.
- **S2 — Bundle packaging and stable signing.** Scripts that assemble
  `Pippin.app` from SwiftPM build products and sign it with a long-lived
  identity. `Info.plist` carries `LSUIElement`, a stable bundle identifier, and
  the Apple Events + Reminders usage descriptions. Not sandboxed.
- **S3 — Resident MCP server.** `StatefulHTTPServerTransport` bound to
  `127.0.0.1`, with bearer-token and Origin validators. Loopback binding
  validated in code.
- **S4 — Endpoint publication and shim.** `endpoint.json` (mode `0600`) carrying
  port and token. `pippin-shim` reads it, bridges `StdioTransport` to the HTTP
  endpoint, launches the app if it is not running, and fails with an actionable
  message on timeout rather than hanging. The shim holds no state.
- **S5 — Tool registry with gating.** Modules and their write capability are
  enabled per config. Disabled means absent from `tools/list`. Config changes
  re-derive the registry and emit `notifications/tools/list_changed`.
- **S6 — Menu bar GUI and Settings, HIG-compliant.** `MenuBarExtra` showing
  server status, bound port, enabled modules, and TCC permission states.
  `Settings` scene toggling modules and their write capability. Standard controls
  and system materials only; no custom-drawn chrome. Built against the macOS 26
  SDK so the system Liquid Glass appearance applies.
- **S7 — Cross-cutting core primitives.** Owned here because all modules consume
  them and duplicating them across module tasks would fragment the safety model:
  config loading, DTO conventions and null-pruning, the error model, the mutation
  gate, the confirm-token store, the audit-log writer, the AppleScript runner
  (parameterized + timeout), the read-only SQLite reader, and backend routing.
- **S8 — One proof tool.** `pippin_status` (read-only): version, bound port,
  enabled modules, and per-permission TCC state. It is both the transport smoke
  test and genuinely the tool the user will want when something is not working.

## Non-Requirements

- No app modules. Reminders and Mail are separate children.
- No escape hatch. Deferred to batch two.
- No notarization or distribution. Local signing only.
- No auto-update mechanism.

## Acceptance Criteria

- [ ] **AC1** `Scripts/package_app.sh` produces `Pippin.app`; `codesign -dv`
      reports the expected identity; `ls -R Pippin.app/Contents` shows the
      expected structure with `LSUIElement` and all usage descriptions present.
- [ ] **AC2** Signing identity is byte-identical across three consecutive
      rebuild-and-repackage cycles, and a permission-dependent call keeps working
      with no fresh TCC prompt. (Feeds parent A1.)
- [ ] **AC3** Claude Code connects over HTTP and lists exactly the enabled tools;
      Claude Code connects through `pippin-shim` and lists the same set.
- [ ] **AC4** Two clients connected at once are served by one process; the shim
      adds no state. Verified by process inspection plus a config change that both
      clients observe. (Feeds parent A4.)
- [ ] **AC5** A request with a missing or wrong bearer token is rejected 401. A
      request with a non-loopback `Origin` is rejected. A config with a
      non-loopback `bind` is refused at startup with a clear error.
- [ ] **AC6** Disabling a module removes its tools from `tools/list` after one
      `list_changed` cycle, without restarting the app.
- [ ] **AC7** `pippin_status` reports each permission's real state, including
      correctly reporting *not yet determined* versus *denied*.
- [ ] **AC8** Shim failure paths are actionable: app not running and cannot be
      launched, `endpoint.json` missing, readiness timeout — each yields a
      distinct message, and none hangs.
- [ ] **AC9** Unit tests cover confirm-token lifecycle (TTL, single-use, ID-set
      binding, session binding), registry gating, loopback-bind validation,
      AppleScript argument escaping, and the `tools/list` byte budget.
- [ ] **AC10** GUI reviewed against HIG: standard controls, system materials, no
      custom chrome, correct menu bar behaviour for an `LSUIElement` app.

## Constraints and Notes

- Depends on parent Open Decision **O1** (swift-sdk approval) and **O2**
  (signing identity). Do not start until both are resolved.
- Lands before the Reminders and Mail children, which consume S7's primitives.
- Never validate permission-dependent behaviour via `swift run`; only the signed
  bundle is a supported run path.
- Relevant skills: `apple-skills:guide-macos-spm-packaging` (bundle assembly and
  stable dev signing templates), `apple-skills:hig` and
  `apple-skills:ios-liquid-glass` for the GUI, `apple-skills:swift-testing`,
  `apple-skills:guide-swift-concurrency` for the resident-actor design.
