#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void ok(int rc, sqlite3 *db, const char *where) {
  if (rc != SQLITE_OK && rc != SQLITE_DONE && rc != SQLITE_ROW) {
    fprintf(stderr, "%s: rc=%d %s\n", where, rc, db ? sqlite3_errmsg(db) : "");
    exit(1);
  }
}

static int scalar(sqlite3 *db, const char *sql, int *rc_out) {
  sqlite3_stmt *stmt = NULL;
  int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
  if (rc == SQLITE_OK) rc = sqlite3_step(stmt);
  int value = rc == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : -1;
  sqlite3_finalize(stmt);
  if (rc_out) *rc_out = rc;
  return value;
}

static long elapsed_ms(struct timespec a, struct timespec b) {
  return (b.tv_sec - a.tv_sec) * 1000L + (b.tv_nsec - a.tv_nsec) / 1000000L;
}

int main(void) {
  const char *wal = "/tmp/pippin-g0-live-wal.sqlite";
  const char *locked = "/tmp/pippin-g0-locked.sqlite";
  unlink(wal);
  unlink("/tmp/pippin-g0-live-wal.sqlite-wal");
  unlink("/tmp/pippin-g0-live-wal.sqlite-shm");
  unlink(locked);
  unlink("/tmp/pippin-g0-locked.sqlite-journal");

  sqlite3 *writer = NULL, *reader = NULL;
  ok(sqlite3_open_v2(wal, &writer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL), writer, "open writer");
  sqlite3_stmt *journal_mode = NULL;
  ok(sqlite3_prepare_v2(writer, "PRAGMA journal_mode=WAL", -1, &journal_mode, NULL), writer, "prepare wal mode");
  ok(sqlite3_step(journal_mode), writer, "set wal mode");
  const unsigned char *mode = sqlite3_column_text(journal_mode, 0);
  int is_wal = mode != NULL && strcmp((const char *)mode, "wal") == 0;
  sqlite3_finalize(journal_mode);
  if (!is_wal) {
    fprintf(stderr, "database did not enter WAL mode\n");
    return 1;
  }
  ok(sqlite3_exec(writer, "CREATE TABLE item(v INTEGER); INSERT INTO item VALUES(1);", NULL, NULL, NULL), writer, "seed wal");
  ok(sqlite3_open_v2(wal, &reader, SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE, NULL), reader, "open reader");
  ok(sqlite3_busy_timeout(reader, 250), reader, "busy timeout");
  int first = scalar(reader, "SELECT count(*) FROM item", NULL);
  ok(sqlite3_exec(writer, "INSERT INTO item VALUES(2);", NULL, NULL, NULL), writer, "second wal commit");
  int second = scalar(reader, "SELECT count(*) FROM item", NULL);
  printf("wal_visibility mode=wal first=%d second=%d readonly=%d\n", first, second, sqlite3_db_readonly(reader, "main"));
  sqlite3_close(reader);
  sqlite3_close(writer);

  sqlite3 *locker = NULL, *blocked = NULL;
  ok(sqlite3_open_v2(locked, &locker, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL), locker, "open locker");
  ok(sqlite3_exec(locker, "PRAGMA journal_mode=DELETE; CREATE TABLE item(v INTEGER); INSERT INTO item VALUES(1); BEGIN EXCLUSIVE;", NULL, NULL, NULL), locker, "lock rollback db");
  ok(sqlite3_open_v2(locked, &blocked, SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE, NULL), blocked, "open blocked reader");
  ok(sqlite3_busy_timeout(blocked, 250), blocked, "blocked timeout");
  struct timespec a, b;
  clock_gettime(CLOCK_MONOTONIC, &a);
  int rc = SQLITE_OK;
  scalar(blocked, "SELECT count(*) FROM item", &rc);
  clock_gettime(CLOCK_MONOTONIC, &b);
  printf("busy_bound rc=%d elapsed_ms=%ld\n", rc, elapsed_ms(a, b));
  sqlite3_exec(locker, "ROLLBACK", NULL, NULL, NULL);
  sqlite3_close(blocked);
  sqlite3_close(locker);
  return (first == 1 && second == 2 && rc == SQLITE_BUSY) ? 0 : 2;
}
