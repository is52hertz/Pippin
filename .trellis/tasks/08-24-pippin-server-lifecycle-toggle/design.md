# Persistent Server Lifecycle Toggle — Technical Design

Inherits the parent and skeleton designs. This document records the intended
contract; exact APIs must be confirmed against the landed runtime before this
task is started.

## 1. Sources of Truth

`Config` gains a persisted global server-enabled value whose decoding default is
`true`, including for pre-feature config files. `ServerRuntime` remains the only
owner of listener, host, sessions, endpoint publication, and transition state.
The presentation model mirrors snapshots and sends intents; it never starts or
stops network objects itself.

The runtime transition state is:

```
starting -> running -> stopping -> stopped
    |          |           |          |
    +----------+-----------+----------+-> failed
```

The actor serializes transitions. Requesting the current target state is a
no-op. A failure publishes `failed` with an actionable detail and leaves no
endpoint that claims readiness.

## 2. Stop and Start Ordering

**Disable:** persist the validated preference, reject new work, stop the
listener, close/sweep all sessions, shut down the host (thereby discarding bearer
and confirm-token stores), remove `endpoint.json`, then publish `stopped`.

**Enable:** persist the validated preference, construct a fresh token store and
host, bind loopback, begin sweeping, publish a fresh mode-0600 endpoint only
after readiness, then publish `running`. A failed start tears everything down and
removes the endpoint before publishing `failed`.

The implementation must verify whether persistence-first is recoverable for
every failure. If not, the task's first research step must define an explicit
rollback rule before code is written; the UI must never claim a state that the
next launch will contradict.

## 3. Shim-Visible Disabled State

`endpoint.json` remains a running-endpoint document and is removed while off.
The shim therefore needs a separate, non-secret, mode-0600 resident-state signal
to distinguish intentional disablement from an app that failed to launch. The
first implementation step must choose and freeze its schema and transition
ordering. A small `runtime-state.json` beside the endpoint is the preferred
shape; it contains only the app PID and semantic server state, never a token,
port, module configuration, permission status, or Apple data.

The resolver checks this signal during its existing bounded readiness loop. A
live signed app reporting `stopped` produces a dedicated `serverDisabled`
failure immediately. `starting` remains bounded by the normal readiness
deadline; stale/malformed state cannot override endpoint validation.

## 4. UI Contract

The menu bar and Settings use the same presentation intent. The switch is
disabled while a transition is in flight. Off does not alter the selected
integration rows or their write settings. A failed transition surfaces one
actionable error and the authoritative state after refresh.

The skeleton's disabled read-only placeholder is removed when this task lands;
there must never be two controls or two persisted values.

## 5. Tests

- Config backward compatibility and default-on persistence.
- Actor transition idempotency, concurrent intents, start/stop failure cleanup.
- Session, bearer-token, and confirm-token invalidation across off/on.
- Shim disabled-state detection plus malformed/stale/racing state files.
- Presentation parity between menu bar and Settings.
- Signed-app manual verification with the fixed identity and no fresh TCC prompt.
