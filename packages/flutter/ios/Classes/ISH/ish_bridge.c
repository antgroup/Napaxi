#include "ish_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>

#include "kernel/init.h"
#include "kernel/calls.h"
#include "kernel/task.h"
#include "kernel/signal.h"
#include "kernel/fs.h"
#include "fs/devices.h"
#include "fs/path.h"
#include "fs/real.h"
#include "fs/tty.h"
#include "tools/fakefs.h"

static int g_initialized = 0;
static pthread_mutex_t g_exec_lock = PTHREAD_MUTEX_INITIALIZER;

// Track child processes for exit detection
struct exec_context {
    pid_t_ child_pid;
    int exit_code;
    int exited;
    pthread_mutex_t lock;
    pthread_cond_t cond;
};

#define MAX_EXEC_CONTEXTS 16
static struct exec_context *g_contexts[MAX_EXEC_CONTEXTS];
static pthread_mutex_t g_contexts_lock = PTHREAD_MUTEX_INITIALIZER;

#define ISH_ARGV_BUF_SIZE 16384

static int build_exec_argv(char *buffer, size_t buffer_size, const char *args[], size_t argc) {
    size_t p = 0;

    if (!buffer || buffer_size == 0) return -E2BIG;

    for (size_t i = 0; i < argc; i++) {
        size_t len = strlen(args[i]);
        size_t remaining = buffer_size - p;

        // iSH expects argv as NUL-separated strings with one extra final NUL.
        if (remaining <= len + 1) return -E2BIG;

        memcpy(buffer + p, args[i], len + 1);
        p += len + 1;
    }

    buffer[p] = '\0';
    return 0;
}

static void bridge_exit_hook(struct task *task, int code) {
    pid_t_ task_pid = task->pid;
    pid_t_ pgid = task->group ? task->group->pgid : 0;
    pid_t_ leader_pid = (task->group && task->group->leader) ? task->group->leader->pid : 0;
    fprintf(stderr, "[ish] exit_hook: pid=%d pgid=%d leader=%d code=%d\n",
            task_pid, pgid, leader_pid, code);

    pthread_mutex_lock(&g_contexts_lock);
    for (int i = 0; i < MAX_EXEC_CONTEXTS; i++) {
        if (g_contexts[i] == NULL) continue;
        pid_t_ tracked = g_contexts[i]->child_pid;
        if (tracked == task_pid || tracked == leader_pid) {
            fprintf(stderr, "[ish] exit_hook: MATCHED ctx[%d] tracked=%d (by %s)\n",
                    i, tracked, tracked == task_pid ? "pid" : "leader");
            pthread_mutex_lock(&g_contexts[i]->lock);
            g_contexts[i]->exit_code = code;
            g_contexts[i]->exited = 1;
            pthread_cond_signal(&g_contexts[i]->cond);
            pthread_mutex_unlock(&g_contexts[i]->lock);
            break;
        }
    }
    pthread_mutex_unlock(&g_contexts_lock);
}

static void register_context(struct exec_context *ctx) {
    pthread_mutex_lock(&g_contexts_lock);
    for (int i = 0; i < MAX_EXEC_CONTEXTS; i++) {
        if (g_contexts[i] == NULL) {
            g_contexts[i] = ctx;
            break;
        }
    }
    pthread_mutex_unlock(&g_contexts_lock);
}

static void unregister_context(struct exec_context *ctx) {
    pthread_mutex_lock(&g_contexts_lock);
    for (int i = 0; i < MAX_EXEC_CONTEXTS; i++) {
        if (g_contexts[i] == ctx) {
            g_contexts[i] = NULL;
            break;
        }
    }
    pthread_mutex_unlock(&g_contexts_lock);
}

// --- PTY-based output capture ---
// When child writes to stdout/stderr (PTY slave), tty_write() calls our
// custom driver's write callback, which forwards data to a host pipe.
// This makes the child see isatty(stdout)==true → line buffering instead
// of full buffering, fixing npm/node/python etc. producing zero output.

static int g_pty_write_fd = -1; // host pipe write end, used by PTY write callback

static int bridge_pty_write(struct tty *tty, const void *buf, size_t len, bool blocking) {
    int wfd = g_pty_write_fd;
    if (wfd >= 0 && len > 0) {
        write(wfd, buf, len);
    }
    return len;
}

static struct tty_driver_ops bridge_pty_ops = {
    .write = bridge_pty_write,
};

// NOTE: Do NOT use DEFINE_TTY_DRIVER — pty_open_fake overwrites ttys/limit/major
static struct tty_driver bridge_pty_driver = {
    .ops = &bridge_pty_ops,
};

