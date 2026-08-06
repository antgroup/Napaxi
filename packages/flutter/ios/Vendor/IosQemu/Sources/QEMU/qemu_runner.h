#ifndef QEMU_RUNNER_H
#define QEMU_RUNNER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void qemu_runner_set_paths(const char *qemu_path, const char *rootfs_path);
int qemu_runner_set_mount_table(const char *mount_table);
int qemu_runner_init_runtime(const char *qemu_path, const char *rootfs_path);
int qemu_runner_validate_guest_working_dir(const char *working_dir);

int qemu_runner_exec(
    const char *elf_path,
    const char *argv_json,
    const char *env_json,
    const char *working_dir,
    char *stdout_buf,
    size_t stdout_size,
    char *stderr_buf,
    size_t stderr_size
);

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
);

int qemu_runner_cancel(unsigned long long command_id);

int qemu_runner_session_open(
    const char *command,
    const char *working_dir,
    const char *env_json,
    unsigned long long session_id,
    int cols,
    int rows
);
int qemu_runner_session_write(unsigned long long session_id, const char *data);
int qemu_runner_session_resize(unsigned long long session_id, int cols, int rows);
int qemu_runner_session_read(
    unsigned long long session_id,
    char *output_buf,
    size_t output_buf_size
);
int qemu_runner_session_wait_output(unsigned long long session_id);
int qemu_runner_session_close(unsigned long long session_id);

#ifdef __cplusplus
}
#endif

#endif
