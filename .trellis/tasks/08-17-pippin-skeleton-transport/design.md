# Skeleton and Transport — Technical Design

Inherits `../08-17-pippin-mcp-server/design.md`. This file covers only what is
specific to the skeleton child.

## 1. Package Layout

```swift
// Package.swift  (sketch — exact API confirmed against the SDK at implementation time)
platforms: [.macOS(.v26)]
swiftLanguageModes: [.v6]

targets:
  PippinCore     // no MCP, no SwiftUI imports — pure, unit-testable
  PippinModules  // depends on PippinCore
  PippinServer   // depends on PippinCore + PippinModules + MCP
  PippinApp      // executable; SwiftUI; depends on PippinServer
  pippin-shim    // executable; depends on MCP only
  PippinCoreTests, PippinServerTests
```

`PippinCore` must not import SwiftUI, AppKit, or the MCP SDK. That boundary is
what keeps the safety model (token store, mutation gate, routing, DTO shaping)
unit-testable without a GUI, a transport, or TCC.

## 2. Bundle Assembly and Signing

Adapt the templates from `apple-skills:guide-macos-spm-packaging` rather than
writing packaging from scratch:

- `Scripts/setup_dev_signing.sh` — create the long-lived signing identity once: a
  fixed self-signed keychain identity, since there is no paid Apple Developer
  account (parent O2). Run once per machine; the identity must then never be
  regenerated, since regenerating it is precisely what breaks TCC grants. The
  script is idempotent and refuses to overwrite an existing identity, because the
  destructive failure mode here is silent — a regenerated certificate does not
  error, it just quietly invalidates every permission the user has granted.
- `Scripts/package_app.sh` — build with `swift build -c release`, assemble
  `Pippin.app/Contents/{MacOS,Resources,Info.plist}`, sign with the stable
  identity. `MENU_BAR_APP=1` emits `LSUIElement`.
- `Scripts/compile_and_run.sh` — dev loop: kill the running instance, repackage,
  relaunch the bundle.
- `version.env` — `APP_NAME`, `BUNDLE_ID`, version, build number.

`Info.plist` keys: `LSUIElement=true`, stable `CFBundleIdentifier`,
`NSAppleEventsUsageDescription`, `NSRemindersFullAccessUsageDescription`.

The shim ships inside the bundle (`Contents/MacOS/pippin-shim`) so there is one
artifact to install, and clients point at that path.

## 3. Resident Server Wiring

`PippinApp` owns server lifetime. The server, the registry, the token store, and
the audit writer are held by a single actor so concurrent client requests
serialize through one owner — this is the mechanism behind parent criterion A4.

```
PippinApp (SwiftUI App)
  └── ServerHost (actor)
        ├── Server (swift-sdk) + StatefulHTTPServerTransport(host: "127.0.0.1")
        ├── ToolRegistry      (derived from Config)
        ├── ConfirmTokenStore (in-memory only; a restart invalidates every token)
        └── AuditLog
```

Confirm tokens intentionally live in memory only. A restarted server refusing a
token minted by its predecessor is the correct, conservative behaviour.

**Port selection:** try the configured port; on conflict, bind an ephemeral port.
Publish whatever was actually bound to `endpoint.json`. Never fail to start over
a port conflict.

