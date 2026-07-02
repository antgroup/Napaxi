#ifndef ISH_BRIDGE_H
#define ISH_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the iSH kernel with the given rootfs path.
// rootfs_path should point to the directory containing "data/" and "meta.db".
// Returns 0 on success, negative on error.
int ish_init(const char *rootfs_path);

// Execute a command in the iSH Linux environment.
// command: the shell command string (run via /bin/sh -c)
// workdir: working directory for the command (NULL or "" for default)
// stdout_buf/stderr_buf: buffers to receive output
// timeout_ms: timeout in milliseconds (0 = no timeout)
// Returns the exit code of the command, or negative on error.
int ish_exec(const char *command,
             const char *workdir,
             char *stdout_buf, size_t stdout_buf_size,
             char *stderr_buf, size_t stderr_buf_size,
             int timeout_ms);

// Check if the iSH kernel has been initialized.
int ish_is_initialized(void);

// Import a raw Alpine rootfs tar.gz into fakefs format.
// archive_path: path to the raw .tar.gz file
// fs_path: destination directory (will contain data/ and meta.db after import)
// Returns 0 on success, negative on error.
int ish_import_rootfs(const char *archive_path, const char *fs_path);

// Mount a host (iOS) directory into the iSH filesystem.
// host_path: real iOS filesystem path (e.g. ".../napaxi_data/prompt_skills")
// mount_point: path inside Alpine (e.g. "/skills")
// The iSH kernel must be initialized before calling this.
// Returns 0 on success, negative on error.
int ish_mount_host(const char *host_path, const char *mount_point);

// Shutdown the iSH kernel.
void ish_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif // ISH_BRIDGE_H
