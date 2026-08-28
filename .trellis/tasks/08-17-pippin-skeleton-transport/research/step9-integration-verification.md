# Step 9 — Integration Verification

- Date: 2026-08-28
- Build: `9946b04` plus no production-code changes
- Scope: skeleton acceptance rerun, signed-bundle stability, live concurrency,
  Codex transport smoke, and explicit external blockers
- Secret handling: no endpoint token appears in commands, arguments, persistent
  client configuration, stdout, stderr, or this evidence

## Build and automated suites

The following passed:

- `swift build`
- `swift test` — 201 tests in 26 suites
- `swift build -c release`
- direct HTTP versus shim `tools/list` parity
- concurrent sessions and shared `ServerHost` state
- config-update `tools/list_changed` delivery to every affected session
- bearer and Origin validation, non-loopback bind refusal
- registry/write gating, token tiers, tool budget, confirm-token lifecycle
- shim endpoint recovery, framing, bounded failures, and credential-redaction tests

## Three stable-signing cycles

`Scripts/package_app.sh` ran three consecutive times. Every round passed strict
codesign verification and produced the same identity:

| Property | All three rounds |
|---|---|
| Authority | `Pippin Local Signing` |
| Certificate SHA-1 | `1AB7E0BC58C427092143FBADABA7F34CD607775D` |
| Certificate SHA-256 | `2662C98D777179098181467BED603722CE45007A79687561951E30983843578D` |
| Bundle identifier | `io.github.is52hertz.pippin` |
| Designated requirement | stable identifier plus the same certificate root |
| `LSUIElement` | `true` |

The final signed bundle launched as the only resident `Pippin` process. A passive
status call through its bundled shim still reported Reminders and effective Mail
Data access as granted. Mail Automation was unavailable because Mail was not
running; this is the designed non-prompting state, not permission loss.

No automated observation can prove that a GUI prompt was absent from the user's
screen. AC2 therefore remains open until the user confirms that the three cycles
caused no fresh TCC prompt.

## Live concurrent clients

Two separate bundled `pippin-shim` processes initialized and remained connected
at the same time. The resident signed app reported:

```text
LIVE_CLIENTS=2
DISTINCT_SHIM_PROCESSES=2
RESIDENT_PIPPIN_PROCESSES=1
TOOL_LISTS_EQUAL=true
TOOLS=pippin_status
SESSIONS_CLIENT_A=2
SESSIONS_CLIENT_B=2
MODULE_STATE_EQUAL=true
```

The automated SDK integration test independently changed the shared config and
confirmed both affected sessions received `notifications/tools/list_changed`.
Together these prove AC4 without adding a production test endpoint or mutating
the user's live config.

## Real Codex smoke

Codex CLI used invocation-only configuration and called `pippin_status` through
both supported transports:

| Transport | Result |
|---|---|
| bundled stdio shim | `PIPPIN_SHIM_SMOKE_OK 0.1.0` |
| direct Streamable HTTP | `PIPPIN_HTTP_SMOKE_OK 0.1.0` |

The shim required no client-visible credential. Direct HTTP used Codex's
`bearer_token_env_var` mechanism; only the environment-variable name entered
configuration, and the process was ephemeral.

## Claude Code blocker

Claude Code 2.1.250 is installed, but `claude auth status --json` reports
`loggedIn=false`, and `ANTHROPIC_API_KEY` is unset. Pippin did not start an
interactive login or persist MCP configuration. Consequently:

- protocol-level and Codex HTTP/shim evidence pass;
- Pippin has no observed transport defect;
- real Claude Code HTTP and shim smoke remain blocked by external credentials;
- AC3 and the first Step 9 item remain open.

## Acceptance status

| Criterion | Status | Evidence |
|---|---|---|
| AC1 package and signature | Pass | three packages plus bundle/signature inspection |
| AC2 TCC stability | Awaiting user confirmation | identity and passive grants stable; prompt absence is manual |
| AC3 Claude Code HTTP + shim | Blocked | Claude Code logged out; no API key |
| AC4 single-owner concurrency | Pass | two live shim clients, one app, shared-state transport test |
| AC5 validators | Pass | HTTP validator and live transport suites |
| AC6 structural module gating | Pass | synthetic catalogue plus list-changed integration |
| AC7 honest permission status | Pass | mapping tests and signed passive status call |
| AC8 bounded shim failures | Pass | endpoint/launch/readiness/auth/connection suites |
| AC9 core safety coverage | Pass | full unit suite |
| AC10 HIG | Pass | Step 8 signed-app review |
| AC11 tier-ready tokens | Pass | two-token capability test |

Step 9 and the skeleton task remain in progress until AC2 is confirmed and AC3
can run with restored Claude Code access.
