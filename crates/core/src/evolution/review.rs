use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use chrono::Utc;
use napaxi_evolution::{
    EvolutionConfig, EvolutionReviewInput, EvolutionReviewJob, EvolutionReviewOutput,
    MemoryEntryType, MessageSnapshot, NudgeState, PendingQueue, ReviewType,
};
use sha2::{Digest, Sha256};

use crate::session::SessionMessage;
use crate::types::PlatformLlmConfig;

use super::executor::{EvolutionExecutor, ReviewLlmHandler};
use super::store::{append_diagnostic_record, persist_pending_confirmations};
use super::{
    DEFAULT_MEMORY_REVIEW_INTERVAL, DEFAULT_SKILL_REVIEW_INTERVAL, EVOLUTION_DIR,
    EvolutionDiagnosticRecord, EvolutionRun, review_type_name,
};

const MAX_REVIEW_MESSAGES: usize = 12;
const MAX_REVIEW_MESSAGE_CHARS: usize = 2_000;

pub(in crate::evolution) fn log_background_review_result(
    thread_id: &str,
    review_type: ReviewType,
    result: &EvolutionRun,
) {
    if let Some(error) = &result.error {
        tracing::warn!(
            thread_id,
            review_type = review_type_name(review_type),
            error,
            "[Evolution] Background review completed with error"
        );
        return;
    }

    tracing::info!(
        thread_id,
        review_type = review_type_name(review_type),
        suggestions_count = result.suggestions_count,
        auto_applied_count = result.auto_applied_count,
        pending_count = result.pending_count,
        "[Evolution] Background review completed"
    );
}

fn review_input_summary(
    history: &[SessionMessage],
    original_message_count: usize,
    trigger_turns: usize,
    trigger_tool_calls: usize,
) -> serde_json::Value {
    let last_user = history
        .iter()
        .rev()
        .find(|message| message.role == "user")
        .map(|message| bounded_preview(&message.content, 240));
    serde_json::json!({
        "message_count": history.len(),
        "original_message_count": original_message_count,
        "trigger_turns": trigger_turns,
        "trigger_tool_calls": trigger_tool_calls,
        "last_user_message": last_user,
        "context_isolated": true,
    })
}

fn review_provenance(
    history: &[SessionMessage],
    original_message_count: usize,
    review_type: ReviewType,
) -> serde_json::Value {
    serde_json::json!({
        "context_isolated": true,
        "review_type": review_type_name(review_type),
        "source_kinds": ["bounded_session_tail"],
        "source_hash": history_source_hash(history),
        "original_message_count": original_message_count,
        "review_message_count": history.len(),
        "max_review_messages": MAX_REVIEW_MESSAGES,
        "max_review_message_chars": MAX_REVIEW_MESSAGE_CHARS,
        "raw_journal_included": false,
        "legacy_daily_included": false,
        "recall_included": false,
    })
}

fn isolated_review_history(history: &[SessionMessage]) -> Vec<SessionMessage> {
    let start = history.len().saturating_sub(MAX_REVIEW_MESSAGES);
    history[start..]
        .iter()
        .filter(|message| !message.content.trim().is_empty())
        .map(|message| {
            let mut cloned = message.clone();
            cloned.content = bounded_preview(&cloned.content, MAX_REVIEW_MESSAGE_CHARS);
            cloned
        })
        .collect()
}

fn history_source_hash(history: &[SessionMessage]) -> String {
    let mut hasher = Sha256::new();
    for message in history {
        hasher.update(message.id.as_bytes());
        hasher.update([0]);
        hasher.update(message.role.as_bytes());
        hasher.update([0]);
        hasher.update(message.created_at.as_bytes());
        hasher.update([0]);
        if let Some(turn_id) = &message.turn_id {
            hasher.update(turn_id.as_bytes());
        }
        hasher.update([0]);
        hasher.update(message.content.as_bytes());
        hasher.update([0xff]);
    }
    format!("{:x}", hasher.finalize())
}

