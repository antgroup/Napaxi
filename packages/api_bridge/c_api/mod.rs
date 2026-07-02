// Every `unsafe` block in this hand-written C ABI module must carry a
// `// SAFETY:` comment justifying the FFI contract it relies on. This is
// scoped to the module (not the crate) on purpose: the FRB-generated
// `frb_generated.rs` contains hundreds of machine-emitted unsafe blocks we
// do not hand-audit, so a crate-wide lint is not actionable there.
#![deny(clippy::undocumented_unsafe_blocks)]

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Arc;

use serde_json::{Value, json};

type StreamCallback = unsafe extern "C" fn(event_json: *const c_char, user_data: *mut c_void);
type ToolRequestCallback =
    unsafe extern "C" fn(request_json: *const c_char, user_data: *mut c_void);

fn cstr(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    // SAFETY: `ptr` is non-null (checked above) and, per the C ABI contract,
    // points to a caller-owned, NUL-terminated C string that outlives this
    // call. `to_string_lossy` copies out before we return, so we never retain
    // the borrowed pointer.
    unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned()
}

fn into_c_string(value: String) -> *mut c_char {
    let sanitized = value.replace('\0', "\\u0000");
    CString::new(sanitized).unwrap_or_default().into_raw()
}

fn payload(ptr: *const c_char) -> Result<Value, String> {
    let raw = cstr(ptr);
    if raw.trim().is_empty() {
        return Ok(Value::Object(Default::default()));
    }
    serde_json::from_str(&raw).map_err(|e| format!("invalid payload json: {e}"))
}

fn get_string(payload: &Value, key: &str) -> String {
    let keys: &[&str] = match key {
        "definition_json" => &["definition_json", "def_json"],
        "definition_id" => &["definition_id", "def_id"],
        _ => &[key],
    };
    keys.iter()
        .find_map(|candidate| payload.get(*candidate))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn get_opt_string(payload: &Value, key: &str) -> Option<String> {
    let keys: &[&str] = match key {
        "definition_id" => &["definition_id", "def_id"],
        _ => &[key],
    };
    keys.iter()
        .find_map(|candidate| payload.get(*candidate))
        .and_then(Value::as_str)
        .map(str::to_string)
}

fn get_bool(payload: &Value, key: &str) -> bool {
    payload.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn get_i64(payload: &Value, key: &str, default: i64) -> i64 {
    payload.get(key).and_then(Value::as_i64).unwrap_or(default)
}

fn get_i32(payload: &Value, key: &str, default: i32) -> i32 {
    get_i64(payload, key, default as i64)
        .try_into()
        .unwrap_or(default)
}

fn get_u32(payload: &Value, key: &str, default: u32) -> u32 {
    payload
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| value.try_into().ok())
        .unwrap_or(default)
}

fn get_usize(payload: &Value, key: &str) -> usize {
    payload
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| value.try_into().ok())
        .unwrap_or(0)
}

fn ok(value: Value) -> String {
    json!({ "ok": true, "value": value }).to_string()
}

fn ok_raw(raw: String) -> String {
    let value = serde_json::from_str(&raw).unwrap_or(Value::String(raw));
    ok(value)
}

fn err(code: &str, message: impl Into<String>) -> String {
    json!({ "ok": false, "error": { "code": code, "message": message.into() } }).to_string()
}

fn c_api_result(f: impl FnOnce() -> String) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(f))
        .unwrap_or_else(|_| err("panic", "Napaxi native bridge panicked"));
    into_c_string(result)
}

fn emit_stream_callback(callback: StreamCallback, event: String, user_data_addr: usize) {
    if let Ok(c_event) = CString::new(event) {
        // SAFETY: `callback` is the function pointer the host registered
        // through the C ABI; `c_event` is a valid NUL-terminated string that
        // lives until the end of this block (the callback must not retain it),
        // and `user_data_addr` is the opaque pointer the host handed us at
        // registration time, passed straight back unmodified.
        unsafe {
            callback(c_event.as_ptr(), user_data_addr as *mut c_void);
        }
    }
}

