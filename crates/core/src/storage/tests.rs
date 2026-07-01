//! Integration tests covering bridge mapping, handle wrappers, attachments,
//! filesystem listing, and reference detection.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

use super::attachments::{
    load_thread_attachments_json, merge_attachments_into_history, save_message_attachments,
};
use super::bridge::{FileBridge, delete_sandbox_file, sandbox_to_real};
use super::filesystem::{
    detect_file_references_json, list_workspace_filesystem_json, workspace_size,
};
use super::handles::{
    delete_sandbox_file_handle, delete_sandbox_file_scoped_handle,
    delete_thread_attachments_handle, detect_file_references_json_handle,
    detect_file_references_json_scoped_handle, init_file_bridge_handle,
    init_file_bridge_scoped_handle, list_workspace_filesystem_json_handle,
    list_workspace_filesystem_json_scoped_handle, load_thread_attachments_json_handle,
    real_to_sandbox_handle, real_to_sandbox_scoped_handle, rootfs_dir_handle,
    sandbox_to_real_handle, sandbox_to_real_scoped_handle, save_message_attachments_handle,
    skills_dir_handle, workspace_dir_handle, workspace_dir_scoped_handle, workspace_size_handle,
    workspace_size_scoped_handle,
};

fn temp_dir(name: &str) -> PathBuf {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("napaxi_mobile_storage_{name}_{millis}"))
}

fn engine_handle(files_dir: &str) -> i64 {
    let config_json = serde_json::json!({
        "provider": "openai",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128
    })
    .to_string();
    let context_json = serde_json::json!({
        "platform": "test",
        "files_dir": files_dir,
        "native_library_dir": null
    })
    .to_string();
    crate::runtime::create_engine_handle(&config_json, &context_json).unwrap()
}

#[test]
fn maps_sandbox_paths_to_mobile_filesystem() {
    let dir = temp_dir("mapping");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);

    let workspace = bridge.sandbox_to_real("/workspace/out.png").unwrap();
    assert!(workspace.ends_with("linux-env/workspace/out.png"));
    assert_eq!(
        bridge.real_to_sandbox(&workspace).as_deref(),
        Some("/workspace/out.png")
    );

    let skill = bridge.sandbox_to_real("/skills/demo/SKILL.md").unwrap();
    assert!(skill.ends_with("prompt_skills/demo/SKILL.md"));
    assert_eq!(
        bridge.real_to_sandbox(&skill).as_deref(),
        Some("/skills/demo/SKILL.md")
    );

    let tmp = bridge.sandbox_to_real("/tmp/a.txt").unwrap();
    assert!(tmp.ends_with("linux-env/rootfs/tmp/a.txt"));
    assert_eq!(bridge.real_to_sandbox(&tmp).as_deref(), Some("/tmp/a.txt"));
}

