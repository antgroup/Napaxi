//! Workspace integration tests covering CRUD, prompt assembly, journal,
//! search, profile sync, reseed/migration, and scoped path policy.

use std::fs;
use std::path::PathBuf;

use chrono::Utc;

use super::files::{
    append_workspace_file, append_workspace_file_handle, delete_workspace_file,
    delete_workspace_file_handle, list_workspace_files_handle, read_workspace_file,
    read_workspace_file_content, read_workspace_file_handle, write_workspace_file,
    write_workspace_file_handle,
};
use super::journal::{append_journal_turn, list_journal_days, read_journal_day};
use super::paths::{
    MEMORY, PROFILE_SECTION_BEGIN, default_scoped_files_dir, is_system_prompt_file,
    looks_like_filesystem_path, memory_dir, normalize_workspace_memory_path,
    normalize_workspace_path, scoped_files_dir,
};
use super::profile::write_profile_json;
use super::prompt::{system_prompt, system_prompt_for_context, system_prompt_handle};
use super::recall;
use super::reseed::{reseed_workspace, reseed_workspace_handle};
use super::search::{is_hybrid_match, search_memory_results, search_terms, snippet};
use super::types::{JournalDay, JournalTurnRecord};
use crate::storage::FileBridge;

fn temp_dir(name: &str) -> PathBuf {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    std::env::temp_dir().join(format!("napaxi_mobile_workspace_{name}_{millis}"))
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
fn file_roundtrip_and_prompt_work() {
    let dir = temp_dir("roundtrip");
    let files_dir = dir.to_string_lossy().to_string();

    assert!(write_workspace_file(&files_dir, "USER.md", "User notes"));
    assert!(append_workspace_file(&files_dir, "USER.md", "\nMore"));
    assert!(write_workspace_file(
        &files_dir,
        "context/profile.json",
        r#"{"name":"Wenyu","preferences":["concise"]}"#
    ));
    assert!(write_workspace_file(
        &files_dir,
        "context/assistant-directives.md",
        "Be direct."
    ));
    assert!(write_workspace_file(
        &files_dir,
        "HEARTBEAT.md",
        "Check in gently."
    ));
    assert!(write_workspace_file(
        &files_dir,
        "PROJECT.md",
        "Project keeps SDK memory local."
    ));
    assert!(write_workspace_file(
        &files_dir,
        "daily/2026-05-13.md",
        "Legacy daily should not enter prompts."
    ));
    let journal_path =
        append_journal_turn(&files_dir, "napaxi", "thread-1", "hi", "hello").unwrap();

    let read = read_workspace_file(&files_dir, "USER.md");
    assert!(read.contains("User notes\\nMore"));
    assert!(journal_path.starts_with("napaxi/journal/turns/"));

    let prompt = system_prompt(&files_dir);
    assert!(prompt.contains("## User Context"));
    assert!(prompt.contains("User notes"));
    assert!(prompt.contains("## User Profile"));
    assert!(prompt.contains("Wenyu"));
    assert!(prompt.contains("## Assistant Directives"));
    assert!(prompt.contains("Be direct."));
    assert!(prompt.contains("## Heartbeat Notes"));
    assert!(prompt.contains("Check in gently."));
    assert!(prompt.contains("## Project Memory"));
    assert!(prompt.contains("Project keeps SDK memory local."));
    assert!(!prompt.contains("## Today's Daily Log"));
    assert!(!prompt.contains("## Yesterday's Daily Log"));
    assert!(!prompt.contains("Legacy daily should not enter prompts."));
    assert!(!prompt.contains("thread-1"));

    let group_prompt = system_prompt_for_context(&files_dir, true);
    assert!(!group_prompt.contains("## User Profile"));
    assert!(!group_prompt.contains("## Long-Term Memory"));
    assert!(!group_prompt.contains("## Project Memory"));
    assert!(!group_prompt.contains("thread-1"));

    assert!(delete_workspace_file(&files_dir, "USER.md"));
    assert_eq!(read_workspace_file(&files_dir, "USER.md"), "null");
}

#[test]
fn journal_and_memory_search_are_separate_from_prompt() {
    let dir = temp_dir("journal_search");
    let files_dir = dir.to_string_lossy().to_string();

    write_workspace_file(&files_dir, MEMORY, "Curated pineapple preference");
    write_workspace_file(&files_dir, "daily/2026-05-13.md", "Legacy daily zebra note");
    let journal_path = append_journal_turn(
        &files_dir,
        "napaxi",
        "thread-journal",
        "Discuss marble hypothesis",
        "Marble hypothesis recorded",
    )
    .unwrap();
    assert!(journal_path.starts_with("napaxi/journal/turns/"));

    let today = Utc::now().format("%Y-%m-%d").to_string();
    let days: Vec<JournalDay> = serde_json::from_str(&list_journal_days(&files_dir)).unwrap();
    assert!(days.iter().any(|day| day.date == today));
    assert!(days.iter().any(|day| day.date == "2026-05-13"));

    let records: Vec<JournalTurnRecord> =
        serde_json::from_str(&read_journal_day(&files_dir, &today)).unwrap();
    assert!(
        records
            .iter()
            .any(|record| record.thread_id == "thread-journal")
    );

    let results = search_memory_results(&files_dir, "pineapple marble zebra", 10).unwrap();
    assert!(results.iter().any(|result| result.path == MEMORY));
    assert!(
        results
            .iter()
            .any(|result| result.source == "journal" && result.path.contains(&today))
    );
    assert!(
        results
            .iter()
            .any(|result| result.source == "legacy_daily" && result.path == "daily/2026-05-13.md")
    );

    let prompt = system_prompt(&files_dir);
    assert!(prompt.contains("Curated pineapple preference"));
    assert!(!prompt.contains("Marble hypothesis recorded"));
    assert!(!prompt.contains("Legacy daily zebra note"));
}

#[test]
fn recall_search_forgets_deleted_curated_memory() {
    let dir = temp_dir("recall_deleted_curated");
    let files_dir = dir.to_string_lossy().to_string();

    write_workspace_file(&files_dir, MEMORY, "Curated quartz-orchid deletion marker");
    let results = search_memory_results(&files_dir, "quartz orchid", 10).unwrap();
    assert!(results.iter().any(|result| result.path == MEMORY));

    assert!(delete_workspace_file(&files_dir, MEMORY));
    let results = search_memory_results(&files_dir, "quartz orchid", 10).unwrap();
    assert!(!results.iter().any(|result| result.path == MEMORY));
}

#[test]
fn recall_search_forgets_deleted_legacy_daily() {
    let dir = temp_dir("recall_deleted_legacy");
    let files_dir = dir.to_string_lossy().to_string();
    let daily_path = "daily/2026-05-13.md";

    write_workspace_file(
        &files_dir,
        daily_path,
        "Legacy daily lapis-sundial deletion marker",
    );
    let results = search_memory_results(&files_dir, "lapis sundial", 10).unwrap();
    assert!(
        results
            .iter()
            .any(|result| result.source == "legacy_daily" && result.path == daily_path)
    );

    assert!(delete_workspace_file(&files_dir, daily_path));
    let results = search_memory_results(&files_dir, "lapis sundial", 10).unwrap();
    assert!(
        !results
            .iter()
            .any(|result| result.source == "legacy_daily" && result.path == daily_path)
    );
}

#[test]
fn recall_search_refreshes_deleted_journal_source() {
    let dir = temp_dir("recall_deleted_journal");
    let files_dir = dir.to_string_lossy().to_string();
    let journal_path = append_journal_turn(
        &files_dir,
        "napaxi",
        "thread-delete-journal",
        "Discuss cobalt-river marker",
        "Cobalt river marker recorded",
    )
    .unwrap();

    let results = search_memory_results(&files_dir, "cobalt river", 10).unwrap();
    assert!(
        results
            .iter()
            .any(|result| result.thread_id.as_deref() == Some("thread-delete-journal"))
    );

    fs::remove_file(PathBuf::from(&files_dir).join(journal_path)).unwrap();
    let results = search_memory_results(&files_dir, "cobalt river", 10).unwrap();
    assert!(
        !results
            .iter()
            .any(|result| result.thread_id.as_deref() == Some("thread-delete-journal"))
    );
}

#[test]
fn recall_rebuild_counts_match_raw_sources() {
    let dir = temp_dir("recall_rebuild_counts");
    let files_dir = dir.to_string_lossy().to_string();

    write_workspace_file(&files_dir, MEMORY, "Curated amber-radar marker");
    write_workspace_file(
        &files_dir,
        "daily/2026-05-14.md",
        "Legacy daily violet-beacon marker",
    );
    append_journal_turn(
        &files_dir,
        "napaxi",
        "thread-rebuild-counts",
        "Discuss silver-compass marker",
        "Silver compass marker recorded",
    )
    .unwrap();

    let stats = recall::rebuild_index(&files_dir).unwrap();
    assert_eq!(stats.memory_docs, 1);
    assert_eq!(stats.journal_docs, 1);
    assert_eq!(stats.legacy_daily_docs, 1);

    let today = Utc::now().format("%Y-%m-%d").to_string();
    let records: Vec<JournalTurnRecord> =
        serde_json::from_str(&read_journal_day(&files_dir, &today)).unwrap();
    assert!(
        records
            .iter()
            .any(|record| record.thread_id == "thread-rebuild-counts")
    );
}

#[tokio::test]
async fn session_recall_groups_journal_and_excludes_current_thread() {
    let dir = temp_dir("session_recall");
    let files_dir = dir.to_string_lossy().to_string();

    append_journal_turn(
        &files_dir,
        "napaxi",
        "thread-old",
        "Investigate obsidian crash on Android",
        "Fixed by rebuilding the local recall index and clearing a stale cache.",
    )
    .unwrap();
    append_journal_turn(
        &files_dir,
        "napaxi",
        "thread-current",
        "Mention obsidian crash in current context",
        "Current turn should not be recalled as prior work.",
    )
    .unwrap();

    let results = search_memory_results(&files_dir, "obsidian (crash) + stale cache?", 10).unwrap();
    assert!(
        results
            .iter()
            .any(|result| result.thread_id.as_deref() == Some("thread-old"))
    );

    let sessions = super::recall_sessions(
        &files_dir,
        &crate::types::PlatformLlmConfig::default(),
        Some("thread-current"),
        "obsidian crash stale cache",
        5,
    )
    .await
    .unwrap();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0].thread_id, "thread-old");
    assert!(sessions[0].fallback);
    assert!(sessions[0].summary.contains("Raw preview"));

    let stats = recall::rebuild_index(&files_dir).unwrap();
    assert!(stats.indexed_docs >= 2);
    assert!(stats.journal_docs >= 2);
}

