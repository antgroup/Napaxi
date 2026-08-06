#include "qemu_runner.h"
#include "ios-fd.h"
#include "ios-inprocess.h"
#include "ios-task.h"
#include "ios-tty.h"

#include <TargetConditionals.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* M6 真机命中率诊断:AOT adopt 命中统计(实现于 accel/tcg/ios-qemu-aot.c)。 */
extern bool ios_qemu_aot_static_active(void);
extern void ios_qemu_aot_hit_stats(uint64_t *hits, uint64_t *misses);

static char g_qemu_path[4096] = {0};
static char g_rootfs_path[4096] = {0};
static char *g_mount_table = NULL;

typedef struct QemuRunnerMount {
    char guest_path[4096];
    char host_path[4096];
} QemuRunnerMount;

static QemuRunnerMount *g_mounts = NULL;
static size_t g_mount_count = 0;
static size_t g_mount_capacity = 0;

#define QEMU_MAX_COMMAND_CONTEXTS 8
#define QEMU_MAX_SESSION_CONTEXTS 8
#define QEMU_SESSION_OUTPUT_CAPACITY 65536
#define QEMU_SESSION_INPUT_CAPACITY 65536

typedef struct QemuExecCaptureContext {
    char *stdout_buf;
    size_t stdout_size;
    size_t stdout_offset;
    char *stderr_buf;
    size_t stderr_size;
    size_t stderr_offset;
    int stats_enabled;
    size_t stats_callbacks;
    size_t stats_segments;
    size_t stats_bytes;
    size_t stats_min_size;
    size_t stats_max_size;
    size_t stats_le_64;
    size_t stats_le_256;
    size_t stats_le_1024;
} QemuExecCaptureContext;

typedef struct QemuSessionContext {
    unsigned long long id;
    int active;
    int closed;
    volatile int cancel_requested;
    int cols;
    int rows;
    pthread_t thread;
    int thread_started;
    int thread_exited;
    IOSQemuTTY *tty;
    /*
     * 正在无锁使用 session->tty 的调用数(close/write/resize 在 session->mutex
     * 下取快照并 ++,放锁后才调 tty 函数,用完 --并广播 input_cond)。session
     * 线程 teardown 先清 session->tty(掐断新快照)再等它归零才 destroy tty。
     * 这替代两种旧写法:持 session->mutex 调 tty 函数会形成
     * session->mutex→tty->mutex,与 terminal write 回调(tty->mutex→
     * session->mutex)构成 ABBA 死锁环;裸快照放锁后使用则与 teardown 的
     * destroy 竞态(free-on-last-ref 下 tty 可能被释放)。
     */
    int tty_busy;
    pthread_mutex_t mutex;
    pthread_cond_t input_cond;
    pthread_cond_t output_cond;
    char input[QEMU_SESSION_INPUT_CAPACITY];
    size_t input_len;
    char output[QEMU_SESSION_OUTPUT_CAPACITY];
    size_t output_len;
    uint64_t latency_seq;
    uint64_t latency_input_ns;
    int latency_read_reported;
    int latency_output_reported;
    int latency_host_read_reported;
    int latency_watchdog_running;
} QemuSessionContext;

typedef struct QemuCommandContext {
    unsigned long long id;
    int active;
    int has_command_id;
    volatile int cancelled;
} QemuCommandContext;

static QemuCommandContext g_commands[QEMU_MAX_COMMAND_CONTEXTS];
static pthread_mutex_t g_commands_mutex = PTHREAD_MUTEX_INITIALIZER;
/*
 * 每个槽位的 mutex/cond 静态初始化,进程生命周期内终身有效:永不 destroy、
 * 不重 init、不被 memset。槽位回收(active=0)后仍可能有迟到的使用者短暂
 * 上锁——guest 侧发起的 terminal set_size 回调在 tty 层锁外执行,极窄窗口
 * 下可跨过整个 teardown 才落锁;对已 destroy/未初始化的 mutex 上锁是 UB
 * (真机 EXC_BAD_ACCESS 的一类来源)。用静态初始化而非惰性 init,语言层面
 * 消灭"首次触碰必须先经过 allocate"的隐式时序依赖(诊断/单测路径也安全)。
 */
static QemuSessionContext g_sessions[QEMU_MAX_SESSION_CONTEXTS] = {
    [0 ... QEMU_MAX_SESSION_CONTEXTS - 1] = {
        .mutex = PTHREAD_MUTEX_INITIALIZER,
        .input_cond = PTHREAD_COND_INITIALIZER,
        .output_cond = PTHREAD_COND_INITIALIZER,
    },
};
static pthread_mutex_t g_sessions_mutex = PTHREAD_MUTEX_INITIALIZER;

void qemu_runner_set_paths(const char *qemu_path, const char *rootfs_path) {
    snprintf(g_qemu_path, sizeof(g_qemu_path), "%s", qemu_path != NULL ? qemu_path : "");
    snprintf(g_rootfs_path, sizeof(g_rootfs_path), "%s", rootfs_path != NULL ? rootfs_path : "");
}

static int qemu_runner_hex_value(char ch)
{
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    return -1;
}

static int qemu_runner_percent_decode_field(const char *start, size_t len, char *out, size_t out_size)
{
    size_t out_len = 0;

    if (out == NULL || out_size == 0) {
        return -1;
    }

    for (size_t index = 0; index < len; index++) {
        char ch = start[index];

        if (out_len + 1 >= out_size) {
            return -1;
        }
        if (ch == '%' && index + 2 < len) {
            int hi = qemu_runner_hex_value(start[index + 1]);
            int lo = qemu_runner_hex_value(start[index + 2]);

            if (hi < 0 || lo < 0) {
                return -1;
            }
            out[out_len++] = (char)((hi << 4) | lo);
            index += 2;
        } else {
            out[out_len++] = ch;
        }
    }
    out[out_len] = '\0';
    return 0;
}

static void qemu_runner_clear_mounts(void)
{
    free(g_mount_table);
    g_mount_table = NULL;
    free(g_mounts);
    g_mounts = NULL;
    g_mount_count = 0;
    g_mount_capacity = 0;
}

static int qemu_runner_reserve_mount(void)
{
    QemuRunnerMount *new_mounts;
    size_t new_capacity = g_mount_capacity == 0 ? 8 : g_mount_capacity * 2;

    if (g_mount_count < g_mount_capacity) {
        return 0;
    }

    new_mounts = realloc(g_mounts, new_capacity * sizeof(*g_mounts));
    if (new_mounts == NULL) {
        return -1;
    }
    memset(new_mounts + g_mount_capacity, 0,
           (new_capacity - g_mount_capacity) * sizeof(*new_mounts));
    g_mounts = new_mounts;
    g_mount_capacity = new_capacity;
    return 0;
}

int qemu_runner_set_mount_table(const char *mount_table) {
    const char *record;

    qemu_runner_clear_mounts();
    if (mount_table == NULL || mount_table[0] == '\0') {
        return 0;
    }

    g_mount_table = strdup(mount_table);
    if (g_mount_table == NULL) {
        return -1;
    }

    record = g_mount_table;
    while (*record != '\0') {
        const char *record_end = strchr(record, ';');
        const char *separator;
        size_t record_len;
        size_t guest_len;
        size_t host_len;

        if (record_end == NULL) {
            record_end = record + strlen(record);
        }
        record_len = (size_t)(record_end - record);
        separator = memchr(record, '=', record_len);
        if (separator == NULL) {
            qemu_runner_clear_mounts();
            return -1;
        }
        guest_len = (size_t)(separator - record);
        host_len = record_len - guest_len - 1;

        if (qemu_runner_reserve_mount() != 0) {
            qemu_runner_clear_mounts();
            return -1;
        }

        if (qemu_runner_percent_decode_field(record, guest_len,
                                             g_mounts[g_mount_count].guest_path,
                                             sizeof(g_mounts[g_mount_count].guest_path)) != 0 ||
            qemu_runner_percent_decode_field(separator + 1, host_len,
                                             g_mounts[g_mount_count].host_path,
                                             sizeof(g_mounts[g_mount_count].host_path)) != 0 ||
            g_mounts[g_mount_count].guest_path[0] != '/' ||
            g_mounts[g_mount_count].host_path[0] != '/') {
            qemu_runner_clear_mounts();
            return -1;
        }

        g_mount_count++;
        record = *record_end == ';' ? record_end + 1 : record_end;
    }
    return 0;
}

static void write_buffer(char *buffer, size_t buffer_size, const char *message) {
    if (buffer == NULL || buffer_size == 0) {
        return;
    }
    snprintf(buffer, buffer_size, "%s", message != NULL ? message : "");
}

static void append_buffer(char *buffer, size_t buffer_size, size_t *offset, const char *data, ssize_t data_size) {
    if (buffer == NULL || buffer_size == 0 || data == NULL || data_size <= 0 || *offset >= buffer_size - 1) {
        return;
    }
    size_t available = buffer_size - 1 - *offset;
    size_t copied = (size_t)data_size < available ? (size_t)data_size : available;
    memcpy(buffer + *offset, data, copied);
    *offset += copied;
    buffer[*offset] = '\0';
}

static int qemu_exec_capture_target(QemuExecCaptureContext *context, int fd,
                                    char **target_buf, size_t *target_size,
                                    size_t **target_offset)
{
    if (context == NULL || target_buf == NULL || target_size == NULL ||
        target_offset == NULL) {
        return -1;
    }
    if (fd == STDOUT_FILENO) {
        *target_buf = context->stdout_buf;
        *target_size = context->stdout_size;
        *target_offset = &context->stdout_offset;
        return 0;
    }
    if (fd == STDERR_FILENO) {
        *target_buf = context->stderr_buf;
        *target_size = context->stderr_size;
        *target_offset = &context->stderr_offset;
        return 0;
    }
    return -1;
}

static void qemu_exec_capture_record_segment(QemuExecCaptureContext *context,
                                             size_t size)
{
    if (!context->stats_enabled) {
        return;
    }
    context->stats_segments++;
    context->stats_bytes += size;
    if (context->stats_min_size == 0 || size < context->stats_min_size) {
        context->stats_min_size = size;
    }
    if (size > context->stats_max_size) {
        context->stats_max_size = size;
    }
    if (size <= 64) context->stats_le_64++;
    if (size <= 256) context->stats_le_256++;
    if (size <= 1024) context->stats_le_1024++;
}

static ssize_t qemu_exec_capture_write(void *opaque, int fd, const void *buf, size_t size) {
    QemuExecCaptureContext *context = (QemuExecCaptureContext *)opaque;
    char *target_buf = NULL;
    size_t target_size = 0;
    size_t *target_offset = NULL;

    if (buf == NULL ||
        qemu_exec_capture_target(context, fd, &target_buf, &target_size,
                                 &target_offset) != 0) {
        return -1;
    }

    /* 所有 callback 都在 writer_box->lock 下执行；同一捕获上下文只挂一个
     * box，因此这里无需第二把 mutex。buffer 满后 append_buffer 直接返回，
     * guest 仍观察到完整写入长度。 */
    if (context->stats_enabled) {
        context->stats_callbacks++;
    }
    qemu_exec_capture_record_segment(context, size);
    append_buffer(target_buf, target_size, target_offset, (const char *)buf, (ssize_t)size);
    return (ssize_t)size;
}

