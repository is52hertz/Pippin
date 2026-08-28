# Database Guidelines

Pippin does not own an ORM or migration system. `SQLiteReader` provides the
read-only infrastructure for best-effort access to private stores owned by other
macOS apps; no production module uses it yet.

## Scenario: Private SQLite Read Backend

### 1. Scope / Trigger

Apply this contract whenever a module reads a private database owned and
modified by another macOS application, beginning with Mail's Envelope Index.

### 2. Signatures

- `SQLiteReader.resolveVersionedPath(_:) throws -> String` resolves one `*`
  version component at runtime.
- `SQLiteReader.init(path:) throws` opens the database read-only.
- `SQLiteReader.probe(_:) -> Result<Void, PippinError>` verifies required tables
  and columns before the backend is considered available.
- `SQLiteReader.query(_:parameters:map:) throws -> [T]` accepts
  repository-authored SQL and bound `[SQLiteValue]` parameters.

### 3. Contracts

- Open live private stores with a true read-only connection, and validate change
  visibility and WAL behavior against the owning application's writes. The
  current `SQLiteReader` appends `immutable=1`; this is a known implementation
  limitation pending the architecture-hardening task, not a pattern to copy.
  New integrations and integrations reading actively modified stores must not
  use `immutable=1`.
- Resolve versioned private-store paths at runtime with
  `SQLiteReader.resolveVersionedPath`; never hard-code a Mail `V10`-style
  version directory.
- Probe required tables and columns with `SQLiteReader.probe` before trusting a
  private schema. A failed probe disables or degrades that backend.
- Keep SQL repository-authored. Pass all caller values as `[SQLiteValue]` to
  `SQLiteReader.query`; identifiers used by PRAGMA must be trusted constants and
  passed through `quoteIdentifier`.
- Serialize access through the reader's private queue and always finalize the
  prepared statement. Treat any terminal step other than `SQLITE_DONE` as an
  error, not a short or empty result.

### 4. Validation and Error Matrix

| Condition | Required result |
|---|---|
| Mail directory cannot be listed/read | `backend_unavailable` with Full Disk Access hint |
| No matching version directory | `backend_unavailable`; never hard-code a fallback version |
| Required table or column missing | disable/degrade SQLite backend with recorded reason |
| Prepare, bind, or terminal step failure | explicit error; never return fabricated zero rows |
| SQLite unavailable but fallback succeeds | response marked `degraded` with reason |
| All backends unavailable | throw actionable `PippinError` |

Missing Full Disk Access, a moved path, a changed schema, and an incomplete query
must become actionable `PippinError` values. `BackendRouter.route` may fall back
to another backend, but it reports `degraded` and `reason`; if all backends fail,
it throws rather than returning a fabricated empty answer.

### 5. Good / Base / Bad Cases

- Good: dynamically resolve the active `V*` directory, open read-only, pass the
  schema probe, and bind every caller value.
- Base: a probe fails after a macOS update and AppleScript serves the request
  with an explicit degraded marker.
- Bad: hard-code `V10`, interpolate search text, use `immutable=1` against a
  live-changing database, or translate a backend failure into `[]`.

### 6. Tests Required

- `Tests/PippinCoreTests/SQLiteReaderTests.swift`: read-only opening, version
  resolution, bound injection payloads, schema mismatch, missing path, and
  terminal query failure.
- `Tests/PippinCoreTests/BackendRouterTests.swift`: primary success, degraded
  fallback, and all-backends-failed behavior.
- Each concrete module adds an integration test while the owning app is running,
  including WAL/change visibility and the permission-denied path.

### 7. Wrong vs Correct

Wrong: treat private schema and file layout as stable, then return an empty list
when the open or query fails.

Correct: resolve, probe, query with bindings, and either return real rows,
explicitly degrade to a known fallback, or fail actionably.

## Avoid

- No writes, migrations, schema repair, or write-intent locks against another
  app's DB.
- No SQL interpolation for values and no caller-controlled table names.
- No conversion of permission/schema failures into zero rows.
