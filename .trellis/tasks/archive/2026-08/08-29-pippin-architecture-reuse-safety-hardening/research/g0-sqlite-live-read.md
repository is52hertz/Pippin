# G0: SQLite Live Read Contract

## Primary documentation

- [`sqlite3_open_v2`](https://sqlite.org/c3ref/open.html)
- [SQLite URI filenames](https://sqlite.org/uri.html)
- [`sqlite3_busy_timeout`](https://sqlite.org/c3ref/busy_timeout.html)

SQLite documents `immutable=1` as an assertion that the database file will not
change. It disables locking and change detection; if the file changes anyway,
results may be incorrect or SQLite may report corruption. Mail actively owns and
updates Envelope Index, so the assertion is false even though Pippin never
writes it.

## Frozen open policy

- Pass the ordinary filesystem path directly to `sqlite3_open_v2`; do not build
  a `file:` URI.
- Flags: `SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE`.
- Verify `sqlite3_db_readonly(handle, "main") == 1` after opening.
- Configure `sqlite3_busy_timeout(handle, 250)` once after opening.
- Do not use `SQLITE_OPEN_URI`, shared cache, or `immutable=1`.
- Keep Pippin's private serial queue, prepared statements, bound caller values,
  schema probe, and terminal `sqlite3_step` check.

`PRAGMA query_only=ON` is not required: the connection is already opened
read-only and all SQL is repository-authored. Adding it would not replace the
read-only open flag and would not improve the tested live-read behavior.

## Scratch fixture

The scratch program was compiled against the macOS system SQLite (`3.51.0`,
2025-06-12). It used:

1. a writer connection in WAL mode;
2. one long-lived read-only/private-cache reader;
3. a second writer commit after the reader's first statement;
4. an explicit assertion that `PRAGMA journal_mode=WAL` returned `wal`;
5. a separate rollback-journal database held under an exclusive lock for the
   busy path (WAL readers normally do not block a writer).

The exact fixture is retained at `research/fixtures/sqlite-live-read.c` and can
be rerun with:

```sh
xcrun clang -Wall -Wextra -Werror research/fixtures/sqlite-live-read.c \
  -lsqlite3 -o /tmp/pippin-g0-sqlite
/tmp/pippin-g0-sqlite
```

Three runs produced:

```text
wal_visibility mode=wal first=1 second=2 readonly=1
busy_bound rc=5 elapsed_ms=276
wal_visibility mode=wal first=1 second=2 readonly=1
busy_bound rc=5 elapsed_ms=348
wal_visibility mode=wal first=1 second=2 readonly=1
busy_bound rc=5 elapsed_ms=281
```

The same reader observed the later WAL commit on its next statement. Contention
returned `SQLITE_BUSY` (`5`) rather than hanging. SQLite may overshoot the exact
timeout while sleeping and scheduling, so deterministic tests should assert a
generous wall bound (750 ms for the 250 ms configuration), not exact timing.

## Error contract

Open, readonly-verification, prepare, bind, busy exhaustion, step, and schema
failures map to `backend_unavailable` with an actionable hint. A busy or WAL
failure must never be converted to an empty result. The Mail child still owns
real Envelope Index path/schema/FDA validation and its AppleScript fallback.