fn emit_tool_request_callback<T>(
    callback: ToolRequestCallback,
    user_data_addr: usize,
    request_id: u64,
    tool_name: &str,
    params_json: &str,
    context: Option<&T>,
) where
    T: serde::Serialize + ?Sized,
{
    let request = json!({
        "request_id": request_id,
        "tool_name": tool_name,
        "params_json": params_json,
        "context": context
            .and_then(|value| serde_json::to_value(value).ok())
            .unwrap_or(Value::Null),
    })
    .to_string();
    if let Ok(c_request) = CString::new(request) {
        // SAFETY: same contract as `emit_stream_callback` — `callback` is the
        // host-registered function pointer, `c_request` is a valid
        // NUL-terminated string borrowed only for the duration of the call,
        // and `user_data_addr` is the host's opaque pointer passed back as-is.
        unsafe {
            callback(c_request.as_ptr(), user_data_addr as *mut c_void);
        }
    }
}

/// Free a string returned by any Napaxi C ABI function.
///
/// # Safety
///
/// `value` must be either null or a pointer previously returned by an Napaxi
/// C ABI function and not yet freed. Passing any other pointer, or freeing the
/// same pointer twice, is undefined behaviour.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn napaxi_api_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: `value` is non-null (checked above) and, per this function's
        // safety contract, was produced by `into_c_string` via
        // `CString::into_raw`. Reconstructing the `CString` reclaims that exact
        // allocation so it is dropped here; the caller must not use `value`
        // again.
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_create_engine(
    config_json: *const c_char,
    platform_context_json: *const c_char,
) -> i64 {
    catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::engine::create_engine_handle(
            &cstr(config_json),
            &cstr(platform_context_json),
        )
        .unwrap_or(0)
    }))
    .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_update_config(handle: i64, config_json: *const c_char) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::engine::update_config_handle_typed(handle, &cstr(config_json)).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_get_config(handle: i64) -> *mut c_char {
    c_api_result(
        || match napaxi_core::api::engine::get_config_handle_typed(handle) {
            Ok(config) => ok_raw(config),
            Err(error) => err(error.code(), error.to_string()),
        },
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_ensure_agent_ready(handle: i64, config_json: *const c_char) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        if handle == 0 {
            return false;
        }
        let config = cstr(config_json);
        config.trim().is_empty()
            || napaxi_core::api::engine::update_config_handle_typed(handle, &config).is_ok()
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_dispose_engine(handle: i64) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::engine::dispose_engine_handle(handle);
    }));
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_update_custom_tools(handle: i64, tools_json: *const c_char) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::update_custom_tools_handle(handle, &cstr(tools_json)),
        )
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_resolve_tool_execution(
    request_id: u64,
    result_json: *const c_char,
    is_error: bool,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::tools::resolve_tool_execution(request_id, cstr(result_json), is_error)
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_register_tool_request_callback(
    callback: Option<ToolRequestCallback>,
    user_data: *mut c_void,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(callback) = callback else {
            return false;
        };
        let user_data_addr = user_data as usize;
        let dispatcher: napaxi_core::api::tools::ToolRequestDispatcher =
            Arc::new(move |request_id, tool_name, params_json, context| {
                emit_tool_request_callback(
                    callback,
                    user_data_addr,
                    request_id,
                    tool_name,
                    params_json,
                    context,
                );
            });
        napaxi_core::api::engine::set_tool_request_dispatcher(dispatcher);
        true
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_clear_tool_request_callback() {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let dispatcher: napaxi_core::api::tools::ToolRequestDispatcher = Arc::new(|_, _, _, _| {});
        napaxi_core::api::engine::set_tool_request_dispatcher(dispatcher);
    }));
}