// Kill all emulated processes in the same process group as pgid.
static void kill_process_group(pid_t_ pgid) {
    fprintf(stderr, "[ish] killing process group pgid=%d\n", pgid);
    lock(&pids_lock);
    for (int i = 2; i < MAX_PID; i++) {
        struct task *t = pid_get_task(i);
        if (t != NULL && t->group->pgid == pgid) {
            fprintf(stderr, "[ish] killing pid=%d (pgid=%d)\n", t->pid, pgid);
            deliver_signal(t, SIGKILL_, SIGINFO_NIL);
        }
    }
    unlock(&pids_lock);
}

int ish_init(const char *rootfs_path) {
    if (g_initialized)
        return 0;

    fprintf(stderr, "[ish] init: rootfs=%s\n", rootfs_path);

    char data_path[4096];
    snprintf(data_path, sizeof(data_path), "%s/data", rootfs_path);

    struct stat st;
    if (stat(data_path, &st) != 0) {
        fprintf(stderr, "[ish] init: data path not found: %s\n", data_path);
        return -1;
    }

    int err = mount_root(&fakefs, data_path);
    if (err < 0) {
        fprintf(stderr, "[ish] init: mount_root failed: %d\n", err);
        return err;
    }

    err = become_first_process();
    if (err < 0) {
        fprintf(stderr, "[ish] init: become_first_process failed: %d\n", err);
        return err;
    }
    current->thread = pthread_self();

    // Create device nodes
    generic_mknodat(AT_PWD, "/dev/null", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
    generic_mknodat(AT_PWD, "/dev/full", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_FULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/random", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR|0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/tty", S_IFCHR|0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_TTY_MINOR));
    generic_mknodat(AT_PWD, "/dev/console", S_IFCHR|0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_CONSOLE_MINOR));
    generic_mknodat(AT_PWD, "/dev/ptmx", S_IFCHR|0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR));
    generic_mknodat(AT_PWD, "/dev/tty1", S_IFCHR|0666, dev_make(TTY_CONSOLE_MAJOR, 1));
    generic_mkdirat(AT_PWD, "/dev/pts", 0755);
    generic_setattrat(AT_PWD, "/", (struct attr) {.type = attr_mode, .mode = 0755}, false);

    do_mount(&procfs, "proc", "/proc", "", 0);
    do_mount(&devptsfs, "devpts", "/dev/pts", "", 0);

    tty_drivers[TTY_CONSOLE_MAJOR] = &real_tty_driver;
    set_console_device(MEM_MAJOR, DEV_NULL_MINOR);
    err = create_stdio("/dev/null", MEM_MAJOR, DEV_NULL_MINOR);
    if (err < 0) {
        fprintf(stderr, "[ish] init: create_stdio failed: %d\n", err);
        return err;
    }

    extern void (*exit_hook)(struct task *task, int code);
    exit_hook = bridge_exit_hook;

    const char *argv = "/bin/sh\0-c\0while true; do sleep 86400; done\0";
    const char *envp = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\0HOME=/root\0TERM=\0NO_COLOR=1\0";
    err = do_execve("/bin/sh", 3, argv, envp);
    if (err < 0) {
        fprintf(stderr, "[ish] init: do_execve failed: %d\n", err);
        return err;
    }

    task_start(current);
    usleep(100000);

    g_initialized = 1;
    fprintf(stderr, "[ish] init: kernel ready\n");
    return 0;
}

int ish_is_initialized(void) {
    return g_initialized;
}

// Read output from a single pipe. Stops on EOF, process exit, or overall timeout.
static int read_output(int pipe_fd, char *buf, size_t buf_size, size_t *out_len,
                       int timeout_ms, volatile int *exited_flag) {
    size_t total = 0;
    int eof = 0;

    if (buf_size <= 1) {
        buf[0] = '\0';
        *out_len = 0;
        return 0;
    }

    fcntl(pipe_fd, F_SETFL, O_NONBLOCK);

    struct timeval start_tv;
    gettimeofday(&start_tv, NULL);

    while (!eof && total < buf_size - 1) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(pipe_fd, &readfds);

        struct timeval tv = { .tv_sec = 0, .tv_usec = 200000 }; // 200ms
        int ret = select(pipe_fd + 1, &readfds, NULL, NULL, &tv);

        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }

        if (ret > 0 && FD_ISSET(pipe_fd, &readfds)) {
            ssize_t n = read(pipe_fd, buf + total, buf_size - 1 - total);
            if (n > 0) {
                total += n;
                buf[total] = '\0';
            } else if (n == 0) {
                eof = 1;
            } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
                eof = 1;
            }
        }

        // Process exited — drain remaining data then stop
        if (exited_flag && *exited_flag) {
            usleep(100000); // 100ms to let in-flight writes complete
            for (int drain = 0; drain < 10; drain++) {
                ssize_t n = read(pipe_fd, buf + total, buf_size - 1 - total);
                if (n > 0) {
                    total += n;
                    buf[total] = '\0';
                } else {
                    break;
                }
                usleep(20000);
            }
            break;
        }

        // Overall timeout + heartbeat
        if (timeout_ms > 0) {
            struct timeval now_tv;
            gettimeofday(&now_tv, NULL);
            long elapsed_ms = (now_tv.tv_sec - start_tv.tv_sec) * 1000
                              + (now_tv.tv_usec - start_tv.tv_usec) / 1000;
            if (elapsed_ms > 0 && (elapsed_ms / 5000) != ((elapsed_ms - 200) / 5000)) {
                fprintf(stderr, "[ish] waiting for output: %lds elapsed, %zu bytes so far\n",
                        elapsed_ms / 1000, total);
            }
            if (elapsed_ms >= timeout_ms) {
                fprintf(stderr, "[ish] output read timeout after %ldms\n", elapsed_ms);
                break;
            }
        }
    }

    buf[total] = '\0';
    *out_len = total;
    return eof ? 0 : -1;
}

