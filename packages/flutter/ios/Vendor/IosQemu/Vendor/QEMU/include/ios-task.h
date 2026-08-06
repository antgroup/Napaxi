#ifndef LINUX_USER_IOS_TASK_H
#define LINUX_USER_IOS_TASK_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

typedef bool (*IOSQemuTaskPidIterFn)(pid_t pid, void *opaque);

typedef enum IOSQemuTaskWaitStatus {
    IOS_QEMU_TASK_WAIT_NONE = 0,
    IOS_QEMU_TASK_WAIT_LIVE = 1,
    IOS_QEMU_TASK_WAIT_ZOMBIE = 2,
} IOSQemuTaskWaitStatus;

typedef struct IOSQemuTaskSnapshot {
    pid_t pid_override;
    pid_t tid_override;
    pid_t process_group;
    pid_t session_id;
    uint64_t mm_id;
} IOSQemuTaskSnapshot;

pid_t ios_qemu_task_getpid(void);
pid_t ios_qemu_task_gettid(void);
pid_t ios_qemu_task_getppid(void);
uint64_t ios_qemu_task_get_mm_id(void);
uint64_t ios_qemu_task_get_mm_id_for_pid(pid_t pid);
bool ios_qemu_task_same_mm(pid_t left_pid, pid_t right_pid);
void ios_qemu_task_set_pid_override(pid_t pid);
/* 读当前线程的 pid override(0=未设置)。一次性 exec 在设置前保存、结束时
 * 恢复,不硬清:防将来在已持 override 的线程(session 线程内代跑 exec)上
 * 调用时把外层身份静默清成宿主 getpid 别名。 */
pid_t ios_qemu_task_get_pid_override(void);
void ios_qemu_task_enter_thread(pid_t tid, pid_t tgid);
void ios_qemu_task_register_fork_child(pid_t child_pid, pid_t parent_pid,
                                       pid_t process_group, pid_t session_id,
                                       bool current_task);
pid_t ios_qemu_task_get_process_group(void);
pid_t ios_qemu_task_get_session_id(void);
bool ios_qemu_task_get_process_group_for_pid(pid_t pid, pid_t *pgid);
bool ios_qemu_task_get_session_id_for_pid(pid_t pid, pid_t *sid);
int ios_qemu_task_set_process_group(pid_t pid, pid_t pgid);
bool ios_qemu_task_set_session_id(void);
void ios_qemu_task_set_clear_tid(uint64_t clear_tid);
uint64_t ios_qemu_task_get_clear_tid(void);
void ios_qemu_task_reset_current_thread_state(void);
void ios_qemu_task_exec_current(void);
void ios_qemu_task_set_robust_list(uint64_t robust_list, uint64_t len);
bool ios_qemu_task_get_robust_list(pid_t pid, uint64_t *robust_list, uint64_t *len);
int ios_qemu_task_exit_current(void);
bool ios_qemu_task_current_is_thread(void);
bool ios_qemu_task_current_has_peer_thread(void);
void ios_qemu_task_request_exit_group(int status);
bool ios_qemu_task_exit_group_requested(int *status);
pid_t ios_qemu_task_allocate_session_pid(void);
pid_t ios_qemu_task_allocate_child_pid(void);
pid_t ios_qemu_task_allocate_child_pid_with_mm(bool share_parent_mm,
                                               int exit_signal);
pid_t ios_qemu_task_allocate_child_pid_with_parent_mm(pid_t child_ppid,
                                                      bool share_parent_mm,
                                                      int exit_signal);
pid_t ios_qemu_task_allocate_thread_tid(void);
void ios_qemu_task_mark_vfork_child(pid_t pid);
void ios_qemu_task_notify_vfork(pid_t pid);
void ios_qemu_task_wait_vfork(pid_t pid);
void ios_qemu_task_mark_child_zombie(pid_t pid, int status);
void ios_qemu_task_forget_pid(pid_t pid);
bool ios_qemu_task_has_wait_child(void);
bool ios_qemu_task_has_child(pid_t requested_pid, pid_t requested_pgid);
IOSQemuTaskWaitStatus ios_qemu_task_wait_child(pid_t requested_pid,
                                               pid_t requested_pgid,
                                               pid_t *pid, int *status,
                                               bool reap, bool nohang);
bool ios_qemu_task_peek_wait_child(pid_t requested_pid, pid_t *pid, int *status);
bool ios_qemu_task_take_wait_child(pid_t requested_pid, pid_t *pid, int *status);
bool ios_qemu_task_peek_wait_child_group(pid_t requested_pgid, pid_t *pid,
                                         int *status);
bool ios_qemu_task_take_wait_child_group(pid_t requested_pgid, pid_t *pid,
                                         int *status);
