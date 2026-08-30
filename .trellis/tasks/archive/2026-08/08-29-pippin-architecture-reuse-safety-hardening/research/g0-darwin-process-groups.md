# G0: Race-Safe Darwin Process Groups

## Decision

Do not launch with Foundation `Process` and call `setpgid` afterward. The child
may exec before the parent changes its group, leaving a race in which descendants
escape timeout/cancellation cleanup.

Use Darwin `posix_spawn` directly:

1. initialize `posix_spawnattr_t` and `posix_spawn_file_actions_t`;
2. set `POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT`;
3. call `posix_spawnattr_setpgroup(attributes, 0)`; Darwin defines zero here as
   creating a new process group whose ID is the spawned child's PID;
4. use file actions to `dup2` the stdin/stdout/stderr pipes and close inherited
   pipe ends;
5. retain the returned child PID as both direct child PID and process-group ID;
6. reap the direct child with `waitpid`.

`POSIX_SPAWN_SETSID` is unnecessary: Pippin needs a killable process group, not
a new login/session boundary. No third-party process library is required.

Darwin's archived `posix_spawnattr_setpgroup(3)` documentation records the
zero-group behavior, and the installed macOS 26 SDK headers define both flags
and the required file-action APIs.

## Termination sequence

On operation timeout, queue cancellation after launch, or output overflow:

1. send `SIGTERM` to `-processGroupID`;
2. wait a fixed 200 ms grace period while continuing to drain/close pipes;
3. if the group still exists (`kill(-pgid, 0)` succeeds or returns `EPERM`), send
   `SIGKILL` to the group;
4. call `waitpid` for the direct child;
5. close every pipe descriptor on every exit path.

Signals are sent only to the group created atomically for that request. Pippin
must not use a caller-supplied PID/group or signal its own group. The final KILL
is issued immediately after the bounded grace period, before returning control,
which minimizes process-group-ID reuse risk.

## Scratch fixture

A C fixture used `posix_spawn` to run a shell whose compiled descendant ignored
TERM. The shell exited on TERM, leaving a process group with no group leader;
KILL addressed by the original group ID still removed the descendant. Three
consecutive runs verified the critical orphan-cleanup path:

The exact fixture is retained at `research/fixtures/darwin-process-group.c` and
can be rerun with:

```sh
xcrun clang -Wall -Wextra -Werror research/fixtures/darwin-process-group.c \
  -o /tmp/pippin-g0-pgroup
/tmp/pippin-g0-pgroup
```

```text
created child=51947 descendant=51948 child_group=51947 descendant_group=51947
after_term leader_reaped=1 descendant_alive=1 descendant_group=51947
after_kill leader_exited=1 descendant_alive=0
created child=51952 descendant=51953 child_group=51952 descendant_group=51952
after_term leader_reaped=1 descendant_alive=1 descendant_group=51952
after_kill leader_exited=1 descendant_alive=0
created child=51956 descendant=51957 child_group=51956 descendant_group=51956
after_term leader_reaped=1 descendant_alive=1 descendant_group=51956
after_kill leader_exited=1 descendant_alive=0
```

Step 3 must reproduce this behavior in Swift without invoking `osascript` or any
TCC data. Tests should also cover normal exit, spawn failure, cancellation,
bounded output, and descriptor cleanup.
