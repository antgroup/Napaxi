#ifndef NAPAXI_SPM_ISH_BRIDGE_H
#define NAPAXI_SPM_ISH_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int ish_init(const char *rootfs_path);
int ish_exec(const char *command,
             const char *workdir,
             char *stdout_buf, size_t stdout_buf_size,
             char *stderr_buf, size_t stderr_buf_size,
             int timeout_ms);
int ish_is_initialized(void);
int ish_import_rootfs(const char *archive_path, const char *fs_path);
int ish_mount_host(const char *host_path, const char *mount_point);
void ish_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
