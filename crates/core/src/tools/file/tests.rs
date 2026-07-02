//! File tool integration tests covering descriptors, sandbox policy,
//! read_file, and apply_patch (add / update / delete + fuzzy matching).

use std::fs;
use std::path::PathBuf;

use crate::storage::FileBridge;

use super::descriptors::{APPLY_PATCH_TOOL_NAME, READ_FILE_TOOL_NAME, read_file_descriptor};
use super::execute;

fn temp_dir(name: &str) -> PathBuf {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("napaxi_apply_patch_{name}_{millis}"))
}

fn run(files_dir: &str, tool: &str, params: serde_json::Value) -> serde_json::Value {
    let raw = execute(files_dir, files_dir, tool, params, None)
        .unwrap_or_else(|err| panic!("{tool} unexpectedly failed: {err}"));
    serde_json::from_str(&raw.output).expect("tool output must be JSON")
}

fn run_err(files_dir: &str, tool: &str, params: serde_json::Value) -> String {
    match execute(files_dir, files_dir, tool, params, None) {
        Ok(_) => panic!("{tool} unexpectedly succeeded"),
        Err(err) => err,
    }
}

fn error_payload(err: &str) -> serde_json::Value {
    serde_json::from_str(err).expect("apply_patch errors must be JSON payloads")
}

#[test]
fn descriptor_exposes_read_file_tool() {
    let descriptor = read_file_descriptor();
    assert_eq!(descriptor.name, READ_FILE_TOOL_NAME);
    assert!(
        descriptor.parameters["required"]
            .as_array()
            .unwrap()
            .iter()
            .any(|value| value.as_str() == Some("path"))
    );
}

#[test]
fn reads_workspace_and_rootfs_files() {
    let dir = temp_dir("read");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::create_dir_all(bridge.rootfs_dir().join("tmp")).unwrap();
    fs::write(bridge.workspace_dir().join("notes.md"), "hello workspace").unwrap();
    fs::write(
        bridge.rootfs_dir().join("tmp").join("system.txt"),
        "hello rootfs",
    )
    .unwrap();

    let workspace = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/workspace/notes.md"}),
    );
    assert_eq!(workspace["content"].as_str(), Some("hello workspace"));
    assert_eq!(workspace["path"].as_str(), Some("/workspace/notes.md"));

    let rootfs = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/tmp/system.txt"}),
    );
    assert_eq!(rootfs["content"].as_str(), Some("hello rootfs"));
    assert_eq!(rootfs["path"].as_str(), Some("/tmp/system.txt"));
}

#[test]
fn rejects_path_traversal_and_directories() {
    let dir = temp_dir("reject");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("note.txt"), "hello").unwrap();

    assert!(
        execute(
            &files_dir,
            &files_dir,
            READ_FILE_TOOL_NAME,
            serde_json::json!({"path":"/workspace/../note.txt"}),
            None,
        )
        .is_err()
    );
    assert!(
        execute(
            &files_dir,
            &files_dir,
            READ_FILE_TOOL_NAME,
            serde_json::json!({"path":"/workspace"}),
            None,
        )
        .is_err()
    );
}

#[test]
fn add_and_update_via_apply_patch() {
    let dir = temp_dir("add_update");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();

    let created = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /workspace/notes/today.md\n+line one\n*** End Patch"
        }),
    );
    assert_eq!(created["status"].as_str(), Some("patched"));
    assert_eq!(created["files"][0]["action"].as_str(), Some("added"));
    assert_eq!(
        created["files"][0]["path"].as_str(),
        Some("/workspace/notes/today.md")
    );
    assert_eq!(
        fs::read_to_string(bridge.workspace_dir().join("notes/today.md")).unwrap(),
        "line one"
    );

    fs::write(
        bridge.workspace_dir().join("plan.md"),
        "alpha\nbeta\ngamma\n",
    )
    .unwrap();

    let updated = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n alpha\n-beta\n+bravo\n gamma\n*** End Patch"
        }),
    );
    assert_eq!(updated["files"][0]["action"].as_str(), Some("updated"));
    assert_eq!(updated["files"][0]["added_lines"].as_u64(), Some(1));
    assert_eq!(updated["files"][0]["removed_lines"].as_u64(), Some(1));
    assert_eq!(
        fs::read_to_string(bridge.workspace_dir().join("plan.md")).unwrap(),
        "alpha\nbravo\ngamma\n"
    );
}