#[unsafe(no_mangle)]
#[cfg(target_os = "ios")]
pub extern "C" fn napaxi_api_ios_ish_register_rootfs_archive_path(path: *const c_char) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::platform::register_ios_ish_rootfs_archive_path(&cstr(path));
    }));
}

#[unsafe(no_mangle)]
#[cfg(target_os = "ios")]
pub extern "C" fn napaxi_api_ios_ish_is_ready(files_dir: *const c_char) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        napaxi_core::api::platform::ios_ish_is_ready(&cstr(files_dir))
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_send_message(
    handle: i64,
    config_json: *const c_char,
    message: *const c_char,
    attachments_json: *const c_char,
    max_iterations: i32,
) -> *mut c_char {
    c_api_result(|| {
        ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::send_message_json_handle(
                handle,
                &cstr(config_json),
                &cstr(message),
                &cstr(attachments_json),
                max_iterations,
            ),
        ))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_send_to_session(
    handle: i64,
    config_json: *const c_char,
    agent_id: *const c_char,
    session_key_json: *const c_char,
    message: *const c_char,
    attachments_json: *const c_char,
    max_iterations: i32,
) -> *mut c_char {
    c_api_result(|| {
        ok_raw(crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::send_to_session_json_handle(
                handle,
                &cstr(config_json),
                &cstr(agent_id),
                &cstr(session_key_json),
                &cstr(message),
                &cstr(attachments_json),
                max_iterations,
            ),
        ))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_send_message_stream(
    handle: i64,
    config_json: *const c_char,
    message: *const c_char,
    attachments_json: *const c_char,
    max_iterations: i32,
    callback: Option<StreamCallback>,
    user_data: *mut c_void,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(callback) = callback else {
            return false;
        };
        let user_data_addr = user_data as usize;
        crate::bridge::init::runtime().block_on(napaxi_core::api::engine::stream_message_handle(
            handle,
            &cstr(config_json),
            &cstr(message),
            &cstr(attachments_json),
            max_iterations,
            |event| {
                emit_stream_callback(callback, event, user_data_addr);
            },
        ));
        true
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_send_to_session_stream(
    handle: i64,
    config_json: *const c_char,
    agent_id: *const c_char,
    session_key_json: *const c_char,
    message: *const c_char,
    attachments_json: *const c_char,
    max_iterations: i32,
    callback: Option<StreamCallback>,
    user_data: *mut c_void,
) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        let Some(callback) = callback else {
            return false;
        };
        let user_data_addr = user_data as usize;
        crate::bridge::init::runtime().block_on(
            napaxi_core::api::engine::stream_to_session_handle(
                handle,
                &cstr(config_json),
                &cstr(agent_id),
                &cstr(session_key_json),
                &cstr(message),
                &cstr(attachments_json),
                max_iterations,
                |event| {
                    emit_stream_callback(callback, event, user_data_addr);
                },
            ),
        );
        true
    }))
    .unwrap_or(false)
}

#[unsafe(no_mangle)]
pub extern "C" fn napaxi_api_call_json(
    handle: i64,
    namespace: *const c_char,
    method: *const c_char,
    payload_json: *const c_char,
) -> *mut c_char {
    c_api_result(|| {
        let namespace = cstr(namespace);
        let method = cstr(method);
        let payload = match payload(payload_json) {
            Ok(payload) => payload,
            Err(message) => return err("invalid_json", message),
        };
        dispatch(handle, &namespace, &method, &payload)
    })
}

#[cfg(target_os = "android")]
pub fn call_bridge_method(handle: i64, method: &str, payload_json: &str) -> String {
    let payload = match serde_json::from_str(payload_json) {
        Ok(payload) => payload,
        Err(error) => return err("invalid_json", format!("invalid payload json: {error}")),
    };
    let (namespace, method) = method.split_once('.').unwrap_or(("", method));
    let (namespace, method) = android_bridge_alias(namespace, method);
    dispatch(handle, namespace, method, &payload)
}