bool ios_qemu_task_pid_exists(pid_t pid);
bool ios_qemu_task_process_group_exists(pid_t pgid);
bool ios_qemu_task_get_tgid(pid_t pid, pid_t *tgid);
bool ios_qemu_task_get_proc_visible_tgid(pid_t pid, pid_t *tgid);
/*
 * 进程身份(comm/cmdline):exec 落地时由 ios_qemu_main 写入当前 guest pid;
 * fork/clone 子任务出生时从父记录拷贝(见 register_fork_child /
 * allocate_child_pid_* / allocate_thread_tid),直到自己再 exec 覆盖。
 * 全部在 ios_qemu_task_lock 下读写;cmdline 含内嵌 NUL(argv 各段以 NUL 分隔),
 * 查询时锁下拷贝出来再返回,绝不把内部指针递给 proc 层。
 */
/*
 * exec 落地时的映像快照(来自 loader 填好的 image_info)。exe_path 是 guest 可见
 * 路径(argv0);地址字段供 /proc/<pid>/maps 标 [stack]/[heap]/[vdso] 与主映像段
 * (区间 [load_addr, end_data))。存进程表(随记录生命周期、fork/clone 继承),
 * 避免 proc 层读 ts->info——那指向 ios_qemu_main 栈帧,组长退出后即悬垂。
 *
 * env_start/env_end/auxv_start/auxv_len 供 /proc/<pid>/{environ,auxv} 真实化:
 * env_start=info->env_strings、env_end=info->file_string(elfload.c 构造顺序保证
 * envp 字符串块恰是 [env_strings, file_string),STACK_GROWS_DOWN/UP 两支公式相同,
 * 见 elfload.c load_elf_binary);auxv_start=info->saved_auxv、auxv_len=info->auxv_len
 * (字节数)。这些是 guest 虚拟地址,只在写入时那个线程的 guest_base 窗口内有效——
 * proc 层读取前必须确认 subject 与读取者同地址空间(同 tgid),否则回退空串,
 * 不能跨进程窗口硬翻译。
 */
typedef struct IOSQemuTaskExecImage {
    const char *exe_path;  /* set 时借用;get 时 g_strdup 出来由调用方 g_free */
    uint64_t load_addr;
    uint64_t end_data;
    uint64_t brk;
    uint64_t stack_limit;
    uint64_t vdso;
    uint64_t env_start;
    uint64_t env_end;
    uint64_t auxv_start;
    uint64_t auxv_len;
} IOSQemuTaskExecImage;
void ios_qemu_task_set_exec_identity(pid_t pid, char *const argv[],
                                     const IOSQemuTaskExecImage *image);
/* get 时 out->exe_path 是新分配的拷贝(调用方 g_free);无记录返 false。 */
bool ios_qemu_task_get_image(pid_t pid, IOSQemuTaskExecImage *out);
bool ios_qemu_task_get_comm(pid_t pid, char *out, size_t cap);
char *ios_qemu_task_get_cmdline(pid_t pid, size_t *out_len);
bool ios_qemu_task_get_ppid_for_pid(pid_t pid, pid_t *out);
bool ios_qemu_task_get_zombie(pid_t pid, bool *zombie);
/* 一次持锁取齐 /proc/<pid>/{stat,status} 所需字段 + 线程数,消撕裂快照与逐字段取锁。 */
typedef struct IOSQemuTaskProcInfo {
    pid_t ppid;
    pid_t process_group;
    pid_t session_id;
    pid_t tgid;
    bool zombie;
    int threads;
    char comm[16];
} IOSQemuTaskProcInfo;
bool ios_qemu_task_get_proc_info(pid_t pid, IOSQemuTaskProcInfo *out);
/* per-task cwd:set 写当前 guest pid(chdir/fchdir 经 ios_qemu_set_guest_cwd 落库),
 * get 返回 subject 的 cwd 拷贝(调用方 g_free;无记录返 NULL,调用方回落当前 cwd)。 */
void ios_qemu_task_set_cwd(const char *cwd);
char *ios_qemu_task_get_cwd(pid_t pid);
bool ios_qemu_task_add_pending_signal(pid_t pid, int sig);
bool ios_qemu_task_add_pending_signal_group(pid_t pgid, int sig);
bool ios_qemu_task_add_pending_signal_group_except(pid_t pgid, int sig,
                                                   pid_t skip_pid);
bool ios_qemu_task_add_pending_signal_all(int sig);
bool ios_qemu_task_add_pending_signal_all_except(int sig, pid_t skip_pid);
bool ios_qemu_task_take_pending_signal(pid_t pid, int *sig);
bool ios_qemu_task_take_pending_signal_masked(pid_t pid, uint64_t mask, int *sig);
bool ios_qemu_task_has_pending_signal_masked(pid_t pid, uint64_t mask);
void ios_qemu_task_wait_current_pending_signal(void);
bool ios_qemu_task_for_each_pid(IOSQemuTaskPidIterFn callback, void *opaque);
bool ios_qemu_task_for_each_tid(pid_t tgid, IOSQemuTaskPidIterFn callback,
                                void *opaque);
/* 测试/诊断用：返回任务表当前占用槽位数。 */
size_t ios_qemu_task_record_count(void);
IOSQemuTaskSnapshot ios_qemu_task_snapshot_save(void);
void ios_qemu_task_snapshot_restore(IOSQemuTaskSnapshot snapshot);
#ifdef CONFIG_IOS_QEMU_INPROCESS
void ios_qemu_process_image_unregister(pid_t pid);
#endif

#endif
