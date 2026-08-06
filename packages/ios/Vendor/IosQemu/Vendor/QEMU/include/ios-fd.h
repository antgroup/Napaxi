#ifndef LINUX_USER_IOS_FD_H
#define LINUX_USER_IOS_FD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/uio.h>

typedef struct IOSQemuFd IOSQemuFd;
typedef struct IOSQemuFdSnapshot IOSQemuFdSnapshot;
typedef struct IOSQemuFdSparseScanStats {
    uint64_t snapshot_calls;
    uint64_t snapshot_slots;
    uint64_t snapshot_open_entries;
    uint64_t snapshot_ns;
    uint64_t destroy_calls;
    uint64_t destroy_slots;
    uint64_t destroy_open_entries;
    uint64_t destroy_ns;
    uint64_t cloexec_calls;
    uint64_t cloexec_slots;
    uint64_t cloexec_closed_entries;
    uint64_t cloexec_ns;
} IOSQemuFdSparseScanStats;
struct IOSQemuTTYFdSnapshot;
struct IOSQemuFdWriter;
typedef void (*IOSQemuFdIterFn)(int guest_fd, void *opaque);

int ios_qemu_fd_open_host(int host_fd, int flags);
int ios_qemu_fd_open_host_with_guest_path(int host_fd, int flags,
                                          const char *guest_path);
int ios_qemu_fd_open_eventfd(unsigned int initval, int target_flags,
                             bool semaphore);
/* timerfd value as plain nanoseconds, to avoid depending on struct itimerspec
 * (not visible in this Darwin build's feature-macro level). */
typedef struct IOSTimerfdSpec {
    int64_t interval_ns;
    int64_t value_ns;
} IOSTimerfdSpec;

int ios_qemu_fd_open_timerfd(int host_clockid, int target_flags);
int ios_qemu_fd_timerfd_settime(int guest_fd, int flags,
                                const IOSTimerfdSpec *new_value,
                                IOSTimerfdSpec *old_value);
int ios_qemu_fd_timerfd_gettime(int guest_fd, IOSTimerfdSpec *curr_value);
int ios_qemu_fd_open_epoll(int target_flags);
int ios_qemu_fd_get_epoll_kq(int guest_fd);
/* 释放 epoll kqueue 时清理 darwin-syscall.c 持有的独立 TTY watch fd。 */
void ios_qemu_epoll_unregister_kq(int kq);
int ios_qemu_fd_open_signalfd(uint64_t mask, int target_flags);
int ios_qemu_fd_signalfd_setmask(int guest_fd, uint64_t mask);
/* Darwin kqueue-backed inotify compatibility used by Bun/Claude Code. */
int ios_qemu_fd_open_inotify(int target_flags);
int ios_qemu_fd_inotify_add_watch(int guest_fd, const char *host_path,
                                  uint32_t mask);
int ios_qemu_fd_inotify_rm_watch(int guest_fd, int watch_id);
void ios_qemu_signalfd_notify(int sig);
/* Defined in darwin-syscall.c (needs the guest signal state). */
ssize_t ios_qemu_signalfd_consume(uint64_t mask, void *buf, size_t size);
bool ios_qemu_signalfd_pending(uint64_t mask);
int ios_qemu_fd_open_dev(int dev_fd, int flags);
int ios_qemu_fd_open_proc(int proc_fd, int flags);
int ios_qemu_fd_bind_host(int guest_fd, int host_fd, int flags);
int ios_qemu_fd_bind_tty(int guest_fd, int tty_fd, int flags);
ssize_t ios_qemu_fd_read(int guest_fd, void *buf, size_t size);
ssize_t ios_qemu_fd_write(int guest_fd, const void *buf, size_t size);
int ios_qemu_fd_close(int guest_fd);
/* Linux close_range over the virtual guest fd table. flags accepts the Linux
 * CLOSE_RANGE_* bits; unsupported semantics return an error without touching fds. */