#[cfg(target_os = "android")]
fn android_bridge_alias<'a>(namespace: &'a str, method: &'a str) -> (&'a str, &'a str) {
    match (namespace, method) {
        ("tools", "platform_descriptors") => ("tools", "platform_tool_descriptors"),
        ("tools", "is_platform_tool") => ("tools", "is_platform_tool"),
        ("capability", "definitions") => ("capability", "list_definitions"),
        ("capability", "status") => ("capability", "list_status"),
        ("capability", "scenarios") => ("capability", "list_scenarios"),
        ("capability", "install_scenario") => ("capability", "install_scenario"),
        ("capability", "remove_scenario") => ("capability", "remove_scenario"),
        ("capability", "scenario_status") => ("capability", "list_scenario_status"),
        ("capability", "scenario") => ("capability", "resolve_scenario"),
        ("capability", "provider_id") => ("capability", "provider_capability_id"),
        ("capability", "agent_engine_id") => ("capability", "agent_engine_capability_id"),
        ("capability", "tool_id") => ("capability", "tool_capability_id"),
        ("automation", "create") => ("automation", "create_job"),
        ("automation", "update") => ("automation", "update_job"),
        ("automation", "delete") => ("automation", "delete_job"),
        ("automation", "list") => ("automation", "list_jobs"),
        ("automation", "get") => ("automation", "get_job"),
        ("automation", "run") => ("automation", "run_job"),
        ("automation", "runs") => ("automation", "list_runs"),
        ("agent_app", "register") => ("agent_app", "register_package"),
        ("agent_app", "list") => ("agent_app", "list_packages"),
        ("agent_app", "get") => ("agent_app", "get_package"),
        ("agent_app", "delete") => ("agent_app", "delete_package"),
        ("agent_app", "submit_result") => ("agent_app", "submit_action_result"),
        ("a2a", "agent_card") => ("a2a", "agent_card"),
        ("a2a", "create_peer_invite") => ("a2a", "create_peer_invite"),
        ("a2a", "accept_peer_invite") => ("a2a", "accept_peer_invite"),
        ("a2a", "list_peers") => ("a2a", "list_peers"),
        ("a2a", "delete_peer") => ("a2a", "delete_peer"),
        ("a2a", "open_peer_session") => ("a2a", "open_peer_session"),
        ("a2a", "list_peer_sessions") => ("a2a", "list_peer_sessions"),
        ("a2a", "create_task_message") => ("a2a", "create_task_message"),
        ("a2a", "record_peer_message") => ("a2a", "record_peer_message"),
        ("a2a", "record_delivery_status") => ("a2a", "record_delivery_status"),
        ("a2a", "list_peer_messages") => ("a2a", "list_peer_messages"),
        ("a2a", "list_delivery_records") => ("a2a", "list_delivery_records"),
        ("a2a", "accept_deep_link") => ("a2a", "accept_deep_link"),
        ("a2a", "run_task") => ("a2a", "run_task"),
        ("a2a", "list_tasks") => ("a2a", "list_tasks"),
        ("a2a", "get_task") => ("a2a", "get_task"),
        ("a2a", "build_result_link") => ("a2a", "build_result_link"),
        ("a2a", "record_result") => ("a2a", "record_result"),
        ("agent_defs", "create_agent") => ("agent_defs", "create_from_definition"),
        ("agent_defs", "import_md") => ("agent_defs", "import_markdown"),
        ("evolution", "pending") => ("evolution", "list_pending"),
        ("evolution", "runs") => ("evolution", "list_runs"),
        ("evolution", "diagnostics") => ("evolution", "list_diagnostics"),
        ("evolution", "reject") => ("evolution", "reject_pending"),
        ("evolution", "apply") => ("evolution", "apply_pending"),
        ("evolution", "consolidation_review") => ("evolution", "run_skill_consolidation_review"),
        ("group", "set_prompt") => ("group", "set_custom_prompt"),
        ("group", "clear") => ("group", "clear_history"),
        ("group", "export") => ("group", "export_state"),
        ("group", "import") => ("group", "import_state"),
        ("workspace", "read") => ("workspace", "read_file"),
        ("workspace", "write") => ("workspace", "write_file"),
        ("workspace", "append") => ("workspace", "append_file"),
        ("workspace", "delete") => ("workspace", "delete_file"),
        ("workspace", "list") => ("workspace", "list_files"),
        ("file_bridge", "save_attachments") => ("file_bridge", "save_message_attachments"),
        ("file_bridge", "load_attachments") => ("file_bridge", "load_thread_attachments"),
        ("file_bridge", "delete_attachments") => ("file_bridge", "delete_thread_attachments"),
        ("file_bridge", "detect_refs") => ("file_bridge", "detect_file_references"),
        ("file_bridge", "detect_refs_scoped") => ("file_bridge", "detect_file_references_scoped"),
        ("file_bridge", "delete_sandbox") => ("file_bridge", "delete_sandbox_file"),
        ("file_bridge", "delete_sandbox_scoped") => ("file_bridge", "delete_sandbox_file_scoped"),
        ("file_bridge", "list_fs") => ("file_bridge", "list_workspace_filesystem"),
        ("file_bridge", "list_fs_scoped") => ("file_bridge", "list_workspace_filesystem_scoped"),
        ("skill", "curator") => ("skill", "run_curator"),
        ("skill", "unpin") => ("skill", "pin"),
        _ => (namespace, method),
    }
}

