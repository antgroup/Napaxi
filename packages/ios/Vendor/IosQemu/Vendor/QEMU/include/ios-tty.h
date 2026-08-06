#ifndef LINUX_USER_IOS_TTY_H
#define LINUX_USER_IOS_TTY_H

#include "ios-inprocess.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

typedef struct IOSQemuTTY IOSQemuTTY;
typedef struct IOSQemuTTYFdSnapshot IOSQemuTTYFdSnapshot;
typedef struct IOSQemuTTYSparseScanStats {
    uint64_t snapshot_calls;
    uint64_t snapshot_slots;
    uint64_t snapshot_open_entries;
    uint64_t snapshot_ns;
    uint64_t destroy_calls;
    uint64_t destroy_slots;
    uint64_t destroy_open_entries;
    uint64_t destroy_ns;
} IOSQemuTTYSparseScanStats;

int ios_qemu_tty_create(
    const IOSQemuTerminal *terminal,
    unsigned short cols,
    unsigned short rows,
    IOSQemuTTY **out_tty
);
void ios_qemu_tty_destroy(IOSQemuTTY *tty);
void ios_qemu_tty_shutdown(IOSQemuTTY *tty);
int ios_qemu_tty_attach_thread(IOSQemuTTY *tty);
void ios_qemu_tty_detach_thread(void);
void ios_qemu_tty_set_process_identity(int session_id, int process_group);
ssize_t ios_qemu_tty_input(IOSQemuTTY *tty, const void *buf, size_t size, bool signal);
int ios_qemu_tty_resize(IOSQemuTTY *tty, unsigned short cols, unsigned short rows);
int ios_qemu_tty_open_path(const char *path, int flags);
bool ios_qemu_tty_is_fd(int fd);
bool ios_qemu_tty_is_dev_dir_fd(int fd);
bool ios_qemu_tty_is_pts_dir_fd(int fd);
bool ios_qemu_tty_is_fd_dir_fd(int fd);
bool ios_qemu_tty_is_dir_fd(int fd);
bool ios_qemu_tty_is_ptmx_fd(int fd);
ssize_t ios_qemu_tty_read_fd(int fd, void *buf, size_t size);
ssize_t ios_qemu_tty_write_fd(int fd, const void *buf, size_t size);
int ios_qemu_tty_poll_fd(int fd, short events, int timeout_ms, short *revents);
/* Host readiness fd for epoll/poll to watch this TTY (-1 if unavailable). */
int ios_qemu_tty_get_poll_fd(int fd);
bool ios_qemu_tty_has_input_fd(int fd);
long ios_qemu_tty_getdents64(int fd, unsigned long target_dirp, long count);
long ios_qemu_tty_ioctl(int fd, long request, unsigned long argp);
int ios_qemu_tty_dup_fd(int old_fd, int min_fd, bool cloexec);
int ios_qemu_tty_dup2_fd(int old_fd, int new_fd, bool cloexec);
int ios_qemu_tty_close_fd(int fd);
/* 对显式表(NULL=全局)清槽;fd 层 TTY 包装的释放路径用(见 ios-fd.c)。 */
int ios_qemu_tty_close_fd_in_table(IOSQemuTTYFdSnapshot *table, int fd);
int ios_qemu_tty_fstat_fd(int fd, struct stat *st);
ssize_t ios_qemu_tty_readlink_fd_path(const char *path, char *target, size_t target_size);
int ios_qemu_tty_get_fd_flags(int fd);
int ios_qemu_tty_set_fd_flags(int fd, int flags);
int ios_qemu_tty_get_status_flags(int fd);
int ios_qemu_tty_set_status_flags(int fd, int flags);
bool ios_qemu_tty_has_controlling_tty(void);
bool ios_qemu_tty_is_device_path(const char *path);
bool ios_qemu_tty_is_dev_dir_path(const char *path);
bool ios_qemu_tty_is_pts_dir_path(const char *path);
bool ios_qemu_tty_is_pts_slave_path(const char *path);
int ios_qemu_tty_stat_path(const char *path, struct stat *st);
int ios_qemu_tty_pts_name(IOSQemuTTY *tty, char *name, size_t name_size);
int ios_qemu_tty_pts_number(IOSQemuTTY *tty);

/*
 * Per-session/per-process tty fd table isolation (mirrors ios-fd.c's fd table
 * snapshot API). The tty fd table is otherwise a single global array shared by
 * all sessions, so concurrent session leaders alias each other's fd 0/1/2. Each
 * session leader installs a private empty table; a real fork copies it, a
 * CLONE_VM thread shares it by refcount; every table is released with unref.
 */
IOSQemuTTYFdSnapshot *ios_qemu_tty_fd_table_create_empty(void);
IOSQemuTTYFdSnapshot *ios_qemu_tty_fd_snapshot_create(void);
IOSQemuTTYFdSnapshot *ios_qemu_tty_fd_table_share(void);
/* 对显式表加引用(NULL 安全);与 table_unref 配对。 */
IOSQemuTTYFdSnapshot *ios_qemu_tty_fd_table_ref(IOSQemuTTYFdSnapshot *table);
void ios_qemu_tty_fd_table_unref(IOSQemuTTYFdSnapshot *table);
void ios_qemu_tty_fd_set_current_table(IOSQemuTTYFdSnapshot *table);
IOSQemuTTYFdSnapshot *ios_qemu_tty_fd_current_table(void);
long ios_qemu_tty_fd_table_live_count(void);
long ios_qemu_pty_registry_live_count(void);
void ios_qemu_tty_sparse_scan_stats_begin(void);
void ios_qemu_tty_sparse_scan_stats_end(IOSQemuTTYSparseScanStats *stats);

#endif