int ios_qemu_fd_close_range(unsigned int first, unsigned int last,
                            unsigned int flags);
int ios_qemu_fd_dup(int guest_fd, int min_guest_fd, bool cloexec);
int ios_qemu_fd_dup2(int old_guest_fd, int new_guest_fd, bool cloexec);
int ios_qemu_fd_get_backend_fd(int guest_fd);
int ios_qemu_fd_get_host_fd(int guest_fd);
/* CLI host execve 物化:为 guest fd 造可继承宿主 fd(CLOEXEC,>=min_fd,
 * 调用方持有);HOST/DEV kind 之外返回 -1。 */
int ios_qemu_fd_exec_inherit_host_fd(int guest_fd, int min_fd);
/* guest 显式 close 过 stdio fd 且槽位为空(host execve 物化需同步关宿主槽)。 */
bool ios_qemu_fd_stdio_slot_closed(int fd);
/* CLI 重启进程 adopt "-ios-fds" 传来的跨 exec 继承宿主 fd(逗号分隔号列表)。 */
void ios_qemu_fd_adopt_inherited(const char *spec);
int ios_qemu_fd_get_poll_fd(int guest_fd);
/* epoll_ctl 使用同一次 fd lookup 同时取得 poll fd 与对象类型。 */
int ios_qemu_fd_get_poll_fd_info(int guest_fd, bool *is_eventfd,
                                     bool *is_tty);
/* EPOLLET eventfd 派发后确认合并通知，使后续 write 可产生新边沿。 */
bool ios_qemu_fd_eventfd_ack(int guest_fd, int poll_fd);
int ios_qemu_fd_get_host_dirfd(int guest_fd);
int ios_qemu_fd_set_guest_path(int guest_fd, const char *guest_path);
char *ios_qemu_fd_get_guest_path(int guest_fd);
int ios_qemu_fd_getfd(int guest_fd);
int ios_qemu_fd_setfd(int guest_fd, int flags);
int ios_qemu_fd_getfl(int guest_fd);
int ios_qemu_fd_setfl(int guest_fd, int flags);
int ios_qemu_fd_fstat(int guest_fd, struct stat *st);
off_t ios_qemu_fd_lseek(int guest_fd, off_t offset, int whence);
bool ios_qemu_fd_is_tty(int guest_fd);
bool ios_qemu_fd_is_dir(int guest_fd);
int ios_qemu_fd_poll(int guest_fd, short events, int timeout_ms, short *revents);
bool ios_qemu_fd_has_input(int guest_fd);
long ios_qemu_fd_getdents64(int guest_fd, unsigned long target_dirp, long count);
ssize_t ios_qemu_fd_readlink_path(int guest_fd, char *target, size_t target_size);
void ios_qemu_fd_for_each_open(IOSQemuFdIterFn callback, void *opaque);
/* 创建一张空私有 fd 表(refcount 1);session leader 装它以脱离全局共享表。 */
IOSQemuFdSnapshot *ios_qemu_fd_table_create_empty(void);
/* 在空表发布前固化临时 IOSQemuFd 引用的无全局锁 put 策略。 */
void ios_qemu_fd_table_set_atomic_ref_fast(IOSQemuFdSnapshot *table,
                                           bool enabled);
/* 为 real-fork 子进程复制 fd 表。TTY kind 造指向 child_tty_table 同号槽位的
 * 新包装(包装持该表引用),调用方必须先建好子 tty 表再建 fd 快照。 */