static ssize_t qemu_exec_capture_writev(void *opaque, int fd,
                                        const struct iovec *iov, int iovcnt)
{
    QemuExecCaptureContext *context = (QemuExecCaptureContext *)opaque;
    char *target_buf = NULL;
    size_t target_size = 0;
    size_t *target_offset = NULL;
    size_t total = 0;

    if (iovcnt < 0 || (iovcnt != 0 && iov == NULL) ||
        qemu_exec_capture_target(context, fd, &target_buf, &target_size,
                                 &target_offset) != 0) {
        return -1;
    }
    if (context->stats_enabled) {
        context->stats_callbacks++;
    }
    for (int i = 0; i < iovcnt; i++) {
        size_t size = iov[i].iov_len;

        if (size == 0) {
            continue;
        }
        if (iov[i].iov_base == NULL || size > (size_t)SSIZE_MAX - total) {
            return -1;
        }
        qemu_exec_capture_record_segment(context, size);
        append_buffer(target_buf, target_size, target_offset,
                      (const char *)iov[i].iov_base, (ssize_t)size);
        total += size;
    }
    return (ssize_t)total;
}

static int append_json_char(char **cursor, size_t *remaining, char value) {
    if (*remaining <= 1) {
        return -1;
    }
    **cursor = value;
    (*cursor)++;
    (*remaining)--;
    **cursor = '\0';
    return 0;
}

static int parse_json_string_array(const char *json, char **items, int max_items) {
    if (json == NULL || json[0] == '\0') {
        return 0;
    }

    const char *cursor = json;
    while (*cursor == ' ' || *cursor == '\n' || *cursor == '\r' || *cursor == '\t') {
        cursor++;
    }
    if (*cursor != '[') {
        return -1;
    }
    cursor++;

    int count = 0;
    while (*cursor != '\0') {
        while (*cursor == ' ' || *cursor == '\n' || *cursor == '\r' || *cursor == '\t' || *cursor == ',') {
            cursor++;
        }
        if (*cursor == ']') {
            return count;
        }
        if (*cursor != '"' || count >= max_items) {
            return -1;
        }
        cursor++;

        char *value = calloc(1, strlen(cursor) + 1);
        if (value == NULL) {
            return -1;
        }
        char *out = value;
        size_t remaining = strlen(cursor) + 1;
        while (*cursor != '\0' && *cursor != '"') {
            if (*cursor == '\\') {
                cursor++;
                switch (*cursor) {
                case '"':
                case '\\':
                case '/':
                    if (append_json_char(&out, &remaining, *cursor) != 0) {
                        free(value);
                        return -1;
                    }
                    break;
                case 'n':
                    if (append_json_char(&out, &remaining, '\n') != 0) {
                        free(value);
                        return -1;
                    }
                    break;
                case 'r':
                    if (append_json_char(&out, &remaining, '\r') != 0) {
                        free(value);
                        return -1;
                    }
                    break;
                case 't':
                    if (append_json_char(&out, &remaining, '\t') != 0) {
                        free(value);
                        return -1;
                    }
                    break;
                default:
                    free(value);
                    return -1;
                }
                cursor++;
                continue;
            }
            if (append_json_char(&out, &remaining, *cursor) != 0) {
                free(value);
                return -1;
            }
            cursor++;
        }
        if (*cursor != '"') {
            free(value);
            return -1;
        }
        cursor++;
        items[count++] = value;
    }
    return -1;
}

static char *parse_json_string_value(const char **cursor) {
    if (**cursor != '"') {
        return NULL;
    }
    (*cursor)++;

    char *value = calloc(1, strlen(*cursor) + 1);
    if (value == NULL) {
        return NULL;
    }
    char *out = value;
    size_t remaining = strlen(*cursor) + 1;
    while (**cursor != '\0' && **cursor != '"') {
        if (**cursor == '\\') {
            (*cursor)++;
            switch (**cursor) {
            case '"':
            case '\\':
            case '/':
                if (append_json_char(&out, &remaining, **cursor) != 0) {
                    free(value);
                    return NULL;
                }
                break;
            case 'n':
                if (append_json_char(&out, &remaining, '\n') != 0) {
                    free(value);
                    return NULL;
                }
                break;
            case 'r':
                if (append_json_char(&out, &remaining, '\r') != 0) {
                    free(value);
                    return NULL;
                }
                break;
            case 't':
                if (append_json_char(&out, &remaining, '\t') != 0) {
                    free(value);
                    return NULL;
                }
                break;
            default:
                free(value);
                return NULL;
            }
            (*cursor)++;
            continue;
        }
        if (append_json_char(&out, &remaining, **cursor) != 0) {
            free(value);
            return NULL;
        }
        (*cursor)++;
    }
    if (**cursor != '"') {
        free(value);
        return NULL;
    }
    (*cursor)++;
    return value;
}

static void skip_json_space(const char **cursor) {
    while (**cursor == ' ' || **cursor == '\n' || **cursor == '\r' || **cursor == '\t') {
        (*cursor)++;
    }
}

static int parse_json_env_object(const char *json, char **items, int max_items) {
    if (json == NULL || json[0] == '\0') {
        return 0;
    }

    const char *cursor = json;
    skip_json_space(&cursor);
    if (*cursor != '{') {
        return -1;
    }
    cursor++;

    int count = 0;
    while (*cursor != '\0') {
        skip_json_space(&cursor);
        if (*cursor == '}') {
            return count;
        }
        if (count >= max_items) {
            return -1;
        }

        char *key = parse_json_string_value(&cursor);
        if (key == NULL) {
            return -1;
        }
        skip_json_space(&cursor);
        if (*cursor != ':') {
            free(key);
            return -1;
        }
        cursor++;
        skip_json_space(&cursor);

        char *value = parse_json_string_value(&cursor);
        if (value == NULL) {
            free(key);
            return -1;
        }

        size_t item_len = strlen(key) + strlen(value) + 2;
        char *item = calloc(1, item_len);
        if (item == NULL) {
            free(key);
            free(value);
            return -1;
        }
        snprintf(item, item_len, "%s=%s", key, value);
        items[count++] = item;
        free(key);
        free(value);

        skip_json_space(&cursor);
        if (*cursor == ',') {
            cursor++;
            continue;
        }
        if (*cursor == '}') {
            return count;
        }
        return -1;
    }
    return -1;
}

static void free_string_array(char **items, int count) {
    for (int index = 0; index < count; index++) {
        free(items[index]);
    }
}

static bool env_items_contain_key(char **items, int count, const char *key)
{
    size_t key_len;

    if (items == NULL || key == NULL) {
        return false;
    }
    key_len = strlen(key);
    for (int index = 0; index < count; index++) {
        if (items[index] != NULL
            && strncmp(items[index], key, key_len) == 0
            && items[index][key_len] == '=') {
            return true;
        }
    }
    return false;
}

static int append_env_item(char **items, int *count, int max_items, const char *key, const char *value)
{
    size_t item_len;
    char *item;

    if (items == NULL || count == NULL || key == NULL || value == NULL) {
        return -1;
    }
    if (env_items_contain_key(items, *count, key)) {
        return 0;
    }
    if (*count >= max_items) {
        return -1;
    }

    item_len = strlen(key) + strlen(value) + 2;
    item = calloc(1, item_len);
    if (item == NULL) {
        return -1;
    }
    snprintf(item, item_len, "%s=%s", key, value);
    items[*count] = item;
    (*count)++;
    return 0;
}

static int append_default_session_shell_env(char **items, int *count, int max_items)
{
    /* guest 恒以 root 身份运行。默认 session 是 `/bin/sh -il`(login+interactive,
     * 三平台统一由 common.rs::default_session_command 产出),会 source /etc/profile,
     * 但 Alpine 自带 /etc/profile 从不设 HOME/USER/LOGNAME/SHELL,仍需 runner 兜底;
     * 一次性 exec 不走 login shell,不 source profile,更需要这些默认值。
     * "缺则补"由 append_env_item 保证,caller 通过 env_json 传入的值优先。 */
    if (append_env_item(items, count, max_items, "TERM", "xterm-256color") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "HOSTNAME", "ios-qemu") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "PS1", "\\h:\\w\\$ ") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "HOME", "/root") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "PATH",
                         "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "USER", "root") != 0) {
        return -1;
    }
    if (append_env_item(items, count, max_items, "LOGNAME", "root") != 0) {
        return -1;
    }
    return append_env_item(items, count, max_items, "SHELL", "/bin/sh");
}

static int append_guest_cwd_env(char **items, int *count, int max_items, const char *working_dir)
{
    const char *key = "QEMU_GUEST_CWD=";
    size_t item_len;
    char *item;

    if (working_dir == NULL || working_dir[0] == '\0') {
        return 0;
    }
    if (count == NULL || *count >= max_items) {
        return -1;
    }

    item_len = strlen(key) + strlen(working_dir) + 1;
    item = calloc(1, item_len);
    if (item == NULL) {
        return -1;
    }
    snprintf(item, item_len, "%s%s", key, working_dir);
    items[*count] = item;
    (*count)++;

    /* PWD 是 POSIX 标准名,供读 $PWD 的程序用;QEMU_GUEST_CWD 是内部实现细节。 */
    return append_env_item(items, count, max_items, "PWD", working_dir);
}

static size_t path_len_without_trailing_slash(const char *path)
{
    size_t len = path != NULL ? strlen(path) : 0;

    while (len > 1 && path[len - 1] == '/') {
        len--;
    }
    return len;
}

static int map_guest_path_to_host(
    const char *guest_path,
    char *host_path,
    size_t host_path_size
) {
    int written;
    int best_mount = -1;
    size_t best_len = 0;

    if (guest_path == NULL || guest_path[0] != '/' || host_path == NULL || host_path_size == 0) {
        return -1;
    }

    for (size_t index = 0; index < g_mount_count; index++) {
        size_t len = path_len_without_trailing_slash(g_mounts[index].guest_path);

        if ((strlen(guest_path) == len && strncmp(guest_path, g_mounts[index].guest_path, len) == 0) ||
            (strncmp(guest_path, g_mounts[index].guest_path, len) == 0 && guest_path[len] == '/')) {
            if (len > best_len) {
                best_mount = (int)index;
                best_len = len;
            }
        }
    }

    if (best_mount >= 0) {
        size_t host_len = path_len_without_trailing_slash(g_mounts[best_mount].host_path);
        if (strlen(guest_path) == best_len) {
            written = snprintf(host_path, host_path_size, "%.*s",
                               (int)host_len, g_mounts[best_mount].host_path);
        } else {
            written = snprintf(
                host_path,
                host_path_size,
                "%.*s/%s",
                (int)host_len,
                g_mounts[best_mount].host_path,
                guest_path + best_len + 1
            );
        }
    } else {
        if (g_rootfs_path[0] == '\0') {
            return -1;
        }
        size_t rootfs_len = path_len_without_trailing_slash(g_rootfs_path);
        written = snprintf(
            host_path,
            host_path_size,
            "%.*s%s",
            (int)rootfs_len,
            g_rootfs_path,
            guest_path
        );
    }

    return written >= 0 && (size_t)written < host_path_size ? 0 : -1;
}

