#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int alive(pid_t pid) {
    if (kill(pid, 0) == 0) return 1;
    return errno != ESRCH;
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "--descendant") == 0) {
        signal(SIGTERM, SIG_IGN);
        int ready = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (ready < 0) return 2;
        close(ready);
        for (;;) pause();
    }

    int output[2];
    if (pipe(output) != 0) {
        perror("pipe");
        return 1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);

    posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, output[0]);
    posix_spawn_file_actions_addclose(&actions, output[1]);

    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT;
    posix_spawnattr_setflags(&attributes, flags);
    posix_spawnattr_setpgroup(&attributes, 0);

    char readyPath[PATH_MAX];
    snprintf(readyPath, sizeof(readyPath), "/tmp/pippin-g0-pgroup-ready-%d", getpid());
    unlink(readyPath);

    char *arguments[] = {
        "/bin/sh",
        "-c",
        "\"$0\" --descendant \"$1\" & descendant=$!; "
        "while [ ! -f \"$1\" ]; do sleep 0.01; done; "
        "trap 'exit 0' TERM; echo $descendant; wait",
        argv[0],
        readyPath,
        NULL
    };

    pid_t child = 0;
    int result = posix_spawn(&child, arguments[0], &actions, &attributes, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(output[1]);

    if (result != 0) {
        fprintf(stderr, "posix_spawn: %s\n", strerror(result));
        close(output[0]);
        return 1;
    }

    FILE *stream = fdopen(output[0], "r");
    long descendantValue = 0;
    if (stream == NULL || fscanf(stream, "%ld", &descendantValue) != 1) {
        fprintf(stderr, "failed to read descendant pid\n");
        kill(-child, SIGKILL);
        waitpid(child, NULL, 0);
        return 1;
    }
    fclose(stream);
    unlink(readyPath);
    pid_t descendant = (pid_t)descendantValue;

    pid_t childGroup = getpgid(child);
    pid_t descendantGroup = getpgid(descendant);
    printf("created child=%d descendant=%d child_group=%d descendant_group=%d\n",
           child, descendant, childGroup, descendantGroup);
    if (childGroup != child || descendantGroup != child) {
        fprintf(stderr, "unexpected process group\n");
        kill(-child, SIGKILL);
        waitpid(child, NULL, 0);
        return 1;
    }

    kill(-child, SIGTERM);
    int status = 0;
    pid_t reaped = 0;
    for (int attempt = 0; attempt < 40 && reaped == 0; attempt++) {
        reaped = waitpid(child, &status, WNOHANG);
        if (reaped == 0) usleep(50000);
    }
    printf("after_term leader_reaped=%d descendant_alive=%d descendant_group=%d\n",
           reaped == child, alive(descendant), getpgid(descendant));
    if (reaped != child || !alive(descendant) || getpgid(descendant) != child) {
        fprintf(stderr, "TERM did not leave the descendant-only group expected by the fixture\n");
        kill(-child, SIGKILL);
        if (reaped == 0) waitpid(child, NULL, 0);
        return 1;
    }

    kill(-child, SIGKILL);

    for (int attempt = 0; attempt < 40 && alive(descendant); attempt++) {
        usleep(50000);
    }
    printf("after_kill leader_exited=%d descendant_alive=%d\n",
           WIFEXITED(status), alive(descendant));

    return alive(descendant) ? 1 : 0;
}
