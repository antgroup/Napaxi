#include "qemu_bridge.h"
#include "qemu_runner.h"

#include <stdio.h>
#include <string.h>

static int g_initialized = 0;
static char g_rootfs_path[4096] = {0};

static void write_message(char *buffer, size_t buffer_size, const char *message) {
    if (buffer == NULL || buffer_size == 0) {
        return;
    }
    snprintf(buffer, buffer_size, "%s", message);
}

int qemu_sandbox_init(const char *rootfs_path, const char *mount_table) {
    int mount_result;

    if (rootfs_path == NULL || rootfs_path[0] == '\0') {
        return -1;
    }
    snprintf(g_rootfs_path, sizeof(g_rootfs_path), "%s", rootfs_path);
    qemu_runner_set_paths(NULL, g_rootfs_path);
    mount_result = qemu_runner_set_mount_table(mount_table);
    if (mount_result != 0) {
        return -20;
    }
    g_initialized = 1;
    return 0;
}

int qemu_sandbox_exec(
    const char *elf_path,
    const char *argv_json,
    const char *env_json,
    const char *working_dir,
    char *stdout_buf,
    size_t stdout_size,
    char *stderr_buf,
    size_t stderr_size
) {
    return qemu_sandbox_exec_with_id(
        elf_path,
        argv_json,
        env_json,
        working_dir,
        0, 0,
        stdout_buf,
        stdout_size,
        stderr_buf,
        stderr_size
    );
}

int qemu_sandbox_exec_with_id(
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
    if (!g_initialized) {
        write_message(stderr_buf, stderr_size, "QEMU runtime is not initialized");
        return -10;
    }
    if (elf_path == NULL || elf_path[0] == '\0') {
        write_message(stderr_buf, stderr_size, "elf_path must not be empty");
        return -11;
    }
    if (working_dir == NULL || working_dir[0] != '/') {
        write_message(stderr_buf, stderr_size, "working_dir must be an absolute sandbox path");
        return -12;
    }
    if (qemu_runner_validate_guest_working_dir(working_dir) != 0) {
        write_message(stderr_buf, stderr_size, "working_dir must exist and be a sandbox directory");
        return -13;
    }

    return qemu_runner_exec_with_id(
        elf_path,
        argv_json,
        env_json,
        working_dir,
        command_id,
        has_command_id,
        stdout_buf,
        stdout_size,
        stderr_buf,
        stderr_size
    );
}

int qemu_cancel(unsigned long long command_id) {
    if (!g_initialized) {
        return -10;
    }
    return qemu_runner_cancel(command_id);
}

int qemu_session_open(
    const char *command,
    const char *working_dir,
    const char *env_json,
    unsigned long long session_id,
    int cols,
    int rows
) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0) {
        return -11;
    }
    if (cols <= 0 || rows <= 0) {
        return -12;
    }
    if (working_dir == NULL || working_dir[0] != '/') {
        return -13;
    }
    if (qemu_runner_validate_guest_working_dir(working_dir) != 0) {
        return -14;
    }
    return qemu_runner_session_open(command, working_dir, env_json, session_id, cols, rows);
}

int qemu_session_write(unsigned long long session_id, const char *data) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0 || data == NULL) {
        return -11;
    }
    return qemu_runner_session_write(session_id, data);
}

int qemu_session_resize(unsigned long long session_id, int cols, int rows) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0 || cols <= 0 || rows <= 0) {
        return -11;
    }
    return qemu_runner_session_resize(session_id, cols, rows);
}

int qemu_session_read(
    unsigned long long session_id,
    char *output_buf,
    size_t output_buf_size
) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0 || output_buf == NULL || output_buf_size == 0) {
        return -11;
    }
    return qemu_runner_session_read(session_id, output_buf, output_buf_size);
}

int qemu_session_wait_output(unsigned long long session_id) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0) {
        return -11;
    }
    return qemu_runner_session_wait_output(session_id);
}

int qemu_session_close(unsigned long long session_id) {
    if (!g_initialized) {
        return -10;
    }
    if (session_id == 0) {
        return -11;
    }
    return qemu_runner_session_close(session_id);
}

int qemu_sandbox_shutdown(void) {
    g_initialized = 0;
    return 0;
}
