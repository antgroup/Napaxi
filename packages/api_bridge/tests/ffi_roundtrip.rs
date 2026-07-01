//! End-to-end FFI lifecycle tests.
//!
//! The in-crate `c_api` unit tests pin envelope shapes and C-string
//! marshalling, but they all dispatch against a dead handle (`0`). They never
//! prove that a *live* engine can be created and driven across the C ABI and
//! torn down — which is exactly the `core -> bridge -> host` seam most likely
//! to break silently.
//!
//! This integration test links `napaxi_api_bridge` as a downstream crate and
//! drives the real C ABI entry points (`napaxi_api_create_engine`,
//! `napaxi_api_call_json`, `napaxi_api_get_config`, `napaxi_api_dispose_engine`,
//! `napaxi_api_string_free`) with the same raw-pointer signatures a host binds
//! to. (Rust strips a dependency's `#[no_mangle]` symbols from the rlib, so the
//! functions are reached by path rather than re-declared `extern` — the
//! marshalling code under test is identical either way.) Everything is
//! hermetic: a `tempdir` backs the workspace and no network or live LLM
//! provider is touched (all assertions use offline `workspace`/`config`
//! dispatch paths).

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use napaxi_api_bridge::c_api::{
    napaxi_api_call_json, napaxi_api_create_engine, napaxi_api_dispose_engine, napaxi_api_get_config,
    napaxi_api_string_free,
};
use serde_json::{Value, json};

/// Owned C string for passing into the ABI. Held by the caller for the
/// duration of the call so the borrowed pointer stays valid.
fn c(value: &str) -> CString {
    CString::new(value).expect("fixture string has no interior NUL")
}

/// Read back and free a string the bridge handed out, parsing it as the JSON
/// envelope the host decodes. This is the full per-call host lifecycle.
fn take_envelope(ptr: *mut c_char) -> Value {
    assert!(!ptr.is_null(), "bridge returned a null string pointer");
    // SAFETY: `ptr` was just returned by an Napaxi C ABI function and has not
    // been freed; we copy the contents out before handing the same pointer to
    // `napaxi_api_string_free`, which reclaims that exact allocation.
    let owned = unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    // SAFETY: same `ptr`, still live and not yet freed.
    unsafe { napaxi_api_string_free(ptr) };
    serde_json::from_str(&owned).expect("bridge returned non-JSON over the C ABI")
}

/// Drive `napaxi_api_call_json` and return the decoded envelope.
fn call(handle: i64, namespace: &str, method: &str, payload: &Value) -> Value {
    let ns = c(namespace);
    let m = c(method);
    let p = c(&payload.to_string());
    // The locals own the NUL-terminated buffers and outlive the call; the
    // returned pointer is consumed and freed by `take_envelope`.
    let ptr = napaxi_api_call_json(handle, ns.as_ptr(), m.as_ptr(), p.as_ptr());
    take_envelope(ptr)
}

/// Minimal offline config. `provider`/`api_key`/`model`/`system_prompt`/
/// `max_tokens` are the only non-defaulted `PlatformLlmConfig` fields; no
/// network is reached because the test never sends a chat turn.
fn config_json() -> String {
    json!({
        "provider": "test",
        "api_key": "",
        "model": "test-model",
        "system_prompt": "Host prompt.",
        "max_tokens": 1000
    })
    .to_string()
}

/// Create a live engine handle backed by a temp `files_dir`. The caller owns
/// the tempdir guard and must drop it after disposing the handle.
fn live_engine(files_dir: &str) -> i64 {
    let config = c(&config_json());
    let context = c(&json!({ "files_dir": files_dir }).to_string());
    // The locals own the NUL-terminated buffers and outlive the call.
    let handle = napaxi_api_create_engine(config.as_ptr(), context.as_ptr());
    assert_ne!(handle, 0, "create_engine returned a null handle");
    handle
}