int ish_exec(const char *command,
             const char *workdir,
             char *stdout_buf, size_t stdout_buf_size,
             char *stderr_buf, size_t stderr_buf_size,
             int timeout_ms) {
    if (!g_initialized) return -1;
    if (!command || !stdout_buf || !stderr_buf) return -2;

    stdout_buf[0] = '\0';
    stderr_buf[0] = '\0';

    fprintf(stderr, "[ish] exec: '%s' (timeout=%ds)\n", command, timeout_ms / 1000);

    char argv_buf[ISH_ARGV_BUF_SIZE];
    const char *args[] = { "/bin/sh", "-c", command };
    int err = build_exec_argv(argv_buf, sizeof(argv_buf), args, 3);
    if (err < 0) {
        fprintf(stderr, "[ish] exec: command argv too large: %d\n", err);
        return err;
    }

    pthread_mutex_lock(&g_exec_lock);

    // Create host pipe for capturing PTY output
    int output_pipe[2];
    if (pipe(output_pipe) < 0) {
        fprintf(stderr, "[ish] exec: pipe failed\n");
        pthread_mutex_unlock(&g_exec_lock);
        return -3;
    }

    // Set global pipe write fd for PTY callback
    g_pty_write_fd = output_pipe[1];

    struct task *saved_current = current;

    err = become_new_init_child();
    if (err < 0) {
        g_pty_write_fd = -1;
        close(output_pipe[0]); close(output_pipe[1]);
        current = saved_current;
        pthread_mutex_unlock(&g_exec_lock);
        return err;
    }

    pid_t_ child_pid = current->pid;
    fprintf(stderr, "[ish] exec: child pid=%d\n", child_pid);

    // Set working directory if provided (like proot -w)
    if (workdir && workdir[0] != '\0') {
        struct fd *dir_fd = generic_open(workdir, O_RDONLY_, 0);
        if (dir_fd && !IS_ERR(dir_fd)) {
            fs_chdir(current->fs, dir_fd);
            // NOTE: do NOT fd_close here — fs_chdir may not retain the fd
            // in this iSH build, so the fd must stay alive for the child process.
            fprintf(stderr, "[ish] exec: chdir to '%s'\n", workdir);
        } else {
            fprintf(stderr, "[ish] exec: chdir failed for '%s', using default\n", workdir);
        }
    }

    // Create PTY with custom driver for output capture.
    // pty_open_fake creates a slave tty whose driver->write callback is ours.
    // Child sees isatty(stdout)==true → line buffering (not full buffering).
    struct tty *tty = pty_open_fake(&bridge_pty_driver);
    if (IS_ERR(tty)) {
        fprintf(stderr, "[ish] exec: pty_open_fake failed: %ld\n", PTR_ERR(tty));
        g_pty_write_fd = -1;
        close(output_pipe[0]); close(output_pipe[1]);
        current = saved_current;
        pthread_mutex_unlock(&g_exec_lock);
        return (int)PTR_ERR(tty);
    }

    // Disable termios processing — we want raw output, no \n→\r\n conversion
    tty->termios.oflags = 0;
    tty->termios.iflags = 0;
    tty->termios.lflags = 0;

    // Attach PTY slave to child's fd 0/1/2
    char pts_path[64];
    snprintf(pts_path, sizeof(pts_path), "/dev/pts/%d", tty->num);
    fprintf(stderr, "[ish] exec: using PTY %s\n", pts_path);

    err = create_stdio(pts_path, TTY_PSEUDO_SLAVE_MAJOR, tty->num);
    if (err < 0) {
        fprintf(stderr, "[ish] exec: create_stdio(%s) failed: %d\n", pts_path, err);
        lock(&ttys_lock);
        tty_release(tty);
        unlock(&ttys_lock);
        g_pty_write_fd = -1;
        close(output_pipe[0]); close(output_pipe[1]);
        current = saved_current;
        pthread_mutex_unlock(&g_exec_lock);
        return err;
    }
    fprintf(stderr, "[ish] exec: create_stdio succeeded for %s\n", pts_path);

    // Release our initial ref — child holds refs via fd 0/1/2
    lock(&ttys_lock);
    tty_release(tty);
    unlock(&ttys_lock);

    // Set up exit tracking
    struct exec_context ctx = { .child_pid = child_pid, .exit_code = -1, .exited = 0 };
    pthread_mutex_init(&ctx.lock, NULL);
    pthread_cond_init(&ctx.cond, NULL);
    register_context(&ctx);

    const char *envp = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\0HOME=/root\0TERM=\0NO_COLOR=1\0";

    err = do_execve("/bin/sh", 3, argv_buf, envp);
    if (err < 0) {
        fprintf(stderr, "[ish] exec: do_execve failed: %d\n", err);
        g_pty_write_fd = -1;
        close(output_pipe[0]); close(output_pipe[1]);
        unregister_context(&ctx);
        pthread_mutex_destroy(&ctx.lock);
        pthread_cond_destroy(&ctx.cond);
        current = saved_current;
        pthread_mutex_unlock(&g_exec_lock);
        return err;
    }
    fprintf(stderr, "[ish] exec: do_execve succeeded\n");

    struct task *child_task = current;
    task_start(child_task);
    current = saved_current;
    pthread_mutex_unlock(&g_exec_lock);

    // Read output from host pipe (PTY callback writes here)
    // Combined stdout+stderr since PTY merges them (like a real terminal)
    size_t output_len = 0;
    read_output(output_pipe[0], stdout_buf, stdout_buf_size, &output_len,
                timeout_ms, &ctx.exited);

    // Stop the PTY callback from writing and close pipe
    g_pty_write_fd = -1;
    close(output_pipe[1]);
    close(output_pipe[0]);

    // Wait for exit_hook to fire (with short timeout)
    int timed_out = 0;
    pthread_mutex_lock(&ctx.lock);
    if (!ctx.exited) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += 3;
        pthread_cond_timedwait(&ctx.cond, &ctx.lock, &ts);

        if (!ctx.exited) {
            timed_out = 1;
            fprintf(stderr, "[ish] exec: process did not exit, killing pgid=%d\n", child_pid);
            kill_process_group(child_pid);

            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += 2;
            pthread_cond_timedwait(&ctx.cond, &ctx.lock, &ts);
        }
    }
    int exit_code = ctx.exited ? (ctx.exit_code >> 8) : -1;
    pthread_mutex_unlock(&ctx.lock);

    unregister_context(&ctx);
    pthread_mutex_destroy(&ctx.lock);
    pthread_cond_destroy(&ctx.cond);

    fprintf(stderr, "[ish] exec: done exit=%d timed_out=%d stdout=%zu\n",
            exit_code, timed_out, output_len);

    return timed_out ? -4 : exit_code;
}