fn bounded_preview(text: &str, max_chars: usize) -> String {
    let mut preview = text.chars().take(max_chars).collect::<String>();
    if text.chars().count() > max_chars {
        preview.push_str("...");
    }
    preview
}

fn diagnostic_from_review_output(
    agent_id: &str,
    thread_id: &str,
    trigger_reason: &str,
    input_summary: serde_json::Value,
    provenance: serde_json::Value,
    output: &EvolutionReviewOutput,
    pending_count: usize,
) -> EvolutionDiagnosticRecord {
    let auto_applied_count = output.auto_applied_count;
    EvolutionDiagnosticRecord {
        id: uuid::Uuid::new_v4().to_string(),
        created_at: Utc::now().to_rfc3339(),
        agent_id: agent_id.to_string(),
        thread_id: thread_id.to_string(),
        review_type: review_type_name(output.review_type).to_string(),
        trigger_reason: trigger_reason.to_string(),
        input_summary,
        provenance,
        tool_calls: output.tool_calls.clone(),
        suggestions_count: output.suggestions_count,
        pending_count,
        auto_applied_count,
        apply_result: (auto_applied_count > 0)
            .then(|| format!("auto_applied_count={auto_applied_count}")),
        failure_reason: output.error.clone(),
    }
}

pub(in crate::evolution) async fn review_memory_now(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> EvolutionRun {
    let queue = Arc::new(PendingQueue::new());
    let original_message_count = history.len();
    let review_history = isolated_review_history(history);
    let input_summary =
        review_input_summary(&review_history, original_message_count, history.len(), 0);
    let provenance = review_provenance(&review_history, original_message_count, ReviewType::Memory);
    let mut existing_memory = std::collections::HashMap::new();
    for (entry_type, filename) in [
        (MemoryEntryType::Environment, "MEMORY.md"),
        (MemoryEntryType::UserProfile, "USER.md"),
        (MemoryEntryType::Project, "PROJECT.md"),
    ] {
        if let Ok(Some(content)) =
            crate::workspace::read_workspace_file_content(files_dir, filename)
        {
            if !content.trim().is_empty() {
                existing_memory.insert(entry_type, content);
            }
        }
    }

    let input = EvolutionReviewInput {
        thread_id: thread_id.to_string(),
        review_type: ReviewType::Memory,
        conversation_snapshot: review_history.iter().map(snapshot_from_message).collect(),
        nudge_state: NudgeState {
            turns_since_memory: history.len(),
            iters_since_skill: 0,
            last_memory_review: None,
            last_skill_review: None,
            thread_id: thread_id.to_string(),
        },
        trigger_turns: history.len(),
        trigger_tool_calls: 0,
        existing_memory,
    };

    let mut review_config = EvolutionConfig::default();
    review_config.memory_nudge_interval = DEFAULT_MEMORY_REVIEW_INTERVAL;
    review_config.security.min_complexity_threshold = 1;
    review_config.security.auto_apply_high_confidence = true;
    review_config.security.max_suggestions_per_review = 5;

    let handler = Arc::new(ReviewLlmHandler::new(config.clone()));
    let callback = Arc::new(EvolutionExecutor::new(files_dir.to_string()));
    let job = EvolutionReviewJob::new(input, review_config, Arc::clone(&queue))
        .with_llm_handler(handler)
        .with_execution_callback(callback);

    match job.perform_review().await {
        Ok(output) => {
            let pending = queue.get_pending().await;
            let pending_count = match persist_pending_confirmations(files_dir, agent_id, &pending) {
                Ok(count) => count,
                Err(error) => {
                    let mut diagnostic = diagnostic_from_review_output(
                        agent_id,
                        thread_id,
                        "memory_interval",
                        input_summary.clone(),
                        provenance.clone(),
                        &output,
                        pending.len(),
                    );
                    diagnostic.failure_reason =
                        Some(format!("persist pending suggestions: {error}"));
                    append_diagnostic_record(files_dir, diagnostic);
                    return EvolutionRun {
                        reviewed: true,
                        suggestions_count: output.suggestions_count,
                        auto_applied_count: output
                            .suggestions_count
                            .saturating_sub(output.pending_ids.len()),
                        pending_count: pending.len(),
                        error: Some(format!("persist pending suggestions: {error}")),
                    };
                }
            };
            let run = EvolutionRun {
                reviewed: true,
                suggestions_count: output.suggestions_count,
                auto_applied_count: output
                    .suggestions_count
                    .saturating_sub(output.pending_ids.len()),
                pending_count,
                error: output.error.clone(),
            };
            append_diagnostic_record(
                files_dir,
                diagnostic_from_review_output(
                    agent_id,
                    thread_id,
                    "memory_interval",
                    input_summary,
                    provenance,
                    &output,
                    pending_count,
                ),
            );
            run
        }
        Err(error) => {
            let failure = error.to_string();
            append_diagnostic_record(
                files_dir,
                EvolutionDiagnosticRecord {
                    id: uuid::Uuid::new_v4().to_string(),
                    created_at: Utc::now().to_rfc3339(),
                    agent_id: agent_id.to_string(),
                    thread_id: thread_id.to_string(),
                    review_type: review_type_name(ReviewType::Memory).to_string(),
                    trigger_reason: "memory_interval".to_string(),
                    input_summary,
                    provenance,
                    tool_calls: vec![],
                    suggestions_count: 0,
                    pending_count: 0,
                    auto_applied_count: 0,
                    apply_result: None,
                    failure_reason: Some(failure.clone()),
                },
            );
            EvolutionRun {
                reviewed: true,
                suggestions_count: 0,
                auto_applied_count: 0,
                pending_count: 0,
                error: Some(failure),
            }
        }
    }
}

pub(in crate::evolution) async fn review_skill_now(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
    trigger_tool_calls: usize,
) -> EvolutionRun {
    let queue = Arc::new(PendingQueue::new());
    let original_message_count = history.len();
    let review_history = isolated_review_history(history);
    let input_summary = review_input_summary(
        &review_history,
        original_message_count,
        history.len(),
        trigger_tool_calls,
    );
    let provenance = review_provenance(&review_history, original_message_count, ReviewType::Skill);
    let input = EvolutionReviewInput {
        thread_id: thread_id.to_string(),
        review_type: ReviewType::Skill,
        conversation_snapshot: review_history.iter().map(snapshot_from_message).collect(),
        nudge_state: NudgeState {
            turns_since_memory: history.len(),
            iters_since_skill: trigger_tool_calls,
            last_memory_review: None,
            last_skill_review: None,
            thread_id: thread_id.to_string(),
        },
        trigger_turns: history.len(),
        trigger_tool_calls,
        existing_memory: std::collections::HashMap::new(),
    };

    let mut review_config = EvolutionConfig::default();
    review_config.skill_nudge_interval = DEFAULT_SKILL_REVIEW_INTERVAL;
    review_config.security.min_complexity_threshold = 1;
    review_config.security.auto_apply_high_confidence = false;
    review_config.security.max_suggestions_per_review = 5;

    let handler = Arc::new(ReviewLlmHandler::new(config.clone()));
    let skills_dir = prepare_skill_review_dir(files_dir, agent_id)
        .unwrap_or_else(|| installed_skill_dir(files_dir, agent_id));
    let job = EvolutionReviewJob::new(input, review_config, Arc::clone(&queue))
        .with_llm_handler(handler)
        .with_skills_dir(skills_dir);

    match job.perform_review().await {
        Ok(output) => {
            let pending = queue.get_pending().await;
            let pending_count = match persist_pending_confirmations(files_dir, agent_id, &pending) {
                Ok(count) => count,
                Err(error) => {
                    let mut diagnostic = diagnostic_from_review_output(
                        agent_id,
                        thread_id,
                        "tool_call_interval",
                        input_summary.clone(),
                        provenance.clone(),
                        &output,
                        pending.len(),
                    );
                    diagnostic.failure_reason =
                        Some(format!("persist pending suggestions: {error}"));
                    append_diagnostic_record(files_dir, diagnostic);
                    return EvolutionRun {
                        reviewed: true,
                        suggestions_count: output.suggestions_count,
                        auto_applied_count: 0,
                        pending_count: pending.len(),
                        error: Some(format!("persist pending suggestions: {error}")),
                    };
                }
            };
            let run = EvolutionRun {
                reviewed: true,
                suggestions_count: output.suggestions_count,
                auto_applied_count: 0,
                pending_count,
                error: output.error.clone(),
            };
            append_diagnostic_record(
                files_dir,
                diagnostic_from_review_output(
                    agent_id,
                    thread_id,
                    "tool_call_interval",
                    input_summary,
                    provenance,
                    &output,
                    pending_count,
                ),
            );
            run
        }
        Err(error) => {
            let failure = error.to_string();
            append_diagnostic_record(
                files_dir,
                EvolutionDiagnosticRecord {
                    id: uuid::Uuid::new_v4().to_string(),
                    created_at: Utc::now().to_rfc3339(),
                    agent_id: agent_id.to_string(),
                    thread_id: thread_id.to_string(),
                    review_type: review_type_name(ReviewType::Skill).to_string(),
                    trigger_reason: "tool_call_interval".to_string(),
                    input_summary,
                    provenance,
                    tool_calls: vec![],
                    suggestions_count: 0,
                    pending_count: 0,
                    auto_applied_count: 0,
                    apply_result: None,
                    failure_reason: Some(failure.clone()),
                },
            );
            EvolutionRun {
                reviewed: true,
                suggestions_count: 0,
                auto_applied_count: 0,
                pending_count: 0,
                error: Some(failure),
            }
        }
    }
}

fn snapshot_from_message(message: &SessionMessage) -> MessageSnapshot {
    MessageSnapshot {
        role: message.role.clone(),
        content: message.content.clone(),
        timestamp: chrono::DateTime::parse_from_rfc3339(&message.created_at)
            .ok()
            .map(|dt| dt.with_timezone(&Utc)),
    }
}

fn installed_skill_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    let agent = normalize_agent_id(agent_id);
    Path::new(files_dir)
        .join("napaxi")
        .join("skills")
        .join("installed")
        .join(agent)
}