**Validators** (via the SDK's `HTTPRequestValidator` pipeline):
1. bearer-token lookup → 401 on miss
2. `Origin` absent or loopback → otherwise reject

**Token model, shaped for tiers (S9).** Validation resolves a presented token to
a *capability set*, not to a boolean:

```
TokenStore: token → TokenIdentity { label, capabilities }
Capabilities: read | write | destructive        (a set, not a flag)
```

Batch one provisions exactly one token, whose capability set is "all three". The
registry already derives the tool list from `(config, capabilities)` rather than
from config alone, so batch four's remote read-only token needs a new row in the
store and nothing else. The cost today is one parameter threaded through the
registry; the cost of retrofitting it later is every call site that assumed a
single omnipotent caller.

This is intentionally *not* a permission system yet — no minting UI, no
revocation, no persistence of multiple tokens. Only the shape.

**Bind validation:** `config.http.bind` is parsed and required to be a loopback
address. Anything else is a startup error with an explicit message. Constraint C1
is enforced here, in code.

## 4. Shim Behaviour

```
1. read ~/Library/Application Support/Pippin/endpoint.json
2. if missing or connect fails → launch the app by bundle identifier
3. poll for readiness, bounded timeout
4. StdioTransport ⇄ HTTP: forward frames both ways, unmodified
5. on any terminal failure → emit a distinct, actionable error and exit non-zero
```

The shim never parses or rewrites payloads. Keeping it a dumb pipe is what makes
"the shim holds no state" verifiable rather than aspirational.

## 5. Tool Registry

The registry is a pure function: `(Config, Capabilities) → [Tool]`. Testable with
no transport. Registration for each tool declares name, terse description
(≤ 200 characters), input schema, optional output schema, annotations, and
whether it is a write or destructive verb.

The `Capabilities` parameter is the S9 allowance. Batch one always passes the full
set, so behaviour is identical to `Config → [Tool]`; the parameter exists so that
a read-only token later yields a read-only tool list through the same code path
rather than a bolted-on filter.

Gating order: module disabled ⇒ contributes nothing; module enabled with writes
off ⇒ contributes read-only tools only. Absent, never present-and-erroring
(parent A6).

A config change recomputes the registry and emits
`notifications/tools/list_changed`.

## 6. Core Primitives Delivered Here

| Primitive | Responsibility | Key test |
|---|---|---|
| `Config` | load/save, defaults, loopback validation | non-loopback bind refused |
| `DTO` conventions | null pruning, ISO-8601, pagination/cursor | pruning drops empties |
| `PippinError` | code + detail + hint, compact encoding | every code has a hint |
| `MutationGate` | write-enabled check at call time | writes off ⇒ refusal |
| `ConfirmTokenStore` | mint, validate, consume | TTL / single-use / ID-set / session |
| `AuditLog` | append JSONL, rotate, digest args | no raw argument values written |
| `AppleScriptRunner` | Apple Event args, wall-clock timeout | injection attempt is inert |
| `SQLiteReader` | read-only open, schema probe | failed probe disables backend |
| `BackendRouter` | ordered backends + degradation | falls back, never empty-on-failure |

`AppleScriptRunner` and `SQLiteReader` are built here even though the skeleton
itself calls neither: the Mail child needs both, and the alternative — each
module rolling its own — is exactly how the injection and silent-empty-result
rules get violated.

## 7. GUI

`MenuBarExtra` with a `Settings` scene. Content:

- Server: running state, bound port, connected session count.
- Permissions: one row per TCC grant with its real state, distinguishing *not
  determined* from *denied*, and a button opening the relevant System Settings
  pane.
- Modules: per-module enable toggle and write toggle.

HIG compliance is a deliverable, not a polish pass: standard SwiftUI controls,
system materials, no hand-drawn backgrounds or custom window chrome. Consult
`apple-skills:hig` and `apple-skills:ios-liquid-glass` during implementation, not
after.

## 8. Risks

| Risk | Handling |
|---|---|
| SDK API differs from the sketches here | Confirm against the real SDK before writing; treat these snippets as intent, not contract |
| SwiftUI App lifecycle misbehaves in a SwiftPM executable | Always run the packaged bundle; unbundled runs have wrong activation policy and signature |
| TCC prompt attributed to a parent process instead of the app | The app is the only process touching user data and it self-launches; the shim needs no grants |
| Port conflict at startup | Ephemeral fallback, publish the actual port |
| Signing identity accidentally regenerated | `setup_dev_signing.sh` is idempotent and refuses to overwrite an existing identity |