#[test]
fn handle_wrappers_delegate_to_file_bridge_storage() {
    let dir = temp_dir("handle");
    let files_dir = dir.to_string_lossy().to_string();
    fs::create_dir_all(&dir).unwrap();
    let handle = engine_handle(&files_dir);

    assert!(!init_file_bridge_handle(0));
    assert!(init_file_bridge_handle(handle));
    assert!(workspace_dir_handle(handle).ends_with("linux-env/workspace"));
    assert!(rootfs_dir_handle(handle).contains("rootfs"));
    assert!(skills_dir_handle(handle).ends_with("prompt_skills"));

    let attachments = r#"[{"kind":"file","sandbox_path":"/workspace/note.txt"}]"#;
    assert!(save_message_attachments_handle(
        handle,
        "thread-a",
        0,
        attachments
    ));
    assert!(
        load_thread_attachments_json_handle(handle, "thread-a").contains("/workspace/note.txt")
    );
    assert!(delete_thread_attachments_handle(handle, "thread-a"));
    assert_eq!(load_thread_attachments_json_handle(0, "thread-a"), "{}");

    let workspace_root = workspace_dir_handle(handle);
    let workspace_file = Path::new(&workspace_root).join("note.txt");
    fs::create_dir_all(&workspace_root).unwrap();
    fs::write(&workspace_file, "hello through handle").unwrap();
    let sandbox_path = "/workspace/note.txt".to_string();
    let real_path = sandbox_to_real_handle(handle, &sandbox_path).unwrap();
    assert_eq!(
        real_to_sandbox_handle(handle, &real_path).as_deref(),
        Some("/workspace/note.txt")
    );
    assert!(workspace_size_handle(handle) > 0);
    assert!(
        list_workspace_filesystem_json_handle(handle, None, true).contains("/workspace/note.txt")
    );
    assert!(
        detect_file_references_json_handle(handle, "see /workspace/note.txt")
            .contains(r#""exists":true"#)
    );
    assert!(delete_sandbox_file_handle(handle, &sandbox_path));
    assert_eq!(workspace_size_handle(0), 0);
    assert!(sandbox_to_real_handle(0, "/workspace/a.txt").is_none());
    assert!(real_to_sandbox_handle(0, &real_path).is_none());
    assert_eq!(list_workspace_filesystem_json_handle(0, None, true), "[]");

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn scoped_handle_wrappers_map_workspace_without_moving_rootfs() {
    let dir = temp_dir("scoped_handle");
    let files_dir = dir.to_string_lossy().to_string();
    fs::create_dir_all(&dir).unwrap();
    let handle = engine_handle(&files_dir);

    assert!(init_file_bridge_scoped_handle(handle, "acct-a", "agent-a"));
    let workspace_dir = workspace_dir_scoped_handle(handle, "acct-a", "agent-a");
    assert!(
        workspace_dir.ends_with("napaxi_scopes/accounts/acct-a/agents/agent-a/linux-env/workspace")
    );

    let scoped_workspace_file = Path::new(&workspace_dir).join("note.txt");
    fs::create_dir_all(&workspace_dir).unwrap();
    fs::write(&scoped_workspace_file, "hello scoped bridge").unwrap();
    let sandbox_path = "/workspace/note.txt".to_string();
    let scoped_real =
        sandbox_to_real_scoped_handle(handle, "acct-a", "agent-a", &sandbox_path).unwrap();
    assert!(scoped_real.contains("napaxi_scopes/accounts/acct-a/agents/agent-a"));
    assert_eq!(
        real_to_sandbox_scoped_handle(handle, "acct-a", "agent-a", &scoped_real).as_deref(),
        Some("/workspace/note.txt")
    );
    assert!(
        list_workspace_filesystem_json_scoped_handle(handle, "acct-a", "agent-a", None, true,)
            .contains("/workspace/note.txt")
    );
    assert!(
        detect_file_references_json_scoped_handle(
            handle,
            "acct-a",
            "agent-a",
            "see /workspace/note.txt",
        )
        .contains(r#""exists":true"#)
    );
    assert_eq!(
        list_workspace_filesystem_json_handle(handle, None, true),
        "[]"
    );
    assert!(
        sandbox_to_real_scoped_handle(handle, "acct-a", "agent-a", "/tmp/a.txt")
            .unwrap()
            .ends_with("linux-env/rootfs/tmp/a.txt")
    );
    assert!(delete_sandbox_file_scoped_handle(
        handle,
        "acct-a",
        "agent-a",
        &sandbox_path,
    ));
    assert_eq!(workspace_size_scoped_handle(handle, "acct-a", "agent-a"), 0);

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn stores_and_merges_attachments_by_user_message_index() {
    let dir = temp_dir("attachments");
    let files_dir = dir.to_string_lossy().to_string();
    let thread_id = "thread-1";
    let attachments = r#"[{"kind":"image","mime_type":"image/png","filename":"a.png","sandbox_path":"/workspace/a.png","data_base64":"large-payload"}]"#;

    assert!(save_message_attachments(
        &files_dir,
        thread_id,
        1,
        attachments
    ));

    let mut messages = vec![
        serde_json::json!({"role":"user","content":"first"}),
        serde_json::json!({"role":"assistant","content":"reply"}),
        serde_json::json!({"role":"user","content":"second"}),
    ];
    merge_attachments_into_history(&files_dir, thread_id, &mut messages);

    assert!(messages[0].get("attachments").is_none());
    let restored = messages[2].get("attachments").and_then(Value::as_array);
    assert_eq!(restored.map(Vec::len), Some(1));
    assert_eq!(
        restored
            .and_then(|items| items.first())
            .and_then(|item| item.get("sandbox_path"))
            .and_then(Value::as_str),
        Some("/workspace/a.png")
    );
    assert!(
        restored
            .and_then(|items| items.first())
            .and_then(|item| item.get("data_base64"))
            .is_none(),
        "history metadata must not persist raw attachment payloads"
    );

    assert!(save_message_attachments(
        &files_dir,
        thread_id,
        1,
        r#"[{"kind":"image","mime_type":"image/png","filename":"a.png","data_base64":"replacement"}]"#
    ));
    let stored: Value =
        serde_json::from_str(&load_thread_attachments_json(&files_dir, thread_id)).unwrap();
    assert_eq!(
        stored["1"][0]["sandbox_path"].as_str(),
        Some("/workspace/a.png")
    );
    assert!(stored["1"][0].get("data_base64").is_none());

    let _ = fs::remove_dir_all(dir);
}

#[test]
fn stores_local_attachment_path_without_requiring_sandbox_path() {
    let dir = temp_dir("local_attachments");
    let files_dir = dir.to_string_lossy().to_string();
    let thread_id = "thread-local";
    let attachments = r#"[{"kind":"document","mime_type":"text/plain","filename":"notes.txt","path":"/local/demo/notes.txt","data_base64":"payload"}]"#;

    assert!(save_message_attachments(
        &files_dir,
        thread_id,
        0,
        attachments
    ));

    let stored: Value =
        serde_json::from_str(&load_thread_attachments_json(&files_dir, thread_id)).unwrap();
    assert_eq!(
        stored["0"][0]["path"].as_str(),
        Some("/local/demo/notes.txt")
    );
    assert!(stored["0"][0].get("sandbox_path").is_none());
    assert!(stored["0"][0].get("data_base64").is_none());

    let mut messages = vec![serde_json::json!({"role":"user","content":"file"})];
    merge_attachments_into_history(&files_dir, thread_id, &mut messages);
    assert_eq!(
        messages[0]["attachments"][0]["path"].as_str(),
        Some("/local/demo/notes.txt")
    );

    let _ = fs::remove_dir_all(dir);
}

#[test]
fn imports_lists_detects_sizes_and_deletes_workspace_files() {
    let dir = temp_dir("file_bridge");
    let files_dir = dir.to_string_lossy().to_string();
    let workspace_root = Path::new(&files_dir).join("linux-env/workspace");
    fs::create_dir_all(&workspace_root).unwrap();
    let real_path = workspace_root.join("note.txt");
    fs::write(&real_path, "hello bridge").unwrap();
    let sandbox_path = "/workspace/note.txt".to_string();

    let real_path = sandbox_to_real(&files_dir, &sandbox_path).unwrap();
    assert_eq!(fs::read_to_string(&real_path).unwrap(), "hello bridge");
    assert_eq!(workspace_size(&files_dir), "hello bridge".len() as u64);

    let listing: Value =
        serde_json::from_str(&list_workspace_filesystem_json(&files_dir, None, true)).unwrap();
    let entries = listing.as_array().unwrap();
    assert!(entries.iter().any(|entry| {
        entry.get("sandbox_path").and_then(Value::as_str) == Some("/workspace/note.txt")
            && entry.get("mime_type").and_then(Value::as_str) == Some("text/plain")
            && entry.get("size_bytes").and_then(Value::as_u64) == Some("hello bridge".len() as u64)
    }));

    let refs: Value = serde_json::from_str(&detect_file_references_json(
        &files_dir,
        "Please inspect `/workspace/note.txt` and /workspace/missing.md.",
    ))
    .unwrap();
    let refs = refs.as_array().unwrap();
    assert!(refs.iter().any(|entry| {
        entry.get("sandbox_path").and_then(Value::as_str) == Some("/workspace/note.txt")
            && entry.get("exists").and_then(Value::as_bool) == Some(true)
    }));
    assert!(refs.iter().any(|entry| {
        entry.get("sandbox_path").and_then(Value::as_str) == Some("/workspace/missing.md")
            && entry.get("exists").and_then(Value::as_bool) == Some(false)
    }));

    assert!(delete_sandbox_file(&files_dir, &sandbox_path));
    assert!(!Path::new(&real_path).exists());
    assert_eq!(workspace_size(&files_dir), 0);

    let _ = fs::remove_dir_all(dir);
}

#[test]
fn save_message_attachments_inner_returns_decode_error_on_bad_json() {
    use super::attachments::save_message_attachments_inner;
    let dir = temp_dir("inner_decode");
    fs::create_dir_all(&dir).unwrap();
    let files_dir = dir.display().to_string();

    let err = save_message_attachments_inner(&files_dir, "t-1", 0, "not json").unwrap_err();
    assert_eq!(err.code(), "storage_decode");

    let _ = fs::remove_dir_all(dir);
}

#[test]
fn delete_thread_attachments_inner_treats_missing_file_as_ok() {
    use super::attachments::delete_thread_attachments_inner;
    let dir = temp_dir("inner_delete_missing");
    fs::create_dir_all(&dir).unwrap();
    let files_dir = dir.display().to_string();
    assert!(delete_thread_attachments_inner(&files_dir, "absent").is_ok());
    let _ = fs::remove_dir_all(dir);
}