fn agent_skill_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    let agent = normalize_agent_id(agent_id);
    Path::new(files_dir)
        .join("napaxi")
        .join("skills")
        .join("agents")
        .join(agent)
}

fn prepare_skill_review_dir(files_dir: &str, agent_id: &str) -> Option<PathBuf> {
    let agent = normalize_agent_id(agent_id);
    let snapshot = Path::new(files_dir)
        .join(EVOLUTION_DIR)
        .join("skill_review")
        .join(agent);
    if snapshot.exists() {
        let _ = fs::remove_dir_all(&snapshot);
    }
    fs::create_dir_all(&snapshot).ok()?;
    for source in [
        installed_skill_dir(files_dir, agent_id),
        agent_skill_dir(files_dir, agent_id),
    ] {
        copy_skill_dirs_for_review(&source, &snapshot);
    }
    Some(snapshot)
}

fn copy_skill_dirs_for_review(source_root: &Path, snapshot_root: &Path) {
    let Ok(entries) = fs::read_dir(source_root) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        if !metadata.is_dir() {
            continue;
        }
        let skill_md = entry.path().join("SKILL.md");
        if !skill_md.exists() {
            continue;
        }
        let target_dir = snapshot_root.join(entry.file_name());
        if fs::create_dir_all(&target_dir).is_ok() {
            let _ = fs::copy(skill_md, target_dir.join("SKILL.md"));
        }
    }
}

fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        crate::runtime::DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

/// Fallback profile extraction: when the memory review fires but profile hasn't
/// been written yet, extract basic user profile from conversation history and
/// write it to `context/profile.json`. Uses the same LLM pipeline.
pub(in crate::evolution) async fn extract_profile_from_history(
    files_dir: &str,
    config: &PlatformLlmConfig,
    history: &[SessionMessage],
) -> Result<(), String> {
    let review_history = isolated_review_history(history);
    if review_history.is_empty() {
        return Ok(());
    }

    let system_prompt = concat!(
        "Extract a user profile from the conversation below. ",
        "Return ONLY a valid JSON object with these fields (omit fields you cannot infer):\n",
        "{\n",
        "  \"name\": \"how the user wants to be called\",\n",
        "  \"role\": \"their profession or primary activity\",\n",
        "  \"communication\": {\n",
        "    \"style\": \"terse/detailed/casual/formal\",\n",
        "    \"language\": \"primary language they use\"\n",
        "  },\n",
        "  \"interests\": [\"list of interests or topics they care about\"],\n",
        "  \"goals\": [\"what they want help with\"],\n",
        "  \"confidence\": 0.4\n",
        "}\n",
        "If the conversation doesn't contain enough info for any profile, return exactly: {}",
    );

    let mut messages = vec![serde_json::json!({
        "role": "system",
        "content": system_prompt,
    })];
    for msg in &review_history {
        messages.push(serde_json::json!({
            "role": msg.role,
            "content": bounded_preview(&msg.content, MAX_REVIEW_MESSAGE_CHARS),
        }));
    }
    messages.push(serde_json::json!({
        "role": "user",
        "content": "[System] Based on the conversation above, extract the user profile as JSON now.",
    }));

    let mut llm_config = config.clone();
    llm_config.system_prompt.clear();
    let turn = crate::llm::complete_turn_with_raw_messages(&llm_config, &messages, &[])
        .await
        .map_err(|e| e.to_string())?;

    let content = turn.content.trim();
    // Validate it's parseable JSON and not empty
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(content) {
        if let serde_json::Value::Object(map) = &value {
            if map.is_empty() {
                return Ok(());
            }
        }
        crate::workspace::write_profile_json(files_dir, content, true)?;
        tracing::info!(
            "[Evolution] Profile extraction fallback succeeded, wrote context/profile.json"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prepares_skill_review_snapshot_from_installed_and_agent_dirs() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let installed = installed_skill_dir(files_dir, "napaxi").join("installed-skill");
        let agent = agent_skill_dir(files_dir, "napaxi").join("agent-skill");
        fs::create_dir_all(&installed).unwrap();
        fs::create_dir_all(&agent).unwrap();
        fs::write(installed.join("SKILL.md"), "# Installed").unwrap();
        fs::write(agent.join("SKILL.md"), "# Agent").unwrap();

        let snapshot = prepare_skill_review_dir(files_dir, "napaxi").unwrap();
        assert!(snapshot.join("installed-skill/SKILL.md").exists());
        assert!(snapshot.join("agent-skill/SKILL.md").exists());
    }

    #[test]
    fn review_history_is_bounded_and_provenance_marks_isolation() {
        let now = Utc::now().to_rfc3339();
        let history = (0..20)
            .map(|index| SessionMessage {
                id: index.to_string(),
                role: if index % 2 == 0 { "user" } else { "assistant" }.to_string(),
                content: "x".repeat(MAX_REVIEW_MESSAGE_CHARS + 50),
                created_at: now.clone(),
                interrupted: false,
                turn_id: Some(format!("turn-{index}")),
            })
            .collect::<Vec<_>>();

        let isolated = isolated_review_history(&history);
        assert_eq!(isolated.len(), MAX_REVIEW_MESSAGES);
        assert_eq!(isolated[0].id, "8");
        assert!(isolated[0].content.chars().count() <= MAX_REVIEW_MESSAGE_CHARS + 3);

        let provenance = review_provenance(&isolated, history.len(), ReviewType::Memory);
        assert_eq!(provenance["context_isolated"], true);
        assert_eq!(provenance["original_message_count"], 20);
        assert_eq!(provenance["review_message_count"], MAX_REVIEW_MESSAGES);
        assert_eq!(provenance["raw_journal_included"], false);
        assert_eq!(provenance["recall_included"], false);
        assert!(
            provenance["source_hash"]
                .as_str()
                .is_some_and(|value| value.len() == 64)
        );
    }
}