#[test]
fn first_run_prompt_keeps_bootstrap_until_profile_is_populated() {
    let dir = temp_dir("first_run_bootstrap");
    let files_dir = dir.to_string_lossy().to_string();
    reseed_workspace(&files_dir);

    let prompt = system_prompt_for_context(&files_dir, false);
    assert!(prompt.contains("## First-Run Bootstrap"));
    assert!(prompt.contains("You are starting up for the first time"));
    assert!(prompt.contains("Remember things across sessions"));

    write_profile_json(&files_dir, r#"{"name":"Wenyu"}"#, true).unwrap();
    let prompt = system_prompt_for_context(&files_dir, false);
    assert!(!prompt.contains("## First-Run Bootstrap"));
}

#[test]
fn unmodified_identity_and_tools_seeds_are_excluded_from_prompt() {
    let dir = temp_dir("seed_placeholder_prompt");
    let files_dir = dir.to_string_lossy().to_string();
    reseed_workspace(&files_dir);
    // Populate the profile so the first-run bootstrap section drops out and we
    // assess IDENTITY/TOOLS in isolation.
    write_profile_json(&files_dir, r#"{"name":"Wenyu"}"#, true).unwrap();

    // Freshly-seeded IDENTITY/TOOLS are pure placeholders — they must not ship.
    // (Match the placeholder bodies directly; AGENTS.md mentions "Identity"/
    // "Tool" in prose, so asserting on the headers alone would be ambiguous.)
    let prompt = system_prompt_for_context(&files_dir, false);
    assert!(!prompt.contains("pick one during your first conversation"));
    assert!(!prompt.contains("This file does not control which tools are available"));

    // Once edited away from the seed, the section is included normally.
    assert!(write_workspace_file(
        &files_dir,
        "IDENTITY.md",
        "# Identity\n\n- **Name:** Mason"
    ));
    let prompt = system_prompt_for_context(&files_dir, false);
    assert!(prompt.contains("## Identity"));
    assert!(prompt.contains("Mason"));
}

#[test]
fn handle_wrappers_operate_on_scoped_workspace() {
    let dir = temp_dir("handle");
    let files_dir = dir.to_string_lossy().to_string();
    let handle = engine_handle(&files_dir);
    let account_id = "user-a";
    let agent_id = "agent-a";

    assert!(
        read_workspace_file_handle(0, account_id, agent_id, "USER.md")
            .contains("invalid engine handle")
    );
    assert_eq!(
        list_workspace_files_handle(0, account_id, agent_id, ""),
        "[]"
    );
    assert!(write_workspace_file_handle(
        handle,
        account_id,
        agent_id,
        "USER.md",
        "Scoped user notes"
    ));
    assert!(append_workspace_file_handle(
        handle, account_id, agent_id, "USER.md", "\nMore"
    ));
    assert!(
        read_workspace_file_handle(handle, account_id, agent_id, "USER.md")
            .contains("Scoped user notes\\nMore")
    );
    assert!(list_workspace_files_handle(handle, account_id, agent_id, "").contains("USER.md"));
    assert!(system_prompt_handle(handle, account_id, agent_id).contains("Scoped user notes"));
    assert!(reseed_workspace_handle(handle, account_id, agent_id).contains("seeded"));
    assert!(delete_workspace_file_handle(
        handle, account_id, agent_id, "USER.md"
    ));
    assert_eq!(
        read_workspace_file_handle(handle, account_id, agent_id, "USER.md"),
        "null"
    );

    // SAFETY: `handle` was created in this test and is consumed exactly once here, satisfying `handle_consume`'s contract.
    let _ = unsafe { crate::runtime::handle_consume(handle) };
}

#[test]
fn syncs_profile_documents_and_clears_bootstrap() {
    let dir = temp_dir("profile");
    let files_dir = dir.to_string_lossy().to_string();
    reseed_workspace(&files_dir);

    let profile = r#"{
      "name": "Wenyu",
      "communication": {
        "tone": "direct",
        "detail_level": "concise"
      },
      "assistance": {
        "goals": ["ship the SDK", "preserve mobile runtime parity"]
      }
    }"#;
    assert_eq!(
        write_profile_json(&files_dir, profile, true).unwrap(),
        "context/profile.json"
    );

    let user = read_workspace_file_content(&files_dir, "USER.md")
        .unwrap()
        .unwrap();
    assert!(user.contains(PROFILE_SECTION_BEGIN));
    assert!(user.contains("Wenyu"));
    assert!(user.contains("communication / tone"));

    let directives = read_workspace_file_content(&files_dir, "context/assistant-directives.md")
        .unwrap()
        .unwrap();
    assert!(directives.contains("direct"));
    assert!(directives.contains("concise"));

    let heartbeat = read_workspace_file_content(&files_dir, "HEARTBEAT.md")
        .unwrap()
        .unwrap();
    assert!(heartbeat.contains("ship the SDK"));

    let bootstrap = read_workspace_file_content(&files_dir, "BOOTSTRAP.md")
        .unwrap()
        .unwrap();
    assert!(bootstrap.is_empty());

    let update = r#"{"communication":{"pace":"fast"}}"#;
    write_profile_json(&files_dir, update, true).unwrap();
    let merged = read_workspace_file_content(&files_dir, "context/profile.json")
        .unwrap()
        .unwrap();
    assert!(merged.contains("\"tone\": \"direct\""));
    assert!(merged.contains("\"pace\": \"fast\""));
}

#[test]
fn seed_only_creates_missing_files() {
    let dir = temp_dir("seed");
    let files_dir = dir.to_string_lossy().to_string();

    let first = reseed_workspace(&files_dir);
    assert!(first.contains("\"seeded\":"));
    assert!(read_workspace_file(&files_dir, "SOUL.md").contains("content"));
    assert!(memory_dir(&files_dir).join("SOUL.md").exists());
    assert!(
        !FileBridge::new(&files_dir)
            .workspace_dir()
            .join("SOUL.md")
            .exists()
    );

    let second = reseed_workspace(&files_dir);
    assert_eq!(second, r#"{"seeded":0}"#);
}

#[test]
fn reseed_updates_unmodified_bootstrap_template() {
    let dir = temp_dir("bootstrap_seed_update");
    let files_dir = dir.to_string_lossy().to_string();
    // With hardcoded bootstrap prompt, reseed no longer overwrites existing
    // BOOTSTRAP.md content — the file is only seeded on fresh installs.
    let old_bootstrap = r#"# Bootstrap

You are starting up for the first time. Follow these instructions for your first conversation.

1. `memory_write` with `target: "bootstrap"` — clears this file so first-run never repeats
"#;
    assert!(write_workspace_file(
        &files_dir,
        "BOOTSTRAP.md",
        old_bootstrap
    ));

    let result = reseed_workspace(&files_dir);
    assert!(result.contains("\"seeded\":"));
    // File should remain unchanged — reseed no longer rewrites it
    let bootstrap = read_workspace_file_content(&files_dir, "BOOTSTRAP.md")
        .unwrap()
        .unwrap();
    assert!(bootstrap.contains("clears this file so first-run never repeats"));
}

#[test]
fn reseed_migrates_legacy_memory_out_of_sandbox_workspace() {
    let dir = temp_dir("legacy_seed");
    let files_dir = dir.to_string_lossy().to_string();
    let bridge = FileBridge::new(&files_dir);
    fs::create_dir_all(bridge.workspace_dir().join("context")).unwrap();
    fs::write(bridge.workspace_dir().join("AGENTS.md"), "legacy agents").unwrap();
    fs::write(
        bridge.workspace_dir().join("context/profile.json"),
        r#"{"name":"Legacy"}"#,
    )
    .unwrap();

    reseed_workspace(&files_dir);

    assert_eq!(
        read_workspace_file_content(&files_dir, "AGENTS.md").unwrap(),
        Some("legacy agents".to_string())
    );
    assert!(memory_dir(&files_dir).join("context/profile.json").exists());
    assert!(!bridge.workspace_dir().join("AGENTS.md").exists());
    assert!(!bridge.workspace_dir().join("context").exists());
}

#[test]
fn scoped_files_dir_is_account_and_agent_specific() {
    let base = temp_dir("scope");
    let base = base.to_string_lossy().to_string();

    let first = scoped_files_dir(&base, "account/one", "agent:alpha");
    let second = scoped_files_dir(&base, "account/two", "agent:alpha");
    let third = scoped_files_dir(&base, "account/one", "agent:beta");

    assert!(first.starts_with(&base));
    assert!(first.contains("accounts/account_one/agents/agent_alpha"));
    assert_ne!(first, second);
    assert_ne!(first, third);
    assert!(default_scoped_files_dir(&base, "").ends_with("agents/napaxi"));
}

// ===========================================================================
// Path normalization + safety
// ===========================================================================

#[test]
fn normalize_workspace_memory_path_strips_workspace_prefix_and_leading_slash() {
    assert_eq!(
        normalize_workspace_memory_path("/workspace/notes/x.md").unwrap(),
        "notes/x.md"
    );
    assert_eq!(
        normalize_workspace_memory_path("/notes/y.md").unwrap(),
        "notes/y.md"
    );
    assert_eq!(
        normalize_workspace_memory_path("notes/z.md").unwrap(),
        "notes/z.md"
    );
}

#[test]
fn normalize_workspace_memory_path_rejects_traversal_and_empty_segments() {
    // Path traversal — must not let `..` segments escape the workspace root.
    assert!(normalize_workspace_memory_path("../escape.md").is_err());
    assert!(normalize_workspace_memory_path("notes/../escape.md").is_err());
    assert!(normalize_workspace_memory_path("notes/./x.md").is_err());
    // Empty segments (double slashes) should be rejected too.
    assert!(normalize_workspace_memory_path("notes//x.md").is_err());
    // Pure whitespace and empty — empty path is invalid.
    assert!(normalize_workspace_memory_path("").is_err());
    assert!(normalize_workspace_memory_path("   ").is_err());
    // After stripping /workspace/ we get empty.
    assert!(normalize_workspace_memory_path("/workspace/").is_err());
}

#[test]
fn normalize_workspace_path_is_lenient_about_emptiness() {
    // The lenient variant (no leading-slash rejection, used by callers that
    // allow the empty path to mean "memory root").
    assert_eq!(normalize_workspace_path(""), "");
    assert_eq!(normalize_workspace_path("/workspace/"), "");
    assert_eq!(normalize_workspace_path("/workspace/a"), "a");
    assert_eq!(normalize_workspace_path("a/b"), "a/b");
    assert_eq!(normalize_workspace_path("   /workspace/c   "), "c");
}

#[test]
fn looks_like_filesystem_path_detects_absolute_and_home_paths() {
    // Empty / relative — not a filesystem path.
    assert!(!looks_like_filesystem_path(""));
    assert!(!looks_like_filesystem_path("notes/x.md"));

    // Unix absolute.
    assert!(looks_like_filesystem_path("/etc/passwd"));
    assert!(looks_like_filesystem_path("/tmp/foo"));

    // Home shortcut.
    assert!(looks_like_filesystem_path("~/Documents/x.md"));

    // Windows drive letters.
    assert!(looks_like_filesystem_path("C:\\Users\\me"));
    assert!(looks_like_filesystem_path("D:/data"));

    // Almost-but-not — single char before colon doesn't trigger Windows path.
    assert!(!looks_like_filesystem_path("12:00"));
}

#[test]
fn is_system_prompt_file_is_case_insensitive_for_known_files() {
    // Canonical names.
    assert!(is_system_prompt_file("MEMORY.md"));
    assert!(is_system_prompt_file("SOUL.md"));
    assert!(is_system_prompt_file("USER.md"));
    assert!(is_system_prompt_file("context/profile.json"));
    // Case insensitive — eq_ignore_ascii_case.
    assert!(is_system_prompt_file("memory.md"));
    assert!(is_system_prompt_file("Memory.md"));
    // Unknown files are not system prompts.
    assert!(!is_system_prompt_file("notes/random.md"));
    assert!(!is_system_prompt_file("MEMORY.txt"));
    assert!(!is_system_prompt_file(""));
}

// ===========================================================================
// Search fallback + helpers
// ===========================================================================

#[test]
fn search_terms_lowercases_and_splits_on_non_alphanumeric() {
    let terms = search_terms("Hello, WORLD! ab x");
    // Lowercased.
    assert!(terms.contains(&"hello".to_string()));
    assert!(terms.contains(&"world".to_string()));
    // Two-letter words kept; single-letter "x" dropped (filter >= 2).
    assert!(terms.contains(&"ab".to_string()));
    assert!(!terms.contains(&"x".to_string()));
    // Punctuation is treated as separator, not preserved.
    assert!(!terms.iter().any(|t| t.contains(',')));
}

#[test]
fn snippet_returns_substring_near_first_matched_term() {
    let content = "alpha beta gamma delta epsilon zeta eta theta iota";
    let s = snippet(content, &["delta".to_string()]);
    assert!(
        s.contains("delta"),
        "snippet must contain the matched term, got: {s}"
    );
    // It should be reasonably short; not the entire document.
    assert!(s.len() <= content.len());
}

#[test]
fn snippet_handles_no_match_gracefully() {
    let s = snippet("alpha beta gamma", &["nothing".to_string()]);
    // No assertion on specific content — we just verify it does not panic
    // and returns something printable.
    let _ = s.len();
}

#[test]
fn hybrid_match_requires_all_terms_and_multiple_terms() {
    let terms = vec!["alpha".to_string(), "gamma".to_string()];
    // Contains every term -> hybrid match.
    assert!(is_hybrid_match("alpha beta gamma delta", &terms));
    // Missing one term -> not a hybrid match.
    assert!(!is_hybrid_match("alpha beta delta", &terms));
    // Single-term queries are never hybrid matches.
    assert!(!is_hybrid_match("alpha beta", &["alpha".to_string()]));
    // Empty query is never a hybrid match.
    assert!(!is_hybrid_match("alpha beta", &[]));
}