#[test]
fn delete_file_via_apply_patch() {
    let dir = temp_dir("delete");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "alpha\nbeta\n").unwrap();

    let deleted = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Delete File: /workspace/plan.md\n*** End Patch"
        }),
    );
    assert_eq!(deleted["files"][0]["action"].as_str(), Some("deleted"));
    assert!(!bridge.workspace_dir().join("plan.md").exists());
}

#[test]
fn delete_then_add_overwrites_existing_file() {
    let dir = temp_dir("overwrite");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "old\n").unwrap();

    let result = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Delete File: /workspace/plan.md\n*** Add File: /workspace/plan.md\n+new content\n*** End Patch"
        }),
    );
    assert_eq!(result["file_count"].as_u64(), Some(2));
    assert_eq!(result["files"][0]["action"].as_str(), Some("deleted"));
    assert_eq!(result["files"][1]["action"].as_str(), Some("added"));
    assert_eq!(
        fs::read_to_string(bridge.workspace_dir().join("plan.md")).unwrap(),
        "new content"
    );
}

#[test]
fn fuzzy_match_tolerates_trailing_whitespace() {
    let dir = temp_dir("fuzzy_rstrip");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(
        bridge.workspace_dir().join("plan.md"),
        "alpha   \nbeta\t\ngamma\n",
    )
    .unwrap();

    let updated = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n alpha\n-beta\n+bravo\n gamma\n*** End Patch"
        }),
    );
    assert_eq!(updated["files"][0]["action"].as_str(), Some("updated"));
    let actual = fs::read_to_string(bridge.workspace_dir().join("plan.md")).unwrap();
    assert!(actual.contains("bravo"));
}

#[test]
fn fuzzy_match_tolerates_unicode_quotes() {
    let dir = temp_dir("fuzzy_unicode");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(
        bridge.workspace_dir().join("code.rs"),
        "fn greet() {\n    println!(\u{201C}hi\u{201D});\n}\n",
    )
    .unwrap();

    let updated = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/code.rs\n@@\n fn greet() {\n-    println!(\"hi\");\n+    println!(\"hello\");\n }\n*** End Patch"
        }),
    );
    assert_eq!(updated["files"][0]["action"].as_str(), Some("updated"));
    assert!(
        fs::read_to_string(bridge.workspace_dir().join("code.rs"))
            .unwrap()
            .contains("hello")
    );
}

#[test]
fn multiple_hunks_apply_in_document_order() {
    let dir = temp_dir("multi_hunk");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(
        bridge.workspace_dir().join("plan.md"),
        "alpha\nbeta\ngamma\ndelta\nepsilon\n",
    )
    .unwrap();

    let updated = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n alpha\n-beta\n+B\n gamma\n@@\n delta\n-epsilon\n+E\n*** End Patch"
        }),
    );
    assert_eq!(updated["files"][0]["added_lines"].as_u64(), Some(2));
    assert_eq!(updated["files"][0]["removed_lines"].as_u64(), Some(2));
    assert_eq!(
        fs::read_to_string(bridge.workspace_dir().join("plan.md")).unwrap(),
        "alpha\nB\ngamma\ndelta\nE\n"
    );
}

