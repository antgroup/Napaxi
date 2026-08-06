#ifndef LINUX_USER_IOS_INPROCESS_H
#define LINUX_USER_IOS_INPROCESS_H

#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>

#ifndef G_NORETURN
#if defined(__GNUC__) || defined(__clang__)
#define G_NORETURN __attribute__((noreturn))
#else
#define G_NORETURN
#endif
#endif

#ifndef TARGET_IOS_EXIT_RESTART_EXEC
#define TARGET_IOS_EXIT_RESTART_EXEC 9999
#endif

typedef int (*IOSQemuMainFn)(int argc, char **argv, char **envp);
typedef void (*IOSQemuRunFn)(void *opaque);
typedef int (*IOSQemuCancelCheckFn)(void *opaque);
struct iovec;
typedef ssize_t (*IOSQemuFdWriteFn)(void *opaque, int fd, const void *buf, size_t size);
typedef ssize_t (*IOSQemuFdWritevFn)(void *opaque, int fd,
                                     const struct iovec *iov, int iovcnt);
typedef ssize_t (*IOSQemuTerminalReadFn)(void *opaque, void *buf, size_t size);
typedef ssize_t (*IOSQemuTerminalWriteFn)(void *opaque, const void *buf, size_t size);
typedef void (*IOSQemuTerminalInputConsumedFn)(void *opaque, size_t size);
typedef int (*IOSQemuTerminalGetSizeFn)(void *opaque, unsigned short *cols, unsigned short *rows);
typedef int (*IOSQemuTerminalSetSizeFn)(void *opaque, unsigned short cols, unsigned short rows);

typedef struct IOSQemuTerminal {
    void *opaque;
    IOSQemuTerminalReadFn read;
    IOSQemuTerminalWriteFn write;
    IOSQemuTerminalInputConsumedFn input_consumed;
    IOSQemuTerminalGetSizeFn get_size;
    IOSQemuTerminalSetSizeFn set_size;
} IOSQemuTerminal;

typedef struct IOSQemuFdWriter {
    void *opaque;
    IOSQemuFdWriteFn write;
    /* 可选批量回调：只由明确支持 writev 语义的 writer 设置；其余 writer
     * 继续经 write 逐段 fallback，避免把捕获优化扩散成通用 fd 行为变化。 */
    IOSQemuFdWritevFn writev;
    /* 一次性 exec 捕获快路径配置。创建 writer box 时固化，生命周期内不变；
     * 这样 fd 写热路径无需逐次 getenv，也不会与 deactivate 清空 callback 竞争。 */
    bool fast_path;
} IOSQemuFdWriter;

/* real-fork/exec 与顶层映像生命周期的诊断计数；只在
 * IOS_QEMU_PROCESS_PERF_STATS 下启用。 */
typedef enum IOSQemuProcessPerfStage {
    IOS_QEMU_PROCESS_PERF_MAIN_PRE_CPU,
    IOS_QEMU_PROCESS_PERF_MAIN_RESET_ENV_ARGS,
    IOS_QEMU_PROCESS_PERF_MAIN_INIT_PATHS,
    IOS_QEMU_PROCESS_PERF_MAIN_OPEN_ELF,
    IOS_QEMU_PROCESS_PERF_MAIN_CPU_MODEL,
    IOS_QEMU_PROCESS_PERF_MAIN_ACCEL_THREAD,
    IOS_QEMU_PROCESS_PERF_CPU_CREATE_RESET,
    IOS_QEMU_PROCESS_PERF_MAIN_PRE_LOADER,
    IOS_QEMU_PROCESS_PERF_POOL_ENTER_EMPTY,
    IOS_QEMU_PROCESS_PERF_LOADER_EXEC,
    IOS_QEMU_PROCESS_PERF_MAIN_POST_LOADER,
    IOS_QEMU_PROCESS_PERF_INIT_MAIN_THREAD,
    IOS_QEMU_PROCESS_PERF_IMAGE_FINALIZE,
    IOS_QEMU_PROCESS_PERF_EXEC_RESET,
    IOS_QEMU_PROCESS_PERF_RELEASE_ADDRESS_SPACE,
    IOS_QEMU_PROCESS_PERF_RELEASE_MISC,
    IOS_QEMU_PROCESS_PERF_RELEASE_CPU,
} IOSQemuProcessPerfStage;