static int validate_guest_working_dir(const char *working_dir)
{
    char host_path[4096];
    struct stat st;

    if (map_guest_path_to_host(working_dir, host_path, sizeof(host_path)) != 0) {
        return -1;
    }
    if (stat(host_path, &st) != 0) {
        return -1;
    }
    return S_ISDIR(st.st_mode) ? 0 : -1;
}

int qemu_runner_validate_guest_working_dir(const char *working_dir)
{
    return validate_guest_working_dir(working_dir);
}

static int append_mount_table_env(char **items, int *count, int max_items)
{
    const char *key = "QEMU_MOUNT_TABLE=";
    size_t item_len;
    char *item;

    if (g_mount_table == NULL || g_mount_table[0] == '\0') {
        return 0;
    }
    if (count == NULL || *count >= max_items) {
        return -1;
    }

    item_len = strlen(key) + strlen(g_mount_table) + 1;
    item = calloc(1, item_len);
    if (item == NULL) {
        return -1;
    }
    snprintf(item, item_len, "%s%s", key, g_mount_table);
    items[*count] = item;
    (*count)++;
    return 0;
}

static void free_null_terminated_string_array(char **items)
{
    if (items == NULL) {
        return;
    }
    for (int index = 0; items[index] != NULL; index++) {
        free(items[index]);
    }
    free(items);
}

typedef struct QemuArgv {
    char **items;
    int count;
} QemuArgv;

typedef struct QemuSessionThreadContext {
    QemuSessionContext *session;
    QemuArgv argv;
    char **envp;
    char **owned_guest_argv;
    char *guest_argv0;
} QemuSessionThreadContext;

static void free_qemu_argv(QemuArgv *argv)
{
    free(argv->items);
    argv->items = NULL;
    argv->count = 0;
}

static int count_null_terminated_string_array(char **items)
{
    int count = 0;
    if (items == NULL) {
        return 0;
    }
    while (items[count] != NULL) {
        count++;
    }
    return count;
}


static int copy_argv_vector(char **src, QemuArgv *out)
{
    int count;
    char **items;

    if (src == NULL || src[0] == NULL || out == NULL) {
        return -1;
    }

    count = count_null_terminated_string_array(src);
    items = calloc((size_t)count + 1, sizeof(char *));
    if (items == NULL) {
        return -1;
    }
    for (int index = 0; index < count; index++) {
        items[index] = src[index];
    }
    items[count] = NULL;
    out->items = items;
    out->count = count;
    return 0;
}

static int build_qemu_argv(
    const char *qemu_path,
    const char *rootfs_path,
    char **guest_program_argv,
    const char *guest_argv0,
    QemuArgv *out
) {
    int guest_count;
    int capacity;
    int argc = 0;
    char **items;
    const char *launcher_path;

    if (guest_program_argv == NULL || guest_program_argv[0] == NULL || out == NULL) {
        return -1;
    }

    guest_count = count_null_terminated_string_array(guest_program_argv);
    capacity = guest_count + 6;
    items = calloc((size_t)capacity, sizeof(char *));
    if (items == NULL) {
        return -1;
    }

    launcher_path = (qemu_path != NULL && qemu_path[0] != '\0') ? qemu_path : "qemu-aarch64";
    items[argc++] = (char *)launcher_path;
    if (rootfs_path != NULL && rootfs_path[0] != '\0') {
        items[argc++] = "-L";
        items[argc++] = (char *)rootfs_path;
    }
    if (guest_argv0 != NULL && guest_argv0[0] != '\0') {
        items[argc++] = "-0";
        items[argc++] = (char *)guest_argv0;
    }
    for (int index = 0; index < guest_count; index++) {
        items[argc++] = guest_program_argv[index];
    }
    items[argc] = NULL;
    out->items = items;
    out->count = argc;
    return 0;
}

static int build_restart_qemu_argv(
    const char *qemu_path,
    const char *rootfs_path,
    char **captured_argv,
    bool captured_is_qemu_wrapped,
    QemuArgv *out
) {
    /*
     * captured_is_qemu_wrapped 由 exec 生产方(do_execv_darwin)经
     * ios_qemu_exec_request_was_wrapped() 显式声明,不再靠 argv[0] 是否以
     * "qemu-" 开头猜测:当 qemu_path 命名任意(测试 harness 传 busybox 路径)
     * 时,已包装 argv 会被误判成未包装而再包一层,guest 收到 argv[0]="-L"。
     */
    if (captured_is_qemu_wrapped) {
        return copy_argv_vector(captured_argv, out);
    }
    return build_qemu_argv(qemu_path, rootfs_path, captured_argv, NULL, out);
}

static int build_session_shell_qemu_argv(QemuSessionThreadContext *context, QemuArgv *out)
{
    if (context == NULL || context->owned_guest_argv == NULL) {
        return -1;
    }
    return build_qemu_argv(g_qemu_path, g_rootfs_path, context->owned_guest_argv, context->guest_argv0, out);
}

static bool qemu_fd_atomic_ref_enabled(void)
{
    const char *value = getenv("IOS_QEMU_FD_ATOMIC_REF");

    return value == NULL || value[0] == '\0' || strcmp(value, "0") != 0;
}

