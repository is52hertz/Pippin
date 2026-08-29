# G0: Mutation Journal Contract

## Scope and terminology

`audit.jsonl` is a private local operation journal, not a tamper-evident or
compliance audit system. Reads, previews, and refusals remain best-effort.
Every ordinary write and confirmed destructive operation uses one required
mutation sequence owned by `ToolContext.performMutation`.

## Frozen record shape

Preserve the existing JSONL `Entry` and `Outcome` vocabulary, adding:

- `Outcome.intent`;
- optional `operationID` (a fresh UUID for each attempted mutation).

An intent line has `outcome: "intent"`; its success/failure outcome line carries
the same `operationID`. Existing entries remain decodable because the new field
is optional. Explicit affected IDs and an argument digest remain allowed. Raw
arguments, Apple data, bearer tokens, confirmation tokens, script output, and
credentials are never recorded.

## Required append

The required path is serialized by the `AuditLog` actor and propagates every
setup, recovery, rotation, open, seek, write, and sync failure. It creates the
directory/file with modes 0700/0600, appends one JSON line, and calls
`FileHandle.synchronize()` before returning. File creation and rotation also
synchronize the parent directory metadata. Rotation runs before the intent
append and is not silently swallowed on this path.

### Durability boundary

“Durable” means that after the required append and synchronize return, a Pippin
process crash cannot produce an execution with no intent record. The design also
asks Darwin/APFS to flush file and changed directory metadata, but does not claim
tamper resistance or absolute survival of sudden power loss, storage hardware
that ignores flush requests, filesystem damage, or manual deletion. Those are
outside a personal local JSONL journal's honest guarantee.

A single append is not assumed atomic across a crash. Before every required
append, if the current file is non-empty and lacks a final newline, Pippin first
appends a newline and synchronizes it. A complete line that merely lacked its
terminator becomes readable; an incomplete JSON fragment remains preserved as a
separate malformed line and cannot contaminate the next intent. Readers skip
malformed lines but continue decoding later complete lines. No bytes are silently
discarded.

### Rotation and crash recovery

The required path retains the existing one-generation, 5 MiB policy. When the
current file meets the threshold it performs, under the actor:

1. synchronize and close the current file;
2. remove the previous `.1` generation;
3. atomically rename the current file to `.1`;
4. synchronize the parent directory;
5. create the new current file at mode 0600 and synchronize the parent directory;
6. append and synchronize the intent.

If any step fails, the required append fails and `perform` is not entered. A
crash after rotation but before the intent can leave no current file, but it
cannot leave an unjournaled mutation because `beginMutation` has not returned;
the next attempt recreates the current file. The one-generation retention policy
may lose older history if a crash occurs between removing `.1` and renaming the
current file, but it never falsifies whether the new mutation was allowed to run.

Intents and outcomes from concurrent operations may interleave because `perform`
runs outside the log actor; their UUID `operationID` is the correlation key. The
actor still guarantees that individual append/recovery/rotation operations do
not run concurrently.

Failure maps to the existing error code:

```json
{
  "error": {
    "code": "backend_unavailable",
    "detail": "audit_log",
    "hint": "Pippin could not record a durable mutation intent. Fix audit-log storage, then retry; no Apple data was changed."
  }
}
```

No new `PippinError.Code` is introduced.

## Mutation order

Ordinary writes:

```text
mutation gate
→ durable intent append + synchronize
→ perform
→ durable outcome append + synchronize
→ return
```

Confirmed destructive operations:

```text
destructive gate
→ validate and consume exact session/tool/ID-bound confirmation token
→ durable intent append + synchronize
→ perform
→ durable outcome append + synchronize
→ return
```

Burning the token before intent is conservative: if intent fails, no mutation
occurs and the caller must request a fresh preview. Preview and invalid-token
records stay best-effort.

`performMutation` accepts an object result (a `[String: JSONValue]`) so degraded
metadata can be added without changing a tool's root shape. Mutation tool output
schemas reserve the two top-level fields below.

## Frozen degraded success envelope

If `perform` returns successfully but the outcome append/sync fails, Pippin must
return the real result with exactly these additional fields:

```json
{
  "...real result fields...": "...",
  "audit_degraded": true,
  "audit_hint": "Mutation succeeded. Audit outcome unavailable; do not retry. Later mutations stay blocked until audit storage recovers."
}
```

This is a successful tool result, not a generic error. It truthfully prevents an
Agent from retrying an already-applied mutation. If `perform` throws, Pippin
attempts a failed-outcome append and rethrows the original operation error.

## Health latch and recovery

An outcome append failure latches the shared `AuditLog` unhealthy. Mutations
whose required intents were already synchronized may finish; after the latch is
set, no new `perform` starts until recovery.

The next requested mutation gets one recovery attempt, with no retry loop: its
own intent append plus synchronize is the health probe. If it succeeds, the
latch clears and that mutation may run. If it fails, the same
`backend_unavailable` error is returned and `perform` is not called. A successful
outcome from an already-in-flight mutation does not by itself clear an unhealthy
latch.

## Crash-window interpretation

| Last durable event | Meaning after restart |
|---|---|
| No intent | `perform` was never entered |
| Intent only | Operation may not have started, may have failed, or may have applied; reconcile before retrying blindly |
| Intent + failed outcome | Operation reported failure; IDs/error identify the attempt |
| Intent + succeeded outcome | Operation completed successfully |

The journal does not promise automatic replay or rollback. Its guarantee is
durable intent before side effects, truthful degraded success, and fail-closed
behavior when a new intent cannot be recorded.

Tests must inject failures at intent append, intent synchronize, each rotation
boundary, outcome append, and outcome synchronize. They also seed both a valid
unterminated line and a torn JSON tail, then prove that a later required intent
is independently decodable and that no `perform` runs before its synchronized
intent.