IOSQemuFdSnapshot *ios_qemu_fd_snapshot_create(struct IOSQemuTTYFdSnapshot *child_tty_table);
void ios_qemu_fd_snapshot_restore(IOSQemuFdSnapshot *snapshot);
IOSQemuFdSnapshot *ios_qemu_fd_snapshot_exchange(IOSQemuFdSnapshot *snapshot);
void ios_qemu_fd_snapshot_destroy(IOSQemuFdSnapshot *snapshot);
void ios_qemu_fd_set_current_table(IOSQemuFdSnapshot *table);
IOSQemuFdSnapshot *ios_qemu_fd_current_table(void);
/* CLONE_VM 线程共享调用线程的私有 fd 表(refcount++);identity(全局表)返回 NULL。 */
IOSQemuFdSnapshot *ios_qemu_fd_table_share(void);
/* 释放一个 share/继承引用;最后一个引用者真正销毁表。NULL 安全。 */
void ios_qemu_fd_table_unref(IOSQemuFdSnapshot *table);
void ios_qemu_fd_do_cloexec(void);
/* 并发/生命周期 harness 诊断计数；只在对象创建销毁或 fast last-put 时更新。 */
long ios_qemu_fd_table_live_count(void);
long ios_qemu_fd_writer_box_live_count(void);
unsigned long long ios_qemu_fd_atomic_final_release_count(void);
/* fork/exec 稀疏扫描的确定性计数；begin/end 之间才进入计数分支。 */
void ios_qemu_fd_sparse_scan_stats_begin(void);
void ios_qemu_fd_sparse_scan_stats_end(IOSQemuFdSparseScanStats *stats);

/*
 * 一次性 exec 的 stdout/stderr 捕获 writer,挂在 fd 表上(不再是 __thread):
 * real fork 复制表时子表引用同一个 writer box、CLONE_VM 共享表天然可见,
 * 于是 guest 真 fork 出的子进程(管道、多命令)的 fd 1/2 输出也进捕获缓冲。
 * box 引用计数随表走;deactivate 后(exec API 已返回,caller 缓冲不再有效)
 * 迟到的后台子进程写入被静默吞掉,不会悬垂访问 caller 栈上的捕获上下文。
 */
int ios_qemu_fd_table_set_writer(IOSQemuFdSnapshot *table,
                                 const struct IOSQemuFdWriter *writer);
void ios_qemu_fd_table_deactivate_writer(IOSQemuFdSnapshot *table);
/* 当前线程 fd 表是否挂着捕获通道(writer box)。按 box 存在判定,失活后仍
 * true——写路由继续把 fd 1/2 送进 ios_qemu_fd_writer_write 吞掉而不回落
 * 宿主 stdio;session_active(setpgid/kill 任务表路由)也依赖它在 exec API
 * 返回后对存活进程树保持稳定。 */
bool ios_qemu_fd_writer_present(void);
/* 经当前表的 writer 写 fd 1/2;无 box 返回 -1(调用方走真实 backend),
 * box 已失活则吞掉并伪装写满(benign:exec 已返回的孤儿后台子进程)。 */
ssize_t ios_qemu_fd_writer_write(int fd, const void *buf, size_t size);
/* one-shot 捕获快路径：一次 fdtable lookup 同时完成资格判断和 capture fd
 * 映射，再只持一次 writer box 锁完成单次/整组 iovec 写入。返回 true 表示
 * 本次写已由捕获通道处理（包括 deactivate 后静默吞掉）；false 由调用方继续
 * 走 tty/真实 backend/旧捕获路径。 */
bool ios_qemu_fd_writer_try_write(int fd, const void *buf, size_t size,
                                  ssize_t *written);
bool ios_qemu_fd_writer_try_writev(int fd, const struct iovec *iov, int iovcnt,
                                   ssize_t *written);

/* guest 进程的 stdout/stderr 是否已被 dup/dup2 重定向出终端/捕获通道。
 * 状态属于 fd 表(per guest 进程,fork 复制、CLONE_VM 共享),不是 __thread。 */
bool ios_qemu_fd_stdio_redirected(int fd);
void ios_qemu_fd_stdio_set_redirected(int fd, bool redirected);
/* guest fd 是否是 stdio 替身(懒绑定造的宿主 stdio dup;dup 共享同一包装,
 * busybox 重定向保存/恢复 fd1 时据此识别"恢复回终端/捕获通道")。 */
bool ios_qemu_fd_is_stdio_surrogate(int guest_fd);

#endif