static bool qemu_syscall_stats_enabled(void)
{
    const char *value = getenv("IOS_QEMU_SYSCALL_STATS");

    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool qemu_fd_capture_stats_enabled(void)
{
    const char *value = getenv("IOS_QEMU_FD_CAPTURE_STATS");

    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool qemu_fd_sparse_scan_stats_enabled(void)
{
    const char *value = getenv("IOS_QEMU_FD_SPARSE_STATS");

    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool qemu_process_perf_stats_enabled(void)
{
    const char *value = getenv("IOS_QEMU_PROCESS_PERF_STATS");

    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool qemu_fd_capture_fast_enabled(void)
{
    const char *value = getenv("IOS_QEMU_FD_CAPTURE_FAST");

    /* 正确性门禁和 A/B 完成后默认开启；显式 0 保留完整旧路径。配置在每次
     * writer 创建时固化到 box，热写路径不逐次读取环境变量。 */
    return value == NULL || value[0] == '\0' || strcmp(value, "0") != 0;
}

static bool qemu_fd_capture_writev_enabled(void)
{
    const char *value = getenv("IOS_QEMU_FD_CAPTURE_WRITEV");

    /* 实验阶段默认保持逐段 callback；真机 A/B 证明收益且无回归后再切默认。 */
    return value != NULL && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool trace_qemu_session(void)
{
    const char *trace = getenv("IOS_QEMU_TRACE_SESSION");
    return trace != NULL && trace[0] != '\0' && strcmp(trace, "0") != 0;
}

static bool trace_qemu_latency(void)
{
    const char *trace = getenv("IOS_QEMU_TRACE_LATENCY");
    return trace != NULL && trace[0] != '\0' && strcmp(trace, "0") != 0;
}

static uint64_t qemu_monotonic_ns(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static double qemu_latency_ms(uint64_t start_ns, uint64_t now_ns)
{
    return start_ns != 0 && now_ns >= start_ns
        ? (double)(now_ns - start_ns) / 1000000.0
        : -1.0;
}

typedef struct QemuLatencyWatchdog {
    QemuSessionContext *session;
    unsigned long long session_id;
} QemuLatencyWatchdog;

/*
 * 一个 session 同时只保留一个 watchdog。连续输入会更新 latency_seq；现有
 * watchdog 看到序号变化后从 250ms 重新计时，避免“每个字符一个 pthread”
 * 反过来制造调度压力并污染延迟测试。
 */
static bool qemu_latency_watchdog_check(
    QemuLatencyWatchdog *watchdog,
    uint64_t expected_seq,
    bool finish,
    uint64_t *current_seq
)
{
    bool pending = false;
    QemuSessionContext *session = watchdog->session;

    pthread_mutex_lock(&session->mutex);
    if (session->active
        && session->id == watchdog->session_id
        && !session->closed
        && session->latency_seq != 0
        && !session->latency_read_reported) {
        *current_seq = session->latency_seq;
        pending = expected_seq == 0 || session->latency_seq == expected_seq;
    }
    if (finish || (!pending && (session->closed || !session->active
                               || session->id != watchdog->session_id
                               || session->latency_read_reported))) {
        session->latency_watchdog_running = 0;
    }
    pthread_mutex_unlock(&session->mutex);
    return pending;
}

static void *qemu_latency_watchdog_main(void *opaque)
{
    QemuLatencyWatchdog *watchdog = (QemuLatencyWatchdog *)opaque;
    const long waits_ms[] = { 250, 750, 4000 };
    const long elapsed_ms[] = { 250, 1000, 5000 };
    uint64_t watched_seq = 0;

restart:
    if (!qemu_latency_watchdog_check(watchdog, 0, false, &watched_seq)) {
        free(watchdog);
        return NULL;
    }
    for (size_t i = 0; i < sizeof(waits_ms) / sizeof(waits_ms[0]); i++) {
        struct timespec wait = {
            .tv_sec = waits_ms[i] / 1000,
            .tv_nsec = (waits_ms[i] % 1000) * 1000000L,
        };
        uint64_t current_seq = 0;
        char reason[96];

        while (nanosleep(&wait, &wait) != 0 && errno == EINTR) {
        }
        if (!qemu_latency_watchdog_check(watchdog, watched_seq, false,
                                         &current_seq)) {
            if (current_seq != 0 && current_seq != watched_seq) {
                goto restart;
            }
            free(watchdog);
            return NULL;
        }
        snprintf(reason, sizeof(reason),
                 "session=%llu,seq=%llu,unread=%ldms",
                 watchdog->session_id,
                 (unsigned long long)watched_seq, elapsed_ms[i]);
        ios_qemu_debug_dump_host_threads(reason);
    }

    /* 5 秒样本已经足够定位；结束与“是否已有新输入”必须在同一锁区判断，
     * 否则新 input 可能看到 running=1 而不启动，随后被旧 watcher 清零漏监。 */
    pthread_mutex_lock(&watchdog->session->mutex);
    if (watchdog->session->active
        && watchdog->session->id == watchdog->session_id
        && !watchdog->session->closed
        && !watchdog->session->latency_read_reported
        && watchdog->session->latency_seq != watched_seq) {
        pthread_mutex_unlock(&watchdog->session->mutex);
        goto restart;
    }
    watchdog->session->latency_watchdog_running = 0;
    pthread_mutex_unlock(&watchdog->session->mutex);
    free(watchdog);
    return NULL;
}

static void qemu_latency_watchdog_start(
    QemuSessionContext *session,
    unsigned long long session_id,
    uint64_t seq
)
{
    QemuLatencyWatchdog *watchdog;
    pthread_attr_t attr;
    pthread_t thread;
    bool should_start = false;

    if (!trace_qemu_latency() || session == NULL || seq == 0) {
        return;
    }
    pthread_mutex_lock(&session->mutex);
    if (session->active && session->id == session_id && !session->closed
        && session->latency_seq == seq && !session->latency_watchdog_running) {
        session->latency_watchdog_running = 1;
        should_start = true;
    }
    pthread_mutex_unlock(&session->mutex);
    if (!should_start) {
        return;
    }

    watchdog = calloc(1, sizeof(*watchdog));
    if (watchdog == NULL) {
        goto fail;
    }
    watchdog->session = session;
    watchdog->session_id = session_id;
    if (pthread_attr_init(&attr) != 0) {
        free(watchdog);
        goto fail;
    }
    (void)pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&thread, &attr, qemu_latency_watchdog_main, watchdog) != 0) {
        free(watchdog);
        pthread_attr_destroy(&attr);
        goto fail;
    }
    pthread_attr_destroy(&attr);
    return;

fail:
    pthread_mutex_lock(&session->mutex);
    if (session->id == session_id) {
        session->latency_watchdog_running = 0;
    }
    pthread_mutex_unlock(&session->mutex);
}

static void trace_qemu_session_bytes(const char *label, const void *buf, size_t size)
{
    const unsigned char *bytes = (const unsigned char *)buf;
    size_t limit = size < 96 ? size : 96;

    if (!trace_qemu_session()) {
        return;
    }
    /*
     * Suppress the per-character I/O spam (terminal echo and single-byte tty
     * reads/writes) so the useful session/[mmu] traces stay readable.
     */
    if (strcmp(label, "terminal_write") == 0) {
        return;
    }
    if (strcmp(label, "tty_write") == 0) {
        return;
    }
    if (strcmp(label, "tty_read") == 0) {
        return;
    }
    fprintf(stderr, "[qemu-session] %s len=%zu data=\"", label, size);
    for (size_t index = 0; index < limit; index++) {
        unsigned char ch = bytes[index];
        if (ch == '\r') {
            fprintf(stderr, "\\r");
        } else if (ch == '\n') {
            fprintf(stderr, "\\n");
        } else if (ch == '\t') {
            fprintf(stderr, "\\t");
        } else if (ch >= 32 && ch < 127) {
            fputc(ch, stderr);
        } else {
            fprintf(stderr, "\\x%02x", ch);
        }
    }
    if (limit < size) {
        fprintf(stderr, "...");
    }
    fprintf(stderr, "\"\n");
}

static void trace_qemu_session_env(char **envp)
{
    const char *keys[] = {"TERM", "PS1", "ENV", "BB_ASH_VERSION", "HOSTNAME", NULL};

    if (!trace_qemu_session()) {
        return;
    }
    for (int key_index = 0; keys[key_index] != NULL; key_index++) {
        const char *key = keys[key_index];
        size_t key_len = strlen(key);
        const char *value = "(unset)";

        if (envp != NULL) {
            for (int env_index = 0; envp[env_index] != NULL; env_index++) {
                if (strncmp(envp[env_index], key, key_len) == 0
                    && envp[env_index][key_len] == '=') {
                    value = envp[env_index] + key_len + 1;
                    break;
                }
            }
        }
        fprintf(stderr, "[qemu-session] env %s=%s\n", key, value);
    }
}

int qemu_runner_init_runtime(const char *qemu_path, const char *rootfs_path)
{
    return ios_qemu_runtime_init_once(qemu_path, rootfs_path);
}

static QemuSessionContext *find_session_locked(unsigned long long session_id) {
    for (int index = 0; index < QEMU_MAX_SESSION_CONTEXTS; index++) {
        if (g_sessions[index].active && g_sessions[index].id == session_id) {
            return &g_sessions[index];
        }
    }
    return NULL;
}

static QemuSessionContext *allocate_session_locked(unsigned long long session_id) {
    if (find_session_locked(session_id) != NULL) {
        return NULL;
    }
    for (int index = 0; index < QEMU_MAX_SESSION_CONTEXTS; index++) {
        if (!g_sessions[index].active) {
            QemuSessionContext *session = &g_sessions[index];

            /*
             * 字段重置持 session->mutex:槽位 mutex 终身有效的设计前提就是
             * 迟到者(stale 指针/回调)仍可能持锁访问已回收槽位,无锁重置与
             * 之构成数据竞争(input_len/output_len 与缓冲内容撕裂)。只重置
             * 数据字段,mutex/cond 保持静态初始化原样。锁序:g_sessions_mutex
             * → session->mutex,任何持 session->mutex 的路径都不取
             * g_sessions_mutex(session_read 的回收路径先放 session 锁)。
             * id 也在此锁下写,session_find_and_lock 的身份复核由此一致。
             */
            pthread_mutex_lock(&session->mutex);
            session->id = session_id;
            session->closed = 0;
            session->cancel_requested = 0;
            session->cols = 0;
            session->rows = 0;
            memset(&session->thread, 0, sizeof(session->thread));
            session->thread_started = 0;
            session->thread_exited = 0;
            session->tty = NULL;
            session->tty_busy = 0;
            session->input_len = 0;
            session->output_len = 0;
            session->latency_seq = 0;
            session->latency_input_ns = 0;
            session->latency_read_reported = 0;
            session->latency_output_reported = 0;
            session->latency_host_read_reported = 0;
            session->latency_watchdog_running = 0;
            pthread_mutex_unlock(&session->mutex);
            session->active = 1;
            return session;
        }
    }
    return NULL;
}

static QemuSessionContext *find_session(unsigned long long session_id) {
    pthread_mutex_lock(&g_sessions_mutex);
    QemuSessionContext *session = find_session_locked(session_id);
    pthread_mutex_unlock(&g_sessions_mutex);
    return session;
}

/*
 * 查槽位并在 session->mutex 下复核身份。find_session 返回的裸指针与槽位
 * 回收(read 返 -4 置 active=0)/复用(allocate 换 id)之间存在窗口:不复核
 * 的话 close/write 会作用到复用后的新 session(跨 session 关会话/注入输
 * 入)。id 的写入在 allocate 里同样持 session->mutex,锁下读一致;槽位仅
 * 回收未复用时 id 不变,stale 操作落在已死槽位上(tty 已 NULL、closed 已
 * 置),各入口自然短路。返回时持有 session->mutex;不符返回 NULL(不持锁)。
 */
static QemuSessionContext *session_find_and_lock(unsigned long long session_id) {
    QemuSessionContext *session = find_session(session_id);

    if (session == NULL) {
        return NULL;
    }
    pthread_mutex_lock(&session->mutex);
    if (session->id != session_id) {
        pthread_mutex_unlock(&session->mutex);
        return NULL;
    }
    return session;
}

/* 调用方持 session->mutex:取 tty 快照并 tty_busy++(与 session_tty_release
 * 配对),busy 归零前 session 线程的 teardown 不会 destroy 该 tty。所有取
 * tty 的入口统一走这里,不许各自手写快照/计数变体。无 tty 返回 NULL 且不
 * 计数。 */
static IOSQemuTTY *session_tty_acquire_locked(QemuSessionContext *session) {
    IOSQemuTTY *tty = session->tty;

    if (tty != NULL) {
        session->tty_busy++;
    }
    return tty;
}

/* 归还 session_tty_acquire_locked 的快照。 */
static void session_tty_release(QemuSessionContext *session) {
    pthread_mutex_lock(&session->mutex);
    session->tty_busy--;
    /* 只有 teardown 已摘除 session->tty 并可能在等静默时才需要唤醒;tty 还
     * 挂着说明没人等 busy,省掉高频 write 路径上的无谓 broadcast。 */
    if (session->tty_busy == 0 && session->tty == NULL) {
        pthread_cond_broadcast(&session->input_cond);
    }
    pthread_mutex_unlock(&session->mutex);
}

static QemuCommandContext *find_command_by_id_locked(unsigned long long command_id)
{
    for (int index = 0; index < QEMU_MAX_COMMAND_CONTEXTS; index++) {
        QemuCommandContext *command = &g_commands[index];
        if (command->active && command->has_command_id && command->id == command_id) {
            return command;
        }
    }
    return NULL;
}

static QemuCommandContext *register_command_context(unsigned long long command_id, int has_command_id)
{
    if (!has_command_id || command_id == 0) {
        return NULL;
    }

    pthread_mutex_lock(&g_commands_mutex);
    if (find_command_by_id_locked(command_id) != NULL) {
        pthread_mutex_unlock(&g_commands_mutex);
        return NULL;
    }
    for (int index = 0; index < QEMU_MAX_COMMAND_CONTEXTS; index++) {
        QemuCommandContext *command = &g_commands[index];
        if (!command->active) {
            memset(command, 0, sizeof(*command));
            command->id = command_id;
            command->has_command_id = 1;
            command->active = 1;
            pthread_mutex_unlock(&g_commands_mutex);
            return command;
        }
    }
    pthread_mutex_unlock(&g_commands_mutex);
    return NULL;
}

static void unregister_command_context(QemuCommandContext *command)
{
    if (command == NULL) {
        return;
    }
    pthread_mutex_lock(&g_commands_mutex);
    command->active = 0;
    command->has_command_id = 0;
    command->cancelled = 0;
    pthread_mutex_unlock(&g_commands_mutex);
}

/*
 * cancel 标志的读侧:guest 线程在 syscall 入口逐次轮询(do_syscall →
 * ios_qemu_should_cancel),为了不在热路径上抢 session->mutex 而无锁读;
 * 写侧(session_close / qemu_runner_cancel)在各自的表锁下置 1。跨线程的
 * "锁下写 vs 无锁读"必须走原子访问,否则是 C11 数据竞争(TSan:
 * session_close 写 vs cancel_check 读)。标志单调 0→1、槽位静态终身有效,
 * relaxed 语义足够:轮询循环保证最终可见,无需与其它状态建立顺序。
 */
static int qemu_command_cancel_check(void *opaque)
{
    QemuCommandContext *command = (QemuCommandContext *)opaque;
    return command != NULL
        && __atomic_load_n(&command->cancelled, __ATOMIC_RELAXED);
}

static int qemu_session_cancel_check(void *opaque)
{
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    return session != NULL
        && __atomic_load_n(&session->cancel_requested, __ATOMIC_RELAXED);
}

static void append_session_output_locked(QemuSessionContext *session, const char *data, size_t data_len) {
    if (session == NULL || data == NULL || data_len == 0) {
        return;
    }
    size_t available = QEMU_SESSION_OUTPUT_CAPACITY - session->output_len;
    size_t copied = data_len < available ? data_len : available;
    if (copied == 0) {
        return;
    }
    memcpy(session->output + session->output_len, data, copied);
    session->output_len += copied;
}

static ssize_t qemu_session_terminal_read(void *opaque, void *buf, size_t size) {
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    if (session == NULL || buf == NULL || size == 0) {
        return -1;
    }

    pthread_mutex_lock(&session->mutex);
    while (session->input_len == 0 && !session->closed) {
        pthread_cond_wait(&session->input_cond, &session->mutex);
    }
    if (session->input_len == 0 && session->closed) {
        pthread_mutex_unlock(&session->mutex);
        return 0;
    }

    size_t copied = session->input_len < size ? session->input_len : size;
    memcpy(buf, session->input, copied);
    memmove(session->input, session->input + copied, session->input_len - copied);
    session->input_len -= copied;
    pthread_mutex_unlock(&session->mutex);
    return (ssize_t)copied;
}

static void qemu_session_terminal_input_consumed(void *opaque, size_t size) {
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    unsigned long long latency_session_id = 0;
    uint64_t latency_seq = 0;
    uint64_t latency_input_ns = 0;
    uint64_t latency_now_ns = 0;

    if (session == NULL || size == 0 || !trace_qemu_latency()) {
        return;
    }
    pthread_mutex_lock(&session->mutex);
    if (!session->latency_read_reported) {
        session->latency_read_reported = 1;
        latency_session_id = session->id;
        latency_seq = session->latency_seq;
        latency_input_ns = session->latency_input_ns;
        latency_now_ns = qemu_monotonic_ns();
    }
    pthread_mutex_unlock(&session->mutex);
    if (latency_seq != 0) {
        fprintf(stderr,
                "[qemu-latency] session=%llu seq=%llu stage=guest_read delta_ms=%.3f bytes=%zu\n",
                latency_session_id, (unsigned long long)latency_seq,
                qemu_latency_ms(latency_input_ns, latency_now_ns), size);
    }
}

static ssize_t qemu_session_terminal_write(void *opaque, const void *buf, size_t size) {
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    if (session == NULL || buf == NULL) {
        return -1;
    }

    unsigned long long latency_session_id = 0;
    uint64_t latency_seq = 0;
    uint64_t latency_input_ns = 0;
    uint64_t latency_now_ns = 0;

    trace_qemu_session_bytes("terminal_write", buf, size);
    pthread_mutex_lock(&session->mutex);
    append_session_output_locked(session, (const char *)buf, size);
    if (trace_qemu_latency() && !session->latency_output_reported) {
        session->latency_output_reported = 1;
        latency_session_id = session->id;
        latency_seq = session->latency_seq;
        latency_input_ns = session->latency_input_ns;
        latency_now_ns = qemu_monotonic_ns();
    }
    pthread_cond_signal(&session->output_cond);
    pthread_mutex_unlock(&session->mutex);
    if (latency_seq != 0) {
        fprintf(stderr,
                "[qemu-latency] session=%llu seq=%llu stage=guest_output delta_ms=%.3f bytes=%zu\n",
                latency_session_id, (unsigned long long)latency_seq,
                qemu_latency_ms(latency_input_ns, latency_now_ns), size);
    }
    return (ssize_t)size;
}

static int qemu_session_terminal_get_size(void *opaque, unsigned short *cols, unsigned short *rows) {
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    if (session == NULL || cols == NULL || rows == NULL) {
        return -1;
    }

    pthread_mutex_lock(&session->mutex);
    *cols = (unsigned short)session->cols;
    *rows = (unsigned short)session->rows;
    pthread_mutex_unlock(&session->mutex);
    return 0;
}

static int qemu_session_terminal_set_size(void *opaque, unsigned short cols, unsigned short rows) {
    QemuSessionContext *session = (QemuSessionContext *)opaque;
    if (session == NULL || cols == 0 || rows == 0) {
        return -1;
    }

    pthread_mutex_lock(&session->mutex);
    session->cols = cols;
    session->rows = rows;
    pthread_mutex_unlock(&session->mutex);
    return 0;
}

static void *qemu_session_thread_main(void *opaque) {
    QemuSessionThreadContext *context = (QemuSessionThreadContext *)opaque;
    QemuSessionContext *session = context->session;
    QemuArgv current_qemu_argv = context->argv;
    char **current_envp = context->envp != NULL ? context->envp : environ;
    int current_argc = current_qemu_argv.count;
    char **owned_restart_argv = NULL;
    char **owned_restart_envp = NULL;
    int code = 0;
    pid_t session_pid = 0;
    IOSQemuTerminal terminal = {
        .opaque = session,
        .read = qemu_session_terminal_read,
        .write = qemu_session_terminal_write,
        .input_consumed = qemu_session_terminal_input_consumed,
        .get_size = qemu_session_terminal_get_size,
        .set_size = qemu_session_terminal_set_size,
    };
    IOSQemuTTY *tty = NULL;
    IOSQemuFdSnapshot *session_fd_table = NULL;
    IOSQemuTTYFdSnapshot *session_tty_fd_table = NULL;
    context->argv.items = NULL;
    context->argv.count = 0;

    /*
     * Give this session leader PRIVATE fd + tty fd tables so concurrent sessions
     * don't share the global tables and alias each other's stdin/stdout/stderr
     * (fd 0/1/2). Without this the second session's stdin landed on the first
     * session's PTY-master slot and its shell's ppoll waited forever. Install
     * BEFORE attach_thread / any /dev/tty open so every fd binding lands in this
     * session's private tables. A real fork copies them; a CLONE_VM thread shares
     * them by refcount (see darwin-syscall.c clone/fork paths).
     */
    session_fd_table = ios_qemu_fd_table_create_empty();
    session_tty_fd_table = ios_qemu_tty_fd_table_create_empty();
    if (session_fd_table == NULL || session_tty_fd_table == NULL) {
        code = -1;
        goto session_done;
    }
    ios_qemu_fd_table_set_atomic_ref_fast(session_fd_table,
                                           qemu_fd_atomic_ref_enabled());
    ios_qemu_fd_set_current_table(session_fd_table);
    ios_qemu_tty_fd_set_current_table(session_tty_fd_table);

    if (ios_qemu_tty_create(&terminal, (unsigned short)session->cols, (unsigned short)session->rows, &tty) != 0
        || ios_qemu_tty_attach_thread(tty) != 0) {
        code = -1;
        goto session_done;
    }
    pthread_mutex_lock(&session->mutex);
    session->tty = tty;
    pthread_mutex_unlock(&session->mutex);

    ios_qemu_set_cancel_check(qemu_session_cancel_check, session);

    /*
     * Give this session's top-level shell a distinct guest pid so concurrent
     * sessions don't alias one another in the shared guest task table. Must run
     * on the session thread (the pid override is thread-local) before entering
     * the guest; it persists across the loader -> shell exec restart below.
     */
    session_pid = ios_qemu_task_allocate_session_pid();
    ios_qemu_task_set_pid_override(session_pid);

    for (;;) {
        if (trace_qemu_session()) {
            fprintf(stderr, "[qemu-session] enter argc=%d argv0=%s\n",
                    current_argc,
                    current_argc > 0 && current_qemu_argv.items[0] != NULL
                        ? current_qemu_argv.items[0] : "(null)");
            trace_qemu_session_env(current_envp);
        }
        code = ios_qemu_inprocess_enter(
            ios_qemu_main,
            current_argc,
            current_qemu_argv.items,
            current_envp
        );
        if (trace_qemu_session()) {
            fprintf(stderr, "[qemu-session] leave code=%d\n", code);
        }
        if (code != TARGET_IOS_EXIT_RESTART_EXEC) {
            break;
        }
        if (!ios_qemu_has_exec_request()) {
            code = -1;
            break;
        }

        char **next_argv = NULL;
        char **next_envp = NULL;
        if (ios_qemu_get_exec_request(&next_argv, &next_envp) != 0 || next_argv == NULL) {
            code = -1;
            break;
        }
        bool next_wrapped = ios_qemu_exec_request_was_wrapped();
        ios_qemu_take_pseudo_child_exec();
        if (trace_qemu_session()) {
            fprintf(stderr, "[qemu-session] exec request\n");
        }

        free_qemu_argv(&current_qemu_argv);
        if (owned_restart_argv != NULL) {
            free_null_terminated_string_array(owned_restart_argv);
            free_null_terminated_string_array(owned_restart_envp);
        }

        if (build_restart_qemu_argv(g_qemu_path, g_rootfs_path, next_argv, next_wrapped, &current_qemu_argv) != 0) {
            free_null_terminated_string_array(next_argv);
            free_null_terminated_string_array(next_envp);
            code = -1;
            break;
        }
        current_envp = next_envp != NULL ? next_envp : environ;
        current_argc = current_qemu_argv.count;
        owned_restart_argv = next_argv;
        owned_restart_envp = next_envp;
        ios_qemu_inprocess_prepare_exec_restart();
    }

session_done:
    ios_qemu_inprocess_release_current_image();
    ios_qemu_set_cancel_check(NULL, NULL);
    if (session_pid > 0) {
        ios_qemu_task_forget_pid(session_pid);
    }
    /*
     * 释放私有 fd 表。其 TTY-kind 包装自持 owning tty 表引用(见 ios-fd.c),
     * 释放明确打到自己的表,与下方 tty 表的卸载已无顺序要求;保持先 fd 后
     * tty 只是沿袭原布局。
     */
    ios_qemu_fd_set_current_table(NULL);
    ios_qemu_fd_table_unref(session_fd_table);
    ios_qemu_tty_detach_thread();

    pthread_mutex_lock(&session->mutex);
    session->tty = NULL;
    /*
     * 等在飞的 close/write/resize 用完 tty(tty_busy 归零)再往下走到 destroy:
     * session->tty 已清,不会再有新快照。cond_wait 睡眠时释放 session->mutex,
     * 不会卡住 terminal 回调(guest 写路径持 tty->mutex 等 session->mutex)——
     * 回调完成后 guest 侧放掉 tty->mutex,持 busy 的调用才能结束并广播唤醒。
     */
    while (session->tty_busy > 0) {
        pthread_cond_wait(&session->input_cond, &session->mutex);
    }
    if (code != 0 && code != TARGET_IOS_EXIT_RESTART_EXEC) {
        char message[128];
        int written = snprintf(message, sizeof(message), "\r\n[qemu session exited: %d]\r\n", code);
        if (written > 0) {
            append_session_output_locked(session, message, (size_t)written);
        }
    }
    session->closed = 1;
    session->thread_exited = 1;
    pthread_cond_broadcast(&session->input_cond);
    pthread_cond_broadcast(&session->output_cond);
    pthread_mutex_unlock(&session->mutex);

    ios_qemu_tty_destroy(tty);
    /*
     * The private tty fd table's entries are now all released (fd-table teardown
     * closed the /dev/tty fds; detach_thread cleared the fd 0/1/2 bindings). Drop
     * this thread's reference to the table shell itself.
     */
    ios_qemu_tty_fd_set_current_table(NULL);
    ios_qemu_tty_fd_table_unref(session_tty_fd_table);
    ios_qemu_clear_exec_request();
    free_qemu_argv(&current_qemu_argv);
    if (owned_restart_argv != NULL) {
        free_null_terminated_string_array(owned_restart_argv);
        free_null_terminated_string_array(owned_restart_envp);
    }
    free_null_terminated_string_array(context->envp);
    free_null_terminated_string_array(context->owned_guest_argv);
    free(context->guest_argv0);
    free(context);
    return NULL;
}

int qemu_runner_cancel(unsigned long long command_id) {
    pthread_mutex_lock(&g_commands_mutex);
    QemuCommandContext *command = find_command_by_id_locked(command_id);
    if (command == NULL) {
        pthread_mutex_unlock(&g_commands_mutex);
        return -1;
    }
    /* 与 qemu_command_cancel_check 的无锁轮询配对(见其注释),原子置位。 */
    __atomic_store_n(&command->cancelled, 1, __ATOMIC_RELAXED);
    pthread_mutex_unlock(&g_commands_mutex);
    return 0;
}

int qemu_runner_session_open(
    const char *command,
    const char *working_dir,
    const char *env_json,
    unsigned long long session_id,
    int cols,
    int rows
) {
    pthread_mutex_lock(&g_sessions_mutex);
    QemuSessionContext *session = allocate_session_locked(session_id);
    pthread_mutex_unlock(&g_sessions_mutex);
    if (session == NULL) {
        return -2;
    }

    const char *session_command = command != NULL && command[0] != '\0' ? command : "/bin/sh -il";
    const char *session_working_dir = working_dir != NULL && working_dir[0] != '\0'
        ? working_dir
        : "/";
    pthread_mutex_lock(&session->mutex);
    session->cols = cols;
    session->rows = rows;
    char banner[512];
    int written = snprintf(
        banner,
        sizeof(banner),
        "[qemu session starting: %s]\r\n",
        session_command
    );
    if (written > 0) {
        append_session_output_locked(session, banner, (size_t)written);
    }
    pthread_mutex_unlock(&session->mutex);

    char shell_path[4096];
    written = snprintf(shell_path, sizeof(shell_path), "%s/bin/sh", g_rootfs_path);
    if (written < 0 || (size_t)written >= sizeof(shell_path)) {
        qemu_runner_session_close(session_id);
        return -3;
    }

    char **owned_guest_argv = calloc(4, sizeof(char *));
    if (owned_guest_argv == NULL) {
        qemu_runner_session_close(session_id);
        return -3;
    }
    owned_guest_argv[0] = strdup(shell_path);
    if (strcmp(session_command, "/bin/sh -il") == 0) {
        owned_guest_argv[1] = strdup("-il");
    } else {
        owned_guest_argv[1] = strdup("-lc");
        owned_guest_argv[2] = strdup(session_command);
    }
    if (owned_guest_argv[0] == NULL || owned_guest_argv[1] == NULL
        || (owned_guest_argv[2] == NULL && owned_guest_argv[1] != NULL && strcmp(owned_guest_argv[1], "-lc") == 0)) {
        free_null_terminated_string_array(owned_guest_argv);
        qemu_runner_session_close(session_id);
        return -3;
    }

    QemuArgv qemu_argv = {0};
    const char *guest_argv0 = "/bin/sh";
    if (build_qemu_argv(g_qemu_path, g_rootfs_path, owned_guest_argv, guest_argv0, &qemu_argv) != 0) {
        free_null_terminated_string_array(owned_guest_argv);
        qemu_runner_session_close(session_id);
        return -3;
    }

    char *guest_env[64] = {0};
    int guest_envc = parse_json_env_object(env_json, guest_env, 64);
    if (guest_envc < 0
        || append_default_session_shell_env(guest_env, &guest_envc, 64) != 0
        || append_guest_cwd_env(guest_env, &guest_envc, 64, session_working_dir) != 0
        || append_mount_table_env(guest_env, &guest_envc, 64) != 0) {
        free_qemu_argv(&qemu_argv);
        free_null_terminated_string_array(owned_guest_argv);
        free_string_array(guest_env, guest_envc > 0 ? guest_envc : 0);
        qemu_runner_session_close(session_id);
        return -3;
    }

    char **envp = NULL;
    if (guest_envc > 0) {
        envp = calloc((size_t)guest_envc + 1, sizeof(char *));
        if (envp == NULL) {
            free_qemu_argv(&qemu_argv);
            free_null_terminated_string_array(owned_guest_argv);
            free_string_array(guest_env, guest_envc);
            qemu_runner_session_close(session_id);
            return -3;
        }
        for (int index = 0; index < guest_envc; index++) {
            envp[index] = guest_env[index];
            guest_env[index] = NULL;
        }
    }

    QemuSessionThreadContext *context = calloc(1, sizeof(*context));
    if (context == NULL) {
        free_qemu_argv(&qemu_argv);
        free_null_terminated_string_array(envp);
        free_null_terminated_string_array(owned_guest_argv);
        qemu_runner_session_close(session_id);
        return -3;
    }
    context->session = session;
    context->argv = qemu_argv;
    context->envp = envp;
    context->owned_guest_argv = owned_guest_argv;
    context->guest_argv0 = guest_argv0 != NULL ? strdup(guest_argv0) : NULL;
    if (guest_argv0 != NULL && context->guest_argv0 == NULL) {
        free_qemu_argv(&context->argv);
        free_null_terminated_string_array(context->envp);
        free_null_terminated_string_array(context->owned_guest_argv);
        free(context);
        qemu_runner_session_close(session_id);
        return -3;
    }

    if (qemu_runner_init_runtime(qemu_argv.items[0], g_rootfs_path) != 0
        || pthread_create(&session->thread, NULL, qemu_session_thread_main, context) != 0) {
        free_qemu_argv(&context->argv);
        free_null_terminated_string_array(context->envp);
        free_null_terminated_string_array(context->owned_guest_argv);
        free(context->guest_argv0);
        free(context);
        qemu_runner_session_close(session_id);
        return -3;
    }
    session->thread_started = 1;
    pthread_detach(session->thread);
    return 0;
}

int qemu_runner_session_write(unsigned long long session_id, const char *data) {
    QemuSessionContext *session;
    IOSQemuTTY *tty;
    size_t data_len;
    ssize_t written;
    unsigned long long latency_session_id = 0;
    uint64_t latency_seq = 0;
    uint64_t latency_input_ns = 0;

    if (data == NULL) {
        return -2;
    }
    session = session_find_and_lock(session_id);
    if (session == NULL) {
        return -2;
    }
    if (session->closed) {
        pthread_mutex_unlock(&session->mutex);
        return -2;
    }
    tty = session_tty_acquire_locked(session);
    data_len = strlen(data);
    if (trace_qemu_latency()) {
        session->latency_seq++;
        session->latency_input_ns = qemu_monotonic_ns();
        latency_input_ns = session->latency_input_ns;
        session->latency_read_reported = 0;
        session->latency_output_reported = 0;
        session->latency_host_read_reported = 0;
        latency_session_id = session->id;
        latency_seq = session->latency_seq;
    }
    pthread_mutex_unlock(&session->mutex);
    if (tty == NULL) {
        return -2;
    }
    if (latency_seq != 0) {
        fprintf(stderr,
                "[qemu-latency] session=%llu seq=%llu stage=input delta_ms=0.000 bytes=%zu\n",
                latency_session_id, (unsigned long long)latency_seq, data_len);
    }
    trace_qemu_session_bytes("session_write", data, data_len);
    written = ios_qemu_tty_input(tty, data, data_len, false);
    if (latency_seq != 0) {
        uint64_t latency_queued_ns = qemu_monotonic_ns();

        fprintf(stderr,
                "[qemu-latency] session=%llu seq=%llu stage=queued delta_ms=%.3f bytes=%zu written=%zd\n",
                latency_session_id, (unsigned long long)latency_seq,
                qemu_latency_ms(latency_input_ns, latency_queued_ns),
                data_len, written);
    }
    session_tty_release(session);
    if (written == (ssize_t)data_len) {
        qemu_latency_watchdog_start(session, latency_session_id, latency_seq);
        return 0;
    }
    return -3;
}

int qemu_runner_session_resize(unsigned long long session_id, int cols, int rows) {
    QemuSessionContext *session = session_find_and_lock(session_id);
    IOSQemuTTY *tty;

    if (session == NULL) {
        return -2;
    }
    session->cols = cols;
    session->rows = rows;
    tty = (cols > 0 && rows > 0) ? session_tty_acquire_locked(session) : NULL;
    pthread_mutex_unlock(&session->mutex);
    if (tty != NULL) {
        int ret = ios_qemu_tty_resize(tty, (unsigned short)cols, (unsigned short)rows);
        session_tty_release(session);
        return ret;
    }
    return 0;
}

int qemu_runner_session_read(
    unsigned long long session_id,
    char *output_buf,
    size_t output_buf_size
) {
    QemuSessionContext *session;

    if (output_buf == NULL || output_buf_size == 0) {
        return -2;
    }
    session = session_find_and_lock(session_id);
    if (session == NULL) {
        return -2;
    }
    if (session->output_len == 0) {
        int closed = session->closed;
        int can_reclaim = closed && (!session->thread_started || session->thread_exited);
        output_buf[0] = '\0';
        pthread_mutex_unlock(&session->mutex);
        if (can_reclaim) {
            pthread_mutex_lock(&g_sessions_mutex);
            if (session->id == session_id) {
                session->active = 0;
            }
            pthread_mutex_unlock(&g_sessions_mutex);
            /* 不 destroy mutex/cond:槽位同步原语静态初始化、终身有效(见
             * g_sessions 定义处注释),迟到的回调上锁才安全。 */
            return -4;
        }
        return 0;
    }

    size_t copied = session->output_len < output_buf_size - 1
        ? session->output_len
        : output_buf_size - 1;
    memcpy(output_buf, session->output, copied);
    output_buf[copied] = '\0';
    trace_qemu_session_bytes("session_read", output_buf, copied);
    memmove(session->output, session->output + copied, session->output_len - copied);
    session->output_len -= copied;
    unsigned long long latency_session_id = 0;
    uint64_t latency_seq = 0;
    uint64_t latency_input_ns = 0;
    uint64_t latency_now_ns = 0;
    if (trace_qemu_latency()
        && session->latency_output_reported
        && !session->latency_host_read_reported) {
        session->latency_host_read_reported = 1;
        latency_session_id = session->id;
        latency_seq = session->latency_seq;
        latency_input_ns = session->latency_input_ns;
        latency_now_ns = qemu_monotonic_ns();
    }
    pthread_mutex_unlock(&session->mutex);
    if (latency_seq != 0) {
        fprintf(stderr,
                "[qemu-latency] session=%llu seq=%llu stage=host_read delta_ms=%.3f bytes=%zu\n",
                latency_session_id, (unsigned long long)latency_seq,
                qemu_latency_ms(latency_input_ns, latency_now_ns), copied);
    }
    return (int)copied;
}

int qemu_runner_session_wait_output(unsigned long long session_id) {
    QemuSessionContext *session = session_find_and_lock(session_id);

    if (session == NULL) {
        return -2;
    }
    /*
     * read 返回空与这里入睡之间由同一把 session->mutex 串行化；terminal
     * callback 在追加输出后 signal，因此不会丢失“刚好发生在轮询间隙”的唤醒。
     * close/线程退出 broadcast，让 reader 回到 read 路径取得 -4。
     */
    while (session->output_len == 0 && !session->closed) {
        pthread_cond_wait(&session->output_cond, &session->mutex);
    }
    int ready = session->output_len > 0 ? 1 : 0;
    pthread_mutex_unlock(&session->mutex);
    return ready;
}

int qemu_runner_session_close(unsigned long long session_id) {
    QemuSessionContext *session = session_find_and_lock(session_id);
    if (session == NULL) {
        return -2;
    }
    /*
     * shutdown 必须在 session->mutex 之外调:它取 tty->mutex,而 terminal
     * write 回调在 tty->mutex 下取 session->mutex,持锁调用即 ABBA 死锁环。
     * acquire 快照撑住 tty,防 session 线程 teardown 并发 destroy。
     */
    IOSQemuTTY *tty = session_tty_acquire_locked(session);
    /* 与 qemu_session_cancel_check 的无锁轮询配对(见其注释),原子置位。 */
    __atomic_store_n(&session->cancel_requested, 1, __ATOMIC_RELAXED);
    session->closed = 1;
    pthread_cond_broadcast(&session->input_cond);
    pthread_cond_broadcast(&session->output_cond);
    pthread_mutex_unlock(&session->mutex);
    if (tty != NULL) {
        ios_qemu_tty_shutdown(tty);
        session_tty_release(session);
    }
    return 0;
}

/*
 * elf_path is a host path (typically <rootfs_path>/... for the one-shot
 * exec API). Strip the rootfs prefix to recover the guest-visible path for
 * '-0', so /proc/self/exe, /proc/self/cmdline and readlink(2) in the guest
 * never surface the host sandbox path. Falls back to elf_path itself when
 * it does not live under rootfs_path (e.g. a caller-supplied absolute host
 * path outside the rootfs).
 */
static const char *derive_guest_argv0_from_elf_path(const char *elf_path, const char *rootfs_path)
{
    size_t rootfs_len;

    if (elf_path == NULL) {
        return NULL;
    }
    if (rootfs_path == NULL || rootfs_path[0] == '\0') {
        return elf_path;
    }
    rootfs_len = path_len_without_trailing_slash(rootfs_path);
    if (strncmp(elf_path, rootfs_path, rootfs_len) == 0 && elf_path[rootfs_len] == '/') {
        return elf_path + rootfs_len;
    }
    return elf_path;
}

int qemu_runner_exec_with_id(
    const char *elf_path,
    const char *argv_json,
    const char *env_json,
    const char *working_dir,
    unsigned long long command_id,
    int has_command_id,
    char *stdout_buf,
    size_t stdout_size,
    char *stderr_buf,
    size_t stderr_size
) {
    const char *qemu_path = g_qemu_path;
    bool process_perf_stats = qemu_process_perf_stats_enabled();
    uint64_t runner_started_ns = process_perf_stats ? qemu_monotonic_ns() : 0;
    uint64_t runner_setup_ns = 0;
    uint64_t runner_inprocess_calls = 0;
    uint64_t runner_inprocess_ns = 0;
    uint64_t runner_release_image_ns = 0;

    if (elf_path == NULL || elf_path[0] == '\0') {
        write_buffer(stderr_buf, stderr_size, "ELF path is empty");
        return -41;
    }

    char *guest_args[64] = {0};
    int guest_argc = parse_json_string_array(argv_json, guest_args, 64);
    if (guest_argc < 0) {
        write_buffer(stderr_buf, stderr_size, "QEMU argv JSON must be an array of strings");
        return -46;
    }
    char *guest_env[64] = {0};
    int guest_envc = parse_json_env_object(env_json, guest_env, 64);
    if (guest_envc < 0) {
        free_string_array(guest_args, guest_argc);
        write_buffer(stderr_buf, stderr_size, "QEMU environment JSON must be an object of string values");
        return -47;
    }
    if (append_default_session_shell_env(guest_env, &guest_envc, 64) != 0) {
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "QEMU environment is full");
        return -59;
    }
    if (append_guest_cwd_env(guest_env, &guest_envc, 64, working_dir) != 0) {
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "QEMU environment is full");
        return -54;
    }
    if (append_mount_table_env(guest_env, &guest_envc, 64) != 0) {
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "QEMU environment is full");
        return -55;
    }

    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0) {
        int saved_errno = errno;
        if (stdout_pipe[0] >= 0) {
            close(stdout_pipe[0]);
        }
        if (stdout_pipe[1] >= 0) {
            close(stdout_pipe[1]);
        }
        if (stderr_pipe[0] >= 0) {
            close(stderr_pipe[0]);
        }
        if (stderr_pipe[1] >= 0) {
            close(stderr_pipe[1]);
        }
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, strerror(saved_errno));
        return -42;
    }

    const char *rootfs_path = g_rootfs_path;
    char *initial_guest_argv[66] = {0};
    QemuArgv initial_qemu_argv = {0};
    initial_guest_argv[0] = (char *)elf_path;
    for (int index = 0; index < guest_argc && index + 1 < 65; index++) {
        initial_guest_argv[index + 1] = guest_args[index];
    }
    const char *guest_argv0 = derive_guest_argv0_from_elf_path(elf_path, rootfs_path);
    if (build_qemu_argv(qemu_path, rootfs_path, initial_guest_argv, guest_argv0, &initial_qemu_argv) != 0) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[0]);
        close(stderr_pipe[1]);
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "Failed to allocate QEMU argv");
        return -56;
    }

    close(stdout_pipe[0]);
    close(stdout_pipe[1]);
    close(stderr_pipe[0]);
    close(stderr_pipe[1]);

    if (qemu_runner_init_runtime(initial_qemu_argv.items[0], rootfs_path) != 0) {
        free_qemu_argv(&initial_qemu_argv);
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "Failed to initialize QEMU runtime");
        return -53;
    }

    QemuArgv current_qemu_argv = initial_qemu_argv;
    char **current_argv = current_qemu_argv.items;
    char **current_envp = guest_env[0] != NULL ? guest_env : environ;
    int current_argc = current_qemu_argv.count;
    char **owned_guest_argv = NULL;
    char **owned_envp = NULL;
    int exit_code = 0;
    IOSQemuFdSnapshot *previous_fd_table = ios_qemu_fd_current_table();
    IOSQemuTTYFdSnapshot *previous_tty_fd_table = ios_qemu_tty_fd_current_table();
    IOSQemuFdSnapshot *exec_fd_table = ios_qemu_fd_table_create_empty();
    IOSQemuTTYFdSnapshot *exec_tty_fd_table = ios_qemu_tty_fd_table_create_empty();
    if (exec_fd_table == NULL || exec_tty_fd_table == NULL) {
        ios_qemu_fd_table_unref(exec_fd_table);
        ios_qemu_tty_fd_table_unref(exec_tty_fd_table);
        free_qemu_argv(&current_qemu_argv);
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(stderr_buf, stderr_size, "Failed to allocate QEMU fd tables");
        return -58;
    }
    QemuCommandContext *command_context = register_command_context(command_id, has_command_id);
    if (has_command_id && command_context == NULL) {
        ios_qemu_fd_table_unref(exec_fd_table);
        ios_qemu_tty_fd_table_unref(exec_tty_fd_table);
        free_qemu_argv(&current_qemu_argv);
        free_string_array(guest_args, guest_argc);
        free_string_array(guest_env, guest_envc);
        write_buffer(
            stderr_buf,
            stderr_size,
            "QEMU command context limit reached or command id is already active"
        );
        return -57;
    }
    QemuExecCaptureContext capture_context = {
        .stdout_buf = stdout_buf,
        .stdout_size = stdout_size,
        .stdout_offset = 0,
        .stderr_buf = stderr_buf,
        .stderr_size = stderr_size,
        .stderr_offset = 0,
        .stats_enabled = qemu_fd_capture_stats_enabled(),
    };
    const IOSQemuFdWriter fd_writer = {
        .opaque = &capture_context,
        .write = qemu_exec_capture_write,
        .writev = qemu_fd_capture_writev_enabled()
            ? qemu_exec_capture_writev : NULL,
        .fast_path = qemu_fd_capture_fast_enabled(),
    };

    if (stdout_buf != NULL && stdout_size > 0) {
        stdout_buf[0] = '\0';
    }
    if (stderr_buf != NULL && stderr_size > 0) {
        stderr_buf[0] = '\0';
    }
    /*
     * 一次性 exec 也必须使用私有 fd/tty 表。否则它会落到进程级全局表,与
     * 并发 session 或另一个 exec 按 fd 号别名互踩。tty 表同时承载本 exec 的
     * /dev/pts registry,保持 ptmx/pts 命名空间不与 session 串台。
     */
    ios_qemu_fd_table_set_atomic_ref_fast(exec_fd_table,
                                           qemu_fd_atomic_ref_enabled());
    ios_qemu_fd_set_current_table(exec_fd_table);
    ios_qemu_tty_fd_set_current_table(exec_tty_fd_table);
    /*
     * 捕获 writer 挂在私有 fd 表上(不再是 __thread):guest 真 fork 出的
     * 子进程(管道、多命令)复制/共享该表,其 fd 1/2 输出才进捕获缓冲。
     * capture_context 在本函数栈上,返回前必须 deactivate(见 teardown)。
     */
    ios_qemu_fd_table_set_writer(exec_fd_table, &fd_writer);
    ios_qemu_set_cancel_check(qemu_command_cancel_check, command_context);
    /*
     * 给本次 exec 的 guest 进程分配独立 pid(与 session leader 同机制)。
     * 不分配的话 guest pid 恒为宿主 getpid():第一次 exec 的 exit_group(0)
     * 把 exit_group_requested 留在该 pid 的任务表记录上,同进程第二次 exec
     * 复用同一 pid,首个 syscall 就被 do_syscall 入口闸门收割成 exit=0 ——
     * 2-3ms 假成功,命令根本没执行。独立 pid + 结束 forget 同时消除并发
     * 一次性 exec 之间的任务表别名。pid override 是 __thread,须在本线程、
     * 进入 guest 之前设置;它跨 execve 重入持续,fork 子进程另行分配。
     */
    pid_t previous_pid_override = ios_qemu_task_get_pid_override();
    pid_t exec_pid = ios_qemu_task_allocate_session_pid();
    bool syscall_stats = qemu_syscall_stats_enabled();
    bool fd_sparse_stats = qemu_fd_sparse_scan_stats_enabled();
    IOSQemuFdSparseScanStats fd_scan_stats = {0};
    IOSQemuTTYSparseScanStats tty_scan_stats = {0};
    IOSQemuProcessPerfStats process_stats = {0};
    sigset_t previous_host_sigmask;
    int have_previous_host_sigmask =
        pthread_sigmask(SIG_SETMASK, NULL, &previous_host_sigmask) == 0;
    ios_qemu_task_set_pid_override(exec_pid);
    if (syscall_stats) {
        ios_qemu_syscall_stats_begin();
    }
    if (fd_sparse_stats) {
        ios_qemu_fd_sparse_scan_stats_begin();
        ios_qemu_tty_sparse_scan_stats_begin();
    }
    if (process_perf_stats) {
        runner_setup_ns = qemu_monotonic_ns() - runner_started_ns;
        ios_qemu_process_perf_stats_begin();
    }
    for (;;) {
        uint64_t inprocess_started_ns = process_perf_stats
            ? qemu_monotonic_ns() : 0;
        int code = ios_qemu_inprocess_enter(ios_qemu_main, current_argc,
                                            current_argv, current_envp);
        if (process_perf_stats) {
            runner_inprocess_calls++;
            runner_inprocess_ns += qemu_monotonic_ns() - inprocess_started_ns;
        }
        if (code != TARGET_IOS_EXIT_RESTART_EXEC) {
            exit_code = code;
            break;
        }
        if (!ios_qemu_has_exec_request()) {
            write_buffer(stderr_buf, stderr_size, "QEMU restart requested but no exec request payload was captured.");
            exit_code = -1;
            break;
        }

        char **next_argv = NULL;
        char **next_envp = NULL;
        if (ios_qemu_get_exec_request(&next_argv, &next_envp) != 0 || next_argv == NULL) {
            exit_code = -1;
            break;
        }
        bool next_wrapped = ios_qemu_exec_request_was_wrapped();

        free_qemu_argv(&current_qemu_argv);
        if (owned_guest_argv != NULL) {
            free_null_terminated_string_array(owned_guest_argv);
            free_null_terminated_string_array(owned_envp);
        }

        if (build_restart_qemu_argv(qemu_path, rootfs_path, next_argv, next_wrapped, &current_qemu_argv) != 0) {
            free_null_terminated_string_array(next_argv);
            free_null_terminated_string_array(next_envp);
            exit_code = -1;
            break;
        }
        current_argv = current_qemu_argv.items;
        current_envp = next_envp != NULL ? next_envp : environ;
        current_argc = current_qemu_argv.count;
        owned_guest_argv = next_argv;
        owned_envp = next_envp;
        ios_qemu_inprocess_prepare_exec_restart();
    }
    {
        uint64_t release_started_ns = process_perf_stats
            ? qemu_monotonic_ns() : 0;

        ios_qemu_inprocess_release_current_image();
        if (process_perf_stats) {
            runner_release_image_ns += qemu_monotonic_ns() - release_started_ns;
        }
    }
    if (syscall_stats) {
        ios_qemu_syscall_stats_end();
    }
    if (capture_context.stats_enabled) {
        fprintf(stderr,
                "[fd-capture-stats] callbacks=%zu segments=%zu bytes=%zu "
                "min=%zu max=%zu "
                "le64=%zu le256=%zu le1024=%zu stdout=%zu stderr=%zu\n",
                capture_context.stats_callbacks,
                capture_context.stats_segments, capture_context.stats_bytes,
                capture_context.stats_min_size, capture_context.stats_max_size,
                capture_context.stats_le_64, capture_context.stats_le_256,
                capture_context.stats_le_1024, capture_context.stdout_offset,
                capture_context.stderr_offset);
    }
    if (have_previous_host_sigmask) {
        pthread_sigmask(SIG_SETMASK, &previous_host_sigmask, NULL);
    }
    ios_qemu_set_cancel_check(NULL, NULL);
    /*
     * 归还本次 exec 的 guest pid 并恢复本线程进入前的 override(caller 线程会
     * 被复用跑下一次 exec;恢复而非硬清 0,防将来在已持 override 的线程上
     * 调用时把外层身份清掉)。forget 摘除任务表记录,exit_group_requested
     * 残留随之消失;fork 出的子进程各有自己的 pid 记录,不受影响。
     */
    ios_qemu_task_forget_pid(exec_pid);
    ios_qemu_task_set_pid_override(previous_pid_override);
    /*
     * 失活捕获 writer(box 内 writer 置 NULL,与在飞写入串行化):本函数返回后
     * capture_context(栈上)不再有效,尚存活的后台子进程仍持有 box 引用,
     * 其后续输出被静默吞掉而不是悬垂访问。
     */
    ios_qemu_fd_table_deactivate_writer(exec_fd_table);
    ios_qemu_fd_set_current_table(previous_fd_table);
    ios_qemu_fd_table_unref(exec_fd_table);
    ios_qemu_tty_fd_set_current_table(previous_tty_fd_table);
    ios_qemu_tty_fd_table_unref(exec_tty_fd_table);
    if (fd_sparse_stats) {
        ios_qemu_fd_sparse_scan_stats_end(&fd_scan_stats);
        ios_qemu_tty_sparse_scan_stats_end(&tty_scan_stats);
        fprintf(stderr,
                "[fd-sparse-stats] snapshot=%llu/%llu open=%llu ns=%llu "
                "cloexec=%llu/%llu closed=%llu ns=%llu destroy=%llu/%llu "
                "open=%llu ns=%llu\n",
                (unsigned long long)fd_scan_stats.snapshot_calls,
                (unsigned long long)fd_scan_stats.snapshot_slots,
                (unsigned long long)fd_scan_stats.snapshot_open_entries,
                (unsigned long long)fd_scan_stats.snapshot_ns,
                (unsigned long long)fd_scan_stats.cloexec_calls,
                (unsigned long long)fd_scan_stats.cloexec_slots,
                (unsigned long long)fd_scan_stats.cloexec_closed_entries,
                (unsigned long long)fd_scan_stats.cloexec_ns,
                (unsigned long long)fd_scan_stats.destroy_calls,
                (unsigned long long)fd_scan_stats.destroy_slots,
                (unsigned long long)fd_scan_stats.destroy_open_entries,
                (unsigned long long)fd_scan_stats.destroy_ns);
        fprintf(stderr,
                "[tty-sparse-stats] snapshot=%llu/%llu open=%llu ns=%llu "
                "destroy=%llu/%llu open=%llu ns=%llu\n",
                (unsigned long long)tty_scan_stats.snapshot_calls,
                (unsigned long long)tty_scan_stats.snapshot_slots,
                (unsigned long long)tty_scan_stats.snapshot_open_entries,
                (unsigned long long)tty_scan_stats.snapshot_ns,
                (unsigned long long)tty_scan_stats.destroy_calls,
                (unsigned long long)tty_scan_stats.destroy_slots,
                (unsigned long long)tty_scan_stats.destroy_open_entries,
                (unsigned long long)tty_scan_stats.destroy_ns);
    }
    if (process_perf_stats) {
        ios_qemu_process_perf_stats_end(&process_stats);
        fprintf(stderr,
                "[process-perf-stats] forks=%llu parent_ns=%llu "
                "cpu_copy_ns=%llu address_space_ns=%llu fd_snapshot_ns=%llu "
                "pthread_ready_ns=%llu vfork_wait_ns=%llu child_setup_ns=%llu "
                "child_run_ns=%llu child_teardown_ns=%llu "
                "exec_prepare=%llu/%llu wait=%llu/%llu\n",
                (unsigned long long)process_stats.fork_calls,
                (unsigned long long)process_stats.fork_parent_setup_ns,
                (unsigned long long)process_stats.fork_cpu_copy_ns,
                (unsigned long long)process_stats.fork_address_space_ns,
                (unsigned long long)process_stats.fork_fd_snapshot_ns,
                (unsigned long long)process_stats.fork_pthread_ready_ns,
                (unsigned long long)process_stats.fork_vfork_wait_ns,
                (unsigned long long)process_stats.child_setup_ns,
                (unsigned long long)process_stats.child_run_ns,
                (unsigned long long)process_stats.child_teardown_ns,
                (unsigned long long)process_stats.exec_prepare_calls,
                (unsigned long long)process_stats.exec_prepare_ns,
                (unsigned long long)process_stats.wait_calls,
                (unsigned long long)process_stats.wait_ns);
    }
    unregister_command_context(command_context);

    free_qemu_argv(&current_qemu_argv);
    if (owned_guest_argv != NULL) {
        free_null_terminated_string_array(owned_guest_argv);
        free_null_terminated_string_array(owned_envp);
    }
    ios_qemu_clear_exec_request();

    free_string_array(guest_args, guest_argc);
    free_string_array(guest_env, guest_envc);

    /*
     * M6 真机命中率诊断:静态 AOT 下每 exec 完成后把累计 hits/misses 追加到
     * 容器可读文件(rootfs 父目录),供 afcclient 回收。仅静态 AOT 构建触发,
     * 普通 TCI 构建 ios_qemu_aot_static_active()==false,零副作用。
     */
    if (ios_qemu_aot_static_active() && g_rootfs_path[0] != '\0') {
        uint64_t h = 0, m = 0;
        ios_qemu_aot_hit_stats(&h, &m);
        char stats_path[4200];
        /* g_rootfs_path = <container>/mobile-sandbox/runtimes/<id>;上跳两级到
         * <container>/mobile-sandbox/,写 aot-hitstats.txt。 */
        char base[4096];
        snprintf(base, sizeof(base), "%s", g_rootfs_path);
        for (int up = 0; up < 2; up++) {
            char *slash = strrchr(base, '/');
            if (slash != NULL) {
                *slash = '\0';
            }
        }
        snprintf(stats_path, sizeof(stats_path), "%s/aot-hitstats.txt", base);
        FILE *sf = fopen(stats_path, "a");
        if (sf != NULL) {
            fprintf(sf, "cum_hits=%llu cum_misses=%llu\n",
                    (unsigned long long)h, (unsigned long long)m);
            fclose(sf);
        }
    }

    if (process_perf_stats) {
        uint64_t runner_total_ns = qemu_monotonic_ns() - runner_started_ns;
        uint64_t runner_known_ns = runner_setup_ns + runner_inprocess_ns +
                                   runner_release_image_ns;
        uint64_t runner_other_ns = runner_total_ns > runner_known_ns
            ? runner_total_ns - runner_known_ns : 0;

        fprintf(stderr,
                "[exec-lifecycle-stats] runner_total_ns=%llu setup_ns=%llu "
                "inprocess=%llu/%llu release_image_ns=%llu other_ns=%llu "
                "images=%llu main_pre_cpu_ns=%llu "
                "reset_env_args_ns=%llu init_paths_ns=%llu open_elf_ns=%llu "
                "exec_fd_path=%llu/%llu cpu_model_ns=%llu accel_thread_ns=%llu "
                "cpu_create_reset_ns=%llu main_pre_loader_ns=%llu "
                "pool_enter_empty_ns=%llu "
                "loader_exec_ns=%llu main_post_loader_ns=%llu "
                "init_main_thread_ns=%llu image_finalize_ns=%llu "
                "cpu_loop=%llu/%llu exec_reset_ns=%llu "
                "release_address_space_ns=%llu release_misc_ns=%llu "
                "release_cpu_ns=%llu\n",
                (unsigned long long)runner_total_ns,
                (unsigned long long)runner_setup_ns,
                (unsigned long long)runner_inprocess_calls,
                (unsigned long long)runner_inprocess_ns,
                (unsigned long long)runner_release_image_ns,
                (unsigned long long)runner_other_ns,
                (unsigned long long)process_stats.image_calls,
                (unsigned long long)process_stats.main_pre_cpu_ns,
                (unsigned long long)process_stats.main_reset_env_args_ns,
                (unsigned long long)process_stats.main_init_paths_ns,
                (unsigned long long)process_stats.main_open_elf_ns,
                (unsigned long long)process_stats.exec_fd_path_attempts,
                (unsigned long long)process_stats.exec_fd_path_hits,
                (unsigned long long)process_stats.main_cpu_model_ns,
                (unsigned long long)process_stats.main_accel_thread_ns,
                (unsigned long long)process_stats.cpu_create_reset_ns,
                (unsigned long long)process_stats.main_pre_loader_ns,
                (unsigned long long)process_stats.pool_enter_empty_ns,
                (unsigned long long)process_stats.loader_exec_ns,
                (unsigned long long)process_stats.main_post_loader_ns,
                (unsigned long long)process_stats.init_main_thread_ns,
                (unsigned long long)process_stats.image_finalize_ns,
                (unsigned long long)process_stats.cpu_loop_calls,
                (unsigned long long)process_stats.cpu_loop_ns,
                (unsigned long long)process_stats.exec_reset_ns,
                (unsigned long long)process_stats.release_address_space_ns,
                (unsigned long long)process_stats.release_misc_ns,
                (unsigned long long)process_stats.release_cpu_ns);
    }

    return exit_code;
}

int qemu_runner_exec(
    const char *elf_path,
    const char *argv_json,
    const char *env_json,
    const char *working_dir,
    char *stdout_buf,
    size_t stdout_size,
    char *stderr_buf,
    size_t stderr_size
) {
    return qemu_runner_exec_with_id(
        elf_path,
        argv_json,
        env_json,
        working_dir,
        0,
        0,
        stdout_buf,
        stdout_size,
        stderr_buf,
        stderr_size
    );
}