mod a2a_dispatch;
mod channel_agent_dispatch;
mod channel_dispatch;
mod channel_qqbot_dispatch;
mod dispatch;
mod tools_dispatch;
use dispatch::dispatch;

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    unsafe extern "C" fn capture_json(value: *const c_char, user_data: *mut c_void) {
        assert!(!value.is_null());
        assert!(!user_data.is_null());
        // SAFETY: the tests always pass `&Mutex<Vec<String>>` as `user_data`
        // (via `&events as *const _ as *mut c_void`) and the referent outlives
        // the callback, so the cast and deref reconstruct the original borrow.
        let sink = unsafe { &*(user_data as *const Mutex<Vec<String>>) };
        // SAFETY: `value` is non-null (asserted above) and points to the
        // NUL-terminated string the bridge just emitted; we copy it out before
        // returning.
        let value = unsafe { CStr::from_ptr(value) }
            .to_string_lossy()
            .into_owned();
        sink.lock().unwrap().push(value);
    }

    #[test]
    fn returned_strings_are_owned_and_freeable() {
        let ptr = into_c_string(ok(json!("hello")));
        assert!(!ptr.is_null());
        // SAFETY: `ptr` was just produced by `into_c_string` and has not been
        // freed, so it satisfies `napaxi_api_string_free`'s contract.
        unsafe {
            napaxi_api_string_free(ptr);
        }
    }

    #[test]
    fn dispatch_reports_unknown_method() {
        let result = dispatch(0, "missing", "method", &json!({}));
        let parsed: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"]["code"], "unknown_method");
    }

    #[test]
    fn static_capability_dispatch_returns_envelope() {
        let result = dispatch(0, "capability", "list_definitions", &json!({}));
        let parsed: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(parsed["ok"], true);
        assert!(parsed["value"].is_array());
    }

    #[test]
    fn static_scenario_dispatch_returns_builtin_packs() {
        let result = dispatch(0, "capability", "list_scenarios", &json!({}));
        let parsed: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(parsed["ok"], true);
        assert!(parsed["value"].is_array());
        assert!(parsed["value"].as_array().unwrap().iter().any(|item| {
            item["id"] == napaxi_core::api::capability::MOBILE_DEVELOPMENT_SCENARIO_ID
        }));
    }

    #[test]
    fn static_qqbot_dispatch_exposes_core_protocol_helpers() {
        let endpoint = dispatch(
            0,
            "channel_qqbot",
            "outbound_endpoint_path",
            &json!({"peer_kind":"group","peer_id":"group openid"}),
        );
        let parsed: Value = serde_json::from_str(&endpoint).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"], "/v2/groups/group%20openid/messages");

        let fallback = dispatch(
            0,
            "channel_qqbot",
            "should_fallback_from_markdown",
            &json!({"status":400}),
        );
        let parsed: Value = serde_json::from_str(&fallback).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"], true);
    }

    #[test]
    fn static_scenario_resolution_dispatch_returns_activation_plan() {
        let result = dispatch(
            0,
            "capability",
            "resolve_scenario",
            &json!({
                "scenario_id": napaxi_core::api::capability::MOBILE_DEVELOPMENT_SCENARIO_ID,
            }),
        );
        let parsed: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"]["error"]["code"], "invalid_handle");
    }

    #[test]
    fn scenario_install_and_remove_dispatch_require_valid_handle() {
        let install = dispatch(
            0,
            "capability",
            "install_scenario",
            &json!({
                "pack_json": json!({
                    "id": "napaxi.scenario.field_ops",
                    "version": "1",
                    "label": "Field Ops",
                    "description": "Field operations scene",
                    "risk": "high",
                    "activation": "host_policy"
                }).to_string(),
            }),
        );
        let remove = dispatch(
            0,
            "capability",
            "remove_scenario",
            &json!({"scenario_id": "napaxi.scenario.field_ops"}),
        );
        let install: Value = serde_json::from_str(&install).unwrap();
        let remove: Value = serde_json::from_str(&remove).unwrap();
        assert_eq!(install["ok"], true);
        assert_eq!(install["value"]["error"]["code"], "invalid_handle");
        assert_eq!(remove["ok"], true);
        assert_eq!(remove["value"]["error"]["code"], "invalid_handle");
    }

    #[test]
    fn agent_engine_run_event_dispatch_returns_chat_event_envelope() {
        let request_json = json!({
            "run_id": "run-1",
            "event": {
                "type": "completed",
                "tool_call_count": 1
            }
        })
        .to_string();
        let result = dispatch(
            0,
            "agent_engine",
            "run_event",
            &json!({ "request_json": request_json }),
        );
        let parsed: Value = serde_json::from_str(&result).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"]["completed"], true);
        assert_eq!(parsed["value"]["event"]["type"], "run_completed");
        assert_eq!(parsed["value"]["event"]["run_id"], "run-1");
    }

    #[test]
    fn stream_callback_receives_error_event_for_invalid_handle() {
        let config = CString::new(r#"{"provider":"test","apiKey":"","model":"test"}"#).unwrap();
        let message = CString::new("hello").unwrap();
        let attachments = CString::new("[]").unwrap();
        let events = Mutex::new(Vec::<String>::new());

        let ok = napaxi_api_send_message_stream(
            0,
            config.as_ptr(),
            message.as_ptr(),
            attachments.as_ptr(),
            1,
            Some(capture_json),
            &events as *const _ as *mut c_void,
        );

        assert!(ok);
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 1);
        let parsed: Value = serde_json::from_str(&events[0]).unwrap();
        assert_eq!(parsed["type"], "error");
        assert!(
            parsed["message"]
                .as_str()
                .unwrap()
                .contains("engine handle")
        );
    }

    #[test]
    fn stream_callback_is_required() {
        let ok = napaxi_api_send_message_stream(
            0,
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            1,
            None,
            std::ptr::null_mut(),
        );

        assert!(!ok);
    }

    #[test]
    fn tool_request_callback_receives_json_shape_and_user_data() {
        #[derive(serde::Serialize)]
        struct TestContext {
            files_dir: &'static str,
            agent_id: &'static str,
        }

        let requests = Mutex::new(Vec::<String>::new());
        emit_tool_request_callback(
            capture_json,
            &requests as *const _ as usize,
            42,
            "lookup",
            r#"{"q":"napaxi"}"#,
            Some(&TestContext {
                files_dir: "/app/files",
                agent_id: "napaxi",
            }),
        );

        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        let parsed: Value = serde_json::from_str(&requests[0]).unwrap();
        assert_eq!(parsed["request_id"], 42);
        assert_eq!(parsed["tool_name"], "lookup");
        assert_eq!(parsed["params_json"], r#"{"q":"napaxi"}"#);
        assert_eq!(parsed["context"]["files_dir"], "/app/files");
        assert_eq!(parsed["context"]["agent_id"], "napaxi");
    }

    #[test]
    fn tool_request_callback_registration_rejects_missing_callback() {
        assert!(!napaxi_api_register_tool_request_callback(
            None,
            std::ptr::null_mut()
        ));
    }

    // The `napaxi_api_ios_ish_*` FFI entrypoints are `#[cfg(target_os = "ios")]`
    // only, so this test can only compile and run on an iOS target.
    #[test]
    #[cfg(target_os = "ios")]
    fn ios_ish_readiness_is_false_without_ios_runtime() {
        napaxi_api_ios_ish_register_rootfs_archive_path(std::ptr::null());
        assert!(!napaxi_api_ios_ish_is_ready(std::ptr::null()));
    }

    // ------------------------------------------------------------------
    // Wire-contract / round-trip tests
    //
    // These pin the exact JSON envelope and C-string marshalling shapes the
    // Dart and Kotlin/Swift adapters parse. A change here is a breaking
    // change to the FFI boundary and should be deliberate.
    // ------------------------------------------------------------------

    /// Reconstruct a Rust `String` from a pointer the bridge handed out,
    /// then free it — the exact lifecycle the host performs per call.
    fn roundtrip_owned(ptr: *mut c_char) -> String {
        assert!(!ptr.is_null());
        // SAFETY: `ptr` came from `into_c_string` (a `CString::into_raw`) and
        // has not been freed; we read it back and hand ownership to a fresh
        // `CString` which is dropped at the end of this function.
        let owned = unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned();
        // SAFETY: same `ptr`, still live and not yet freed elsewhere.
        unsafe { napaxi_api_string_free(ptr) };
        owned
    }

    #[test]
    fn ok_envelope_has_ok_true_and_value() {
        let out = ok(json!({ "n": 1 }));
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"]["n"], 1);
        assert!(parsed.get("error").is_none());
    }

    #[test]
    fn err_envelope_has_ok_false_code_and_message() {
        let out = err("invalid_handle", "engine handle 7 is not live");
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"]["code"], "invalid_handle");
        assert_eq!(parsed["error"]["message"], "engine handle 7 is not live");
        assert!(parsed.get("value").is_none());
    }

    #[test]
    fn ok_raw_parses_json_payloads_instead_of_double_encoding() {
        // A raw string that is itself valid JSON must be embedded as a value,
        // not re-stringified.
        let out = ok_raw(r#"{"items":[1,2,3]}"#.to_string());
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"]["items"][2], 3);
        assert!(parsed["value"].is_object());
    }

    #[test]
    fn ok_raw_falls_back_to_string_for_non_json_payloads() {
        let out = ok_raw("not json".to_string());
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["value"], "not json");
    }

    #[test]
    fn cstring_roundtrips_unicode_through_the_boundary() {
        let original = ok(json!({ "msg": "héllo 世界 🦀" }));
        let ptr = into_c_string(original.clone());
        let back = roundtrip_owned(ptr);
        assert_eq!(back, original);
        let parsed: Value = serde_json::from_str(&back).unwrap();
        assert_eq!(parsed["value"]["msg"], "héllo 世界 🦀");
    }

    #[test]
    fn into_c_string_sanitizes_interior_nul_instead_of_truncating() {
        // `CString::new` rejects interior NULs; the bridge must escape them so
        // the host receives the whole envelope rather than a silently
        // truncated (or empty) string.
        let with_nul = "before\0after".to_string();
        let ptr = into_c_string(with_nul);
        let back = roundtrip_owned(ptr);
        assert_eq!(back, "before\\u0000after");
    }

    #[test]
    fn cstr_treats_null_pointer_as_empty_string() {
        assert_eq!(cstr(std::ptr::null()), "");
    }

    #[test]
    fn payload_accepts_empty_pointer_as_empty_object() {
        let value = payload(std::ptr::null()).unwrap();
        assert!(value.is_object());
        assert_eq!(value.as_object().unwrap().len(), 0);
    }

    #[test]
    fn payload_rejects_malformed_json() {
        let raw = CString::new("{ not json").unwrap();
        let result = payload(raw.as_ptr());
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("invalid payload json"));
    }

    #[test]
    fn get_string_resolves_field_aliases() {
        // The dispatch layer accepts both the canonical key and the legacy
        // abbreviated key the older Dart/Kotlin call sites still send.
        let canonical = json!({ "definition_json": "A" });
        let legacy = json!({ "def_json": "B" });
        assert_eq!(get_string(&canonical, "definition_json"), "A");
        assert_eq!(get_string(&legacy, "definition_json"), "B");
        assert_eq!(get_string(&json!({ "def_id": "X" }), "definition_id"), "X");
        // Missing key yields empty string, never a panic.
        assert_eq!(get_string(&json!({}), "definition_json"), "");
    }

    #[test]
    fn numeric_getters_clamp_to_defaults_on_missing_or_wrong_type() {
        assert_eq!(get_i32(&json!({ "n": 5 }), "n", -1), 5);
        assert_eq!(get_i32(&json!({ "n": "oops" }), "n", -1), -1);
        assert_eq!(get_u32(&json!({ "n": -3 }), "n", 9), 9);
        assert_eq!(get_usize(&json!({ "n": 12 }), "n"), 12);
        assert!(get_bool(&json!({ "b": true }), "b"));
        assert!(!get_bool(&json!({}), "b"));
    }

    #[test]
    fn call_json_emits_invalid_json_envelope_for_bad_payload() {
        let namespace = CString::new("capability").unwrap();
        let method = CString::new("list_definitions").unwrap();
        let payload = CString::new("{ broken").unwrap();
        let ptr = napaxi_api_call_json(0, namespace.as_ptr(), method.as_ptr(), payload.as_ptr());
        let out = roundtrip_owned(ptr);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"]["code"], "invalid_json");
    }

    #[test]
    fn call_json_dispatches_static_method_and_returns_owned_envelope() {
        let namespace = CString::new("capability").unwrap();
        let method = CString::new("list_definitions").unwrap();
        let payload = CString::new("{}").unwrap();
        let ptr = napaxi_api_call_json(0, namespace.as_ptr(), method.as_ptr(), payload.as_ptr());
        let out = roundtrip_owned(ptr);
        let parsed: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed["ok"], true);
        assert!(parsed["value"].is_array());
    }

    #[test]
    fn stream_error_event_matches_dart_chat_event_contract() {
        // The Dart `ChatEvent.fromMap` switch keys on `type == "error"` and
        // reads `message`. Lock that shape so the two sides cannot drift.
        let config = CString::new(r#"{"provider":"test","apiKey":"","model":"test"}"#).unwrap();
        let message = CString::new("hello").unwrap();
        let attachments = CString::new("[]").unwrap();
        let events = Mutex::new(Vec::<String>::new());

        let ok = napaxi_api_send_message_stream(
            0,
            config.as_ptr(),
            message.as_ptr(),
            attachments.as_ptr(),
            1,
            Some(capture_json),
            &events as *const _ as *mut c_void,
        );

        assert!(ok);
        let events = events.lock().unwrap();
        let parsed: Value = serde_json::from_str(&events[0]).unwrap();
        assert_eq!(parsed["type"], "error");
        assert!(parsed["message"].is_string());
    }
}
