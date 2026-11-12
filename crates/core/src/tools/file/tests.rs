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

// ---------------------------------------------------------------------------
// exec diagnostic-candidate bound audit baseline (DIMA #2026110800120444016,
// OpenClaw #194790). Audit conclusion: Napaxi has no strsim/levenshtein
// diagnostic-candidate module, and read_file returns `file not found: <path>`
// directly on a missing path WITHOUT listing or sorting sibling directory
// entries — so it cannot reproduce the OpenClaw `missing-file read →
// retain+sort large dir` stall. These tests pin that invariant so a future
// diagnostic-candidate path cannot silently reintroduce it.
// ---------------------------------------------------------------------------

#[test]
fn read_file_missing_returns_not_found_without_listing_directory() {
    let dir = temp_dir("missing_nolist");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    // Populate the workspace dir with several sibling files so that an
    // OpenClaw-#194790-style "did you mean" candidate path would have material
    // to surface — but read_file must return only the canonical not-found
    // message, never the sibling names.
    let siblings = ["alpha.txt", "beta.txt", "gamma.rs", "delta_long_name.txt"];
    for name in &siblings {
        fs::write(bridge.workspace_dir().join(name), "noise").unwrap();
    }
    let missing = run_err(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path": "/workspace/does_not_exist.txt"}),
    );
    assert!(
        missing.contains("does_not_exist.txt"),
        "missing-file error must name the requested path; got: {missing}"
    );
    for name in &siblings {
        assert!(
            !missing.contains(name),
            "missing-file error must not list sibling directory entries (no retain+sort), \
             but `{name}` appeared in: {missing}"
        );
    }
}

#[test]
fn read_file_truncates_at_max_bytes_bound() {
    let dir = temp_dir("maxbytes_bound");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    // File larger than max_bytes; read_file must bound output via take(max_bytes)
    // and report truncation rather than accumulating the whole file.
    let big: Vec<u8> = (0u8..255).cycle().take(4096).collect();
    fs::write(bridge.workspace_dir().join("big.bin"), &big).unwrap();
    let out = serde_json::from_str::<serde_json::Value>(&run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path": "/workspace/big.bin", "max_bytes": 128}),
    ))
    .expect("read_file output is JSON");
    let bytes_read = out["bytes_read"].as_u64().expect("bytes_read");
    assert!(
        bytes_read <= 128,
        "bytes_read must respect max_bytes; got {bytes_read}"
    );
    assert_eq!(out["truncated"].as_bool(), Some(true));
}

// --- §2 exec 结果观察类型独立化基线（#194175 映射 + #185636/#193802 续） ---------
// OpenClaw #194175：把 exec 已可观察结果与退场/失败/policy 合约拆到独立 observation type owner
// （uncertain 标记 / terminal / ordinal 字段），避免后续 cleanup 信号改写已观察成功结果、或
// 超时/被排队打断/退场路径下结果被 failed/canceled/shutdown 覆盖。Napaxi 当前
// `ShellExecResult` 与执行路径耦在一起、无独立 observation type owner——本族 baseline 用
// read_file 工具作最小可观察结果载体，固化两条不变式：观察结果相比后续无关工单不被覆盖、
// 观察边界 per-call 不串扰（max_bytes 截断只作用于当次调用）。末来引入独立 observation type
// owner 时这两条不变式继续约束读路径行为。

#[test]
fn read_file_observation_survives_unrelated_apply_patch() {
    // OpenClaw #194175：已观察的 exec 结果不应被后续无关工单的失败/退场信号改写。
    // baseline 用 read_file 先读一份稳定结果，再对另一个无关文件 apply_patch（add），
    // 然后重读同一文件——结果与首次观察一致，证明观察结果未被外部路径覆盖。
    let dir = temp_dir("obs_survive");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    fs::write(
        bridge.workspace_dir().join("observed.md"),
        "first observation payload",
    )
    .unwrap();

    let first = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/workspace/observed.md"}),
    );
    assert_eq!(first["content"].as_str(), Some("first observation payload"),);
    assert_eq!(first["truncated"].as_bool(), Some(false));

    // 对无关文件 apply_patch（add）——模拟一个后续无关工具动作。
    let _add = run(
        &files_dir,
        APPLY_PATCH_TOOL_NAME,
        serde_json::json!({
            "patch": "*** Begin Patch\n*** Add File: /workspace/other.md\n+unrelated\n*** End Patch"
        }),
    );

    // 重读同一已观察文件：结果必须与首次观察一致，不被后续动作覆盖。
    let reread = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/workspace/observed.md"}),
    );
    assert_eq!(
        reread["content"].as_str(),
        Some("first observation payload"),
    );
    assert_eq!(reread["truncated"].as_bool(), Some(false));
}

#[test]
fn read_file_observation_bounded_per_call_not_shared_across_calls() {
    // OpenClaw #194175：观察边界 per-call——单次调用的 max_bytes 截断只作用于当次读取，
    // 不应串扰到同一文件的后续无界读取（独立 observation owner 的 per-call 语义）。
    // baseline：一个 max_bytes=4 的截断调用其后，无 max_bytes 调用须读回完整内容。
    let dir = temp_dir("obs_per_call");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir()).unwrap();
    let full = "observation-bounded-per-call-payload";
    fs::write(bridge.workspace_dir().join("bounded.md"), full).unwrap();

    let bounded = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/workspace/bounded.md","max_bytes":4}),
    );
    assert_eq!(bounded["bytes_read"].as_u64(), Some(4));
    assert_eq!(bounded["truncated"].as_bool(), Some(true));

    // 同一文件、无 max_bytes 的后续调用：观察边界不应串扰，须读回完整未截断内容。
    let unbounded = run(
        &files_dir,
        READ_FILE_TOOL_NAME,
        serde_json::json!({"path":"/workspace/bounded.md"}),
    );
    assert_eq!(unbounded["content"].as_str(), Some(full));
    assert_eq!(unbounded["truncated"].as_bool(), Some(false));
}