int ish_mount_host(const char *host_path, const char *mount_point) {
    if (!g_initialized) return -1;
    if (!host_path || !mount_point) return -2;

    fprintf(stderr, "[ish] mount_host: %s -> %s\n", host_path, mount_point);

    // Ensure mount point directory exists inside Alpine
    generic_mkdirat(AT_PWD, mount_point, 0755);

    // Mount host iOS directory using realfs (direct passthrough to host filesystem)
    int err = do_mount(&realfs, host_path, mount_point, "", 0);
    if (err < 0) {
        fprintf(stderr, "[ish] mount_host: failed: %d\n", err);
        return err;
    }

    fprintf(stderr, "[ish] mount_host: OK\n");
    return 0;
}

void ish_shutdown(void) {
    g_initialized = 0;
}

int ish_import_rootfs(const char *archive_path, const char *fs_path) {
    fprintf(stderr, "[ish] import_rootfs: %s -> %s\n", archive_path, fs_path);
    struct fakefsify_error err;
    memset(&err, 0, sizeof(err));
    struct progress p = {NULL, NULL};
    if (!fakefs_import(archive_path, fs_path, &err, p)) {
        fprintf(stderr, "[ish] import_rootfs: failed: %s (line %d, code %d)\n",
                err.message ? err.message : "unknown", err.line, err.code);
        if (err.message) free(err.message);
        return -1;
    }
    fprintf(stderr, "[ish] import_rootfs: done\n");
    return 0;
}