#[test]
fn ambiguous_context_returns_typed_error_with_hint() {
    let dir = temp_dir("ambiguous");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "dup\nother\ndup\n").unwrap();

    let err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n-dup\n+changed\n*** End Patch"
        }),
    );
    let payload = error_payload(&err);
    assert_eq!(
        payload["error_kind"].as_str(),
        Some("hunk_context_ambiguous")
    );
    assert!(payload["hint"].is_string());
}

#[test]
fn missing_context_returns_typed_error_with_excerpt() {
    let dir = temp_dir("missing_context");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "alpha\nbeta\n").unwrap();

    let err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n-nope\n+changed\n*** End Patch"
        }),
    );
    let payload = error_payload(&err);
    assert_eq!(
        payload["error_kind"].as_str(),
        Some("hunk_context_not_found")
    );
    assert!(payload["pattern_excerpt"].is_array());
}

#[test]
fn add_existing_file_returns_typed_error() {
    let dir = temp_dir("add_existing");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "alpha\n").unwrap();

    let err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /workspace/plan.md\n+other\n*** End Patch"
        }),
    );
    let payload = error_payload(&err);
    assert_eq!(payload["error_kind"].as_str(), Some("add_file_exists"));
    assert!(payload["hint"].as_str().unwrap().contains("Update File"));
    let fix = payload["example_fix"]
        .as_str()
        .expect("example_fix present");
    assert!(fix.contains("*** Begin Patch"));
    assert!(fix.contains("*** Update File: /workspace/plan.md"));
}

#[test]
fn apply_patch_rejects_unsafe_paths_and_skills() {
    let dir = temp_dir("write_reject");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::create_dir_all(bridge.skills_dir()).unwrap();

    let skills_err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /skills/demo/SKILL.md\n+nope\n*** End Patch"
        }),
    );
    assert_eq!(
        error_payload(&skills_err)["error_kind"].as_str(),
        Some("invalid_path")
    );

    let traversal_err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /workspace/../escape.txt\n+nope\n*** End Patch"
        }),
    );
    assert_eq!(
        error_payload(&traversal_err)["error_kind"].as_str(),
        Some("invalid_path")
    );

    let not_sandbox_err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /not-a-sandbox/host.txt\n+nope\n*** End Patch"
        }),
    );
    assert_eq!(
        error_payload(&not_sandbox_err)["error_kind"].as_str(),
        Some("invalid_path")
    );
}

#[test]
fn missing_envelope_returns_typed_error() {
    let dir = temp_dir("missing_envelope");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();

    let err = run_err(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Update File: /workspace/plan.md\n@@\n-foo\n+bar\n*** End Patch"
        }),
    );
    let payload = error_payload(&err);
    assert_eq!(
        payload["error_kind"].as_str(),
        Some("envelope_missing_begin")
    );
    let fix = payload["example_fix"]
        .as_str()
        .expect("example_fix present");
    assert!(fix.starts_with("*** Begin Patch"));
    assert!(fix.contains("*** End Patch"));
}

#[test]
fn streaming_progress_chunk_uses_apply_patch_progress_type() {
    use crate::tool_loop::InternalToolProgressEvent;
    use tokio::sync::mpsc;

    let dir = temp_dir("progress_chunk");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(bridge.workspace_dir().join("plan.md"), "alpha\nbeta\n").unwrap();

    let (tx, mut rx) = mpsc::unbounded_channel::<InternalToolProgressEvent>();
    super::execute(
        &files_dir,
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Update File: /workspace/plan.md\n@@\n alpha\n-beta\n+bravo\n*** End Patch"
        }),
        Some(tx),
    )
    .expect("apply_patch must succeed");

    let event = rx.try_recv().expect("at least one progress event");
    assert_eq!(event.stream, "patch");
    let payload: serde_json::Value =
        serde_json::from_str(&event.content).expect("progress payload is JSON");
    assert_eq!(payload["type"].as_str(), Some("apply_patch_progress"));
    assert_eq!(payload["path"].as_str(), Some("/workspace/plan.md"));
    assert_eq!(payload["action"].as_str(), Some("updated"));
}