#[test]
fn live_engine_workspace_write_read_list_roundtrip_then_dispose() {
    let tmp = tempfile::tempdir().expect("create tempdir");
    let files_dir = tmp.path().to_str().expect("utf-8 tempdir path");

    let handle = live_engine(files_dir);

    // Write a workspace memory file through the dispatch layer.
    let wrote = call(
        handle,
        "workspace",
        "write_file",
        &json!({
            "account_id": "app",
            "agent_id": "napaxi",
            "path": "notes/hello.md",
            "content": "# Hello\n\nfrom the FFI boundary"
        }),
    );
    assert_eq!(wrote["ok"], true, "write envelope: {wrote}");
    assert_eq!(wrote["value"], true, "write should report success");

    // Read it straight back; content must survive the round-trip verbatim.
    let read = call(
        handle,
        "workspace",
        "read_file",
        &json!({
            "account_id": "app",
            "agent_id": "napaxi",
            "path": "notes/hello.md"
        }),
    );
    assert_eq!(read["ok"], true, "read envelope: {read}");
    assert_eq!(
        read["value"]["content"], "# Hello\n\nfrom the FFI boundary",
        "content drifted across the boundary"
    );
    assert_eq!(read["value"]["path"], "notes/hello.md");

    // The written file must appear in the directory listing.
    let listed = call(
        handle,
        "workspace",
        "list_files",
        &json!({
            "account_id": "app",
            "agent_id": "napaxi",
            "directory": "notes"
        }),
    );
    assert_eq!(listed["ok"], true, "list envelope: {listed}");
    let entries = listed["value"]
        .as_array()
        .expect("list_files should return an array");
    let names: Vec<&str> = entries
        .iter()
        .filter_map(|e| e["path"].as_str().or_else(|| e["name"].as_str()))
        .collect();
    assert!(
        names.iter().any(|n| n.contains("hello.md")),
        "written file not in listing: {listed}"
    );

    // Dispose the engine. The handle is consumed here and must never be used
    // again — reading through a disposed handle is use-after-free per the
    // runtime's documented safety contract, so this test does not probe it.
    // The safe rejection of a never-live handle is covered separately by
    // `call_json_on_dead_handle_reports_invalid_handle_without_crashing`.
    napaxi_api_dispose_engine(handle);

    drop(tmp);
}

#[test]
fn live_engine_get_config_returns_persisted_config() {
    let tmp = tempfile::tempdir().expect("create tempdir");
    let files_dir = tmp.path().to_str().expect("utf-8 tempdir path");

    let handle = live_engine(files_dir);

    let envelope = take_envelope(napaxi_api_get_config(handle));
    assert_eq!(envelope["ok"], true, "get_config envelope: {envelope}");
    assert_eq!(
        envelope["value"]["provider"], "test",
        "config did not round-trip through the engine: {envelope}"
    );
    assert_eq!(envelope["value"]["model"], "test-model");

    // `handle` is consumed here and not reused.
    napaxi_api_dispose_engine(handle);
    drop(tmp);
}

#[test]
fn create_engine_rejects_malformed_config_json() {
    let bad_config = c("{ not valid json");
    let context = c(&json!({ "files_dir": "/tmp/ignored" }).to_string());
    // The locals own the NUL-terminated buffers and outlive the call.
    let handle = napaxi_api_create_engine(bad_config.as_ptr(), context.as_ptr());
    assert_eq!(
        handle, 0,
        "malformed config must yield a null handle, not a live engine"
    );
}

#[test]
fn call_json_on_dead_handle_reports_invalid_handle_without_crashing() {
    // No engine is ever created. The bridge must degrade to its invalid-handle
    // marker, proving the dead-handle path is panic-free across the ABI.
    let read = call(
        0,
        "workspace",
        "read_file",
        &json!({ "account_id": "app", "agent_id": "napaxi", "path": "notes/x.md" }),
    );
    assert_eq!(read["ok"], true);
    assert!(
        read["value"]
            .get("error")
            .and_then(Value::as_str)
            .is_some_and(|e| e.contains("invalid engine handle")),
        "dead handle should yield the invalid-handle marker, got: {read}"
    );
}
