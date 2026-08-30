# Persistent Server Lifecycle Toggle — Execution Plan

This task remains `planning`. Do not start it as part of the skeleton UI
redesign.

## Checklist

### Step 0 — Freeze the lifecycle contract
- [ ] Re-read the landed `Config`, `Endpoint`, `ServerRuntime`, `ServerHost`, and
      shim resolver rather than relying on this plan's sketches.
- [ ] Decide and document preference migration, failure rollback, and the
      token-free shim-visible resident-state schema/ordering.
- [ ] Add failing tests for default-on migration, intentional-disable diagnosis,
      and credential/session invalidation before implementation.

### Step 1 — Persisted configuration
- [ ] Add the backward-compatible global preference with default `true`.
- [ ] Cover old config files, corrupt values, save/load, and preservation of
      module/write settings.

### Step 2 — Runtime lifecycle
- [ ] Serialize enable/disable transitions in `ServerRuntime`.
- [ ] Implement conservative teardown and fresh-start ordering.
- [ ] Publish runtime snapshots and the non-secret resident-state signal.

### Step 3 — Shim semantics
- [ ] Teach endpoint resolution to recognize intentional disablement under the
      existing bounded deadline.
- [ ] Keep all existing missing/malformed/stale/authentication/readiness errors
      distinct and ensure no token is logged.

### Step 4 — Wire the existing UI control
- [ ] Replace the Step 8 disabled placeholder with one real shared intent/state.
- [ ] Verify menu bar and Settings parity, transition disabling, and failure UI.

### Step 5 — Integration and quality gate
- [ ] Run unit/protocol tests, direct HTTP and shim parity, concurrent clients,
      and repeated off/on cycles.
- [ ] Package and verify the signed app without rebuilding the identity; confirm
      no new TCC prompt.
- [ ] Run `swift build`, `swift test`, `git diff --check`, independent
      `trellis-check`, and the task acceptance list.