typedef struct IOSQemuProcessPerfStats {
    uint64_t image_calls;
    uint64_t main_pre_cpu_ns;
    uint64_t main_reset_env_args_ns;
    uint64_t main_init_paths_ns;
    uint64_t main_open_elf_ns;
    uint64_t exec_fd_path_attempts;
    uint64_t exec_fd_path_hits;
    uint64_t main_cpu_model_ns;
    uint64_t main_accel_thread_ns;
    uint64_t cpu_create_reset_ns;
    uint64_t main_pre_loader_ns;
    uint64_t pool_enter_empty_ns;
    uint64_t loader_exec_ns;
    uint64_t main_post_loader_ns;
    uint64_t init_main_thread_ns;
    uint64_t image_finalize_ns;
    uint64_t cpu_loop_calls;
    uint64_t cpu_loop_ns;
    uint64_t exec_reset_ns;
    uint64_t release_address_space_ns;
    uint64_t release_misc_ns;
    uint64_t release_cpu_ns;
    uint64_t fork_calls;
    uint64_t fork_parent_setup_ns;
    uint64_t fork_cpu_copy_ns;
    uint64_t fork_address_space_ns;
    uint64_t fork_fd_snapshot_ns;
    uint64_t fork_pthread_ready_ns;
    uint64_t fork_vfork_wait_ns;
    uint64_t child_setup_ns;
    uint64_t child_run_ns;
    uint64_t child_teardown_ns;
    uint64_t exec_prepare_calls;
    uint64_t exec_prepare_ns;
    uint64_t wait_calls;
    uint64_t wait_ns;
} IOSQemuProcessPerfStats;

int ios_qemu_main(int argc, char **argv, char **envp);
int ios_qemu_runtime_init_once(const char *qemu_path, const char *rootfs_path);
int ios_qemu_inprocess_enter(IOSQemuMainFn main_fn, int argc, char **argv, char **envp);
int ios_qemu_inprocess_run(IOSQemuRunFn run_fn, void *opaque);
/*
 * runner 在 guest execve 重入前调用：按 Linux exec 语义重置当前进程映像，
 * 释放旧 CPUState，并把 pool 地址空间换成空表供新 ELF loader 使用。
 */
void ios_qemu_inprocess_prepare_exec_restart(void);
/*
 * runner 在顶层 guest 最终退出后调用：释放当前线程持有的 signal table、
 * pool 地址空间和 CPUState。不会清理 task/fd/tty；这些仍由 runner 按各自
 * 生命周期处理。
 */
void ios_qemu_inprocess_release_current_image(void);
int ios_qemu_get_exec_request(char ***argv, char ***envp);
void ios_qemu_clear_exec_request(void);
bool ios_qemu_has_exec_request(void);
/* 单进程性能诊断：env 门控，由 one-shot runner 在进入/退出 guest 时调用。
 * 统计所有 real-fork/CLONE_VM 子线程的 syscall 号和 arg3 累计，输出到宿主 stderr。 */
void ios_qemu_syscall_stats_begin(void);
void ios_qemu_syscall_stats_end(void);
void ios_qemu_process_perf_stats_begin(void);
void ios_qemu_process_perf_stats_end(IOSQemuProcessPerfStats *stats);
/* 返回 0 表示诊断关闭；调用方只在非零时结束对应阶段。 */
uint64_t ios_qemu_process_perf_stage_begin(void);
void ios_qemu_process_perf_stage_end(IOSQemuProcessPerfStage stage,
                                     uint64_t started_ns);
/* cpu_loop 通过 longjmp 退出，入口在 main.c 标记，出口由 inprocess 边界结算。 */
void ios_qemu_process_perf_cpu_loop_enter(void);
void ios_qemu_process_perf_cpu_loop_exit(void);
void ios_qemu_process_perf_record_exec_fd_path(bool hit);
/* latency trace 专用：采样所有已注册 guest pthread 的宿主/guest 执行位置。 */
void ios_qemu_debug_dump_host_threads(const char *reason);
/*
 * argv_is_qemu_wrapped 由生产方声明:true 表示 argv 已是 QEMU 包装形态
 * ([qemu, -L, prefix, -C, cwd, -0, argv0, exec-target, ...],do_execv 构造)。
 * runner 据此决定 exec 重入时直接复用还是再包一层,不再靠 argv[0] 是否以
 * "qemu-" 开头猜测(qemu_path 命名任意时会误判成双重包装 → guest argv[0]="-L")。
 */
int ios_qemu_request_exec(char **argv, char **envp, bool argv_is_qemu_wrapped);
/* exec 重入前查询:上一次 request_exec 的 argv 是否已是 QEMU 包装形态。 */
bool ios_qemu_exec_request_was_wrapped(void);
void ios_qemu_begin_pseudo_child_fork(void);
bool ios_qemu_take_pseudo_child_exec(void);
/* 当前线程是否属于 in-process 运行时(跨 fork 传播);guest fork 据此路由到
 * run_real_fork(pthread)而非 host fork()。 */
bool ios_qemu_inprocess_active(void);
/* Guest 可见 CPU 数量：IOS_QEMU_GUEST_CPUS 未设置时使用宿主在线 CPU 数。 */
long ios_qemu_guest_cpu_count(void);
void ios_qemu_set_active_terminal(const IOSQemuTerminal *terminal);
const IOSQemuTerminal *ios_qemu_get_active_terminal(void);
/* 一次性 exec 的捕获 writer 挂 fd 表(ios_qemu_fd_table_set_writer,见
 * ios-fd.h),随 real fork 复制 / CLONE_VM 共享;不再提供 __thread 版本。 */
void ios_qemu_set_cancel_check(IOSQemuCancelCheckFn check, void *opaque);
bool ios_qemu_should_cancel(void);
void ios_qemu_guest_exit(int code) G_NORETURN;

#endif
