#ifndef NAPAXI_API_BRIDGE_H
#define NAPAXI_API_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*NapaxiStreamCallback)(const char *event_json, void *user_data);
typedef void (*NapaxiToolRequestCallback)(const char *request_json, void *user_data);

void napaxi_api_string_free(char *value);

int64_t napaxi_api_create_engine(const char *config_json, const char *platform_context_json);
bool napaxi_api_update_config(int64_t handle, const char *config_json);
char *napaxi_api_get_config(int64_t handle);
bool napaxi_api_ensure_agent_ready(int64_t handle, const char *config_json);
void napaxi_api_dispose_engine(int64_t handle);

bool napaxi_api_update_custom_tools(int64_t handle, const char *tools_json);
bool napaxi_api_resolve_tool_execution(uint64_t request_id, const char *result_json, bool is_error);
bool napaxi_api_register_tool_request_callback(NapaxiToolRequestCallback callback, void *user_data);
void napaxi_api_clear_tool_request_callback(void);

char *napaxi_api_send_message(
    int64_t handle,
    const char *config_json,
    const char *message,
    const char *attachments_json,
    int32_t max_iterations
);

char *napaxi_api_send_to_session(
    int64_t handle,
    const char *config_json,
    const char *agent_id,
    const char *session_key_json,
    const char *message,
    const char *attachments_json,
    int32_t max_iterations
);

bool napaxi_api_send_message_stream(
    int64_t handle,
    const char *config_json,
    const char *message,
    const char *attachments_json,
    int32_t max_iterations,
    NapaxiStreamCallback callback,
    void *user_data
);

bool napaxi_api_send_to_session_stream(
    int64_t handle,
    const char *config_json,
    const char *agent_id,
    const char *session_key_json,
    const char *message,
    const char *attachments_json,
    int32_t max_iterations,
    NapaxiStreamCallback callback,
    void *user_data
);

char *napaxi_api_call_json(
    int64_t handle,
    const char *namespace_name,
    const char *method_name,
    const char *payload_json
);

void napaxi_api_ios_ish_register_rootfs_archive_path(const char *path);
bool napaxi_api_ios_ish_is_ready(const char *files_dir);

/* Legacy aliases — prefer the napaxi_api_-prefixed versions above.
 * These are retained for backward compatibility with earlier integrations
 * and will be removed in a future major version. */
void napaxi_ios_ish_register_rootfs_archive_path(const char *path);
char *napaxi_version(void);
void napaxi_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
