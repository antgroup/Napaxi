use async_trait::async_trait;
use chrono::Utc;
use napaxi_evolution::job::ExecutionCallback;
use napaxi_evolution::{
    LlmReviewHandler, MemoryEntryType, Message, PendingActionType, ReviewResult, Role, ToolRegistry,
};

use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

const MEMORY_DEDUP_SIMILARITY_THRESHOLD: f64 = 0.65;

pub(super) struct ReviewLlmHandler {
    config: PlatformLlmConfig,
}

impl ReviewLlmHandler {
    pub(super) fn new(config: PlatformLlmConfig) -> Self {
        Self { config }
    }
}

#[async_trait]
impl LlmReviewHandler for ReviewLlmHandler {
    async fn review(
        &self,
        messages: Vec<Message>,
        tools: &ToolRegistry,
        _timeout_secs: u64,
    ) -> Result<ReviewResult, String> {
        let raw_messages: Vec<serde_json::Value> = messages
            .into_iter()
            .map(|message| {
                serde_json::json!({
                    "role": role_name(message.role),
                    "content": message.content,
                })
            })
            .collect();
        let descriptors: Vec<ToolDescriptor> = tools
            .list()
            .into_iter()
            .map(|tool| ToolDescriptor {
                name: tool.name,
                description: tool.description,
                parameters: normalize_tool_schema(tool.parameters),
                effect: crate::tool_registry::ToolEffect::Unknown,
            })
            .collect();
        let mut config = self.config.clone();
        config.system_prompt.clear();
        let turn =
            crate::llm::complete_turn_with_raw_messages(&config, &raw_messages, &descriptors)
                .await
                .map_err(|e| e.to_string())?;
        let tool_calls = turn
            .tool_calls
            .into_iter()
            .map(|call| {
                (
                    call.name,
                    serde_json::from_str::<serde_json::Value>(&call.arguments)
                        .unwrap_or_else(|_| serde_json::json!({})),
                )
            })
            .collect();
        Ok(ReviewResult {
            content: turn.content,
            tool_calls,
        })
    }
}

fn role_name(role: Role) -> &'static str {
    match role {
        Role::System => "system",
        Role::User => "user",
        Role::Assistant => "assistant",
        Role::Tool => "tool",
    }
}

fn normalize_tool_schema(schema: serde_json::Value) -> serde_json::Value {
    schema.get("schema").cloned().unwrap_or_else(|| {
        if schema.get("type").is_some() {
            schema
        } else {
            serde_json::json!({"type": "object", "properties": {}})
        }
    })
}

pub(super) struct EvolutionExecutor {
    files_dir: String,
}

impl EvolutionExecutor {
    pub(super) fn new(files_dir: String) -> Self {
        Self { files_dir }
    }
}

#[async_trait]
impl ExecutionCallback for EvolutionExecutor {
    async fn execute(&self, action: &PendingActionType) -> Result<String, String> {
        match action {
            PendingActionType::MemoryWrite {
                entry_type,
                content,
            } => write_memory_evolution(&self.files_dir, *entry_type, content),
            other => Err(format!(
                "Mobile evolution auto-apply is not enabled for {}",
                other.action_type_name()
            )),
        }
    }
}

pub(super) async fn apply_mobile_action(
    files_dir: &str,
    agent_id: &str,
    action: &PendingActionType,
) -> Result<String, String> {
    match action {
        PendingActionType::MemoryWrite {
            entry_type,
            content,
        } => write_memory_evolution(files_dir, *entry_type, content),
        PendingActionType::Create { .. }
        | PendingActionType::Edit { .. }
        | PendingActionType::Patch { .. }
        | PendingActionType::Delete { .. }
        | PendingActionType::WriteFile { .. }
        | PendingActionType::RemoveFile { .. } => {
            crate::skills::apply_evolution_action(files_dir, agent_id, action).await
        }
    }
}

enum MemoryAction {
    Append,
    Update,
    Delete,
}

fn parse_memory_action(content: &str) -> (MemoryAction, String) {
    let trimmed = content.trim();
    if let Some(body) = trimmed.strip_prefix("[UPDATE]") {
        (MemoryAction::Update, body.trim().to_string())
    } else if let Some(body) = trimmed.strip_prefix("[DELETE]") {
        (MemoryAction::Delete, body.trim().to_string())
    } else {
        (MemoryAction::Append, trimmed.to_string())
    }
}

fn write_memory_evolution(
    files_dir: &str,
    entry_type: MemoryEntryType,
    content: &str,
) -> Result<String, String> {
    let target = match entry_type {
        MemoryEntryType::Environment => "MEMORY.md",
        MemoryEntryType::UserProfile => "USER.md",
        MemoryEntryType::Project => "PROJECT.md",
    };

    let (action, body) = parse_memory_action(content);
    let existing = crate::workspace::read_workspace_file_content(files_dir, target)
        .unwrap_or_default()
        .unwrap_or_default();

    match action {
        MemoryAction::Delete => {
            if existing.trim().is_empty() {
                return Ok(format!("Memory evolution skip delete on empty {target}"));
            }
            let entries = parse_memory_entries(&existing);
            let best = find_most_similar_entry(&body, &entries);
            match best {
                Some((idx, _sim)) => {
                    let kept: Vec<&str> = entries
                        .iter()
                        .enumerate()
                        .filter(|(i, _)| *i != idx)
                        .map(|(_, e)| e.as_str())
                        .collect();
                    let new_content = kept.join("\n\n");
                    crate::workspace::write_workspace_file_checked(
                        files_dir,
                        target,
                        &new_content,
                    )?;
                    Ok(format!("Memory evolution deleted entry from {target}"))
                }
                None => Ok(format!(
                    "Memory evolution skip delete: no similar entry in {target}"
                )),
            }
        }
        MemoryAction::Update => {
            let new_entry = format!(
                "## Memory Evolution - {}\n\n{}",
                Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
                body
            );
            if existing.trim().is_empty() {
                crate::workspace::append_workspace_file_checked(files_dir, target, &new_entry)?;
                return Ok(format!(
                    "Memory evolution wrote {target} (update fallback to append: file was empty)"
                ));
            }
            let entries = parse_memory_entries(&existing);
            let best = find_most_similar_entry(&body, &entries);
            match best {
                Some((idx, _sim)) => {
                    let replaced: Vec<String> = entries
                        .iter()
                        .enumerate()
                        .map(|(i, e)| {
                            if i == idx {
                                new_entry.clone()
                            } else {
                                e.clone()
                            }
                        })
                        .collect();
                    let new_content = replaced.join("\n\n");
                    crate::workspace::write_workspace_file_checked(
                        files_dir,
                        target,
                        &new_content,
                    )?;
                    Ok(format!("Memory evolution updated entry in {target}"))
                }
                None => {
                    crate::workspace::append_workspace_file_checked(files_dir, target, &new_entry)?;
                    Ok(format!(
                        "Memory evolution wrote {target} (update fallback to append: no similar entry)"
                    ))
                }
            }
        }
        MemoryAction::Append => {
            let entry = format!(
                "## Memory Evolution - {}\n\n{}",
                Utc::now().format("%Y-%m-%d %H:%M:%S UTC"),
                body
            );
            if is_duplicate_memory_entry(&entry, &existing) {
                return Ok(format!(
                    "Memory evolution skipped duplicate write to {target}"
                ));
            }
            // 字段级精确匹配：如果新内容与某个已有条目共享相同的结构化前缀
            // （如 **communication style:**），自动当作 update 处理
            if !existing.trim().is_empty() {
                if let Some(prefix) = extract_field_prefix(&body) {
                    let entries = parse_memory_entries(&existing);
                    if let Some(idx) = find_entry_with_same_prefix(&prefix, &entries) {
                        let replaced: Vec<String> = entries
                            .iter()
                            .enumerate()
                            .map(|(i, e)| if i == idx { entry.clone() } else { e.clone() })
                            .collect();
                        let new_content = replaced.join("\n\n");
                        crate::workspace::write_workspace_file_checked(
                            files_dir,
                            target,
                            &new_content,
                        )?;
                        return Ok(format!(
                            "Memory evolution updated {target} (field prefix match: {prefix})"
                        ));
                    }
                }
            }
            crate::workspace::append_workspace_file_checked(files_dir, target, &entry)?;
            Ok(format!("Memory evolution wrote {target}"))
        }
    }
}

fn find_most_similar_entry(query: &str, entries: &[String]) -> Option<(usize, f64)> {
    let mut best_idx = None;
    let mut best_sim = MEMORY_DEDUP_SIMILARITY_THRESHOLD * 0.5;
    for (i, entry) in entries.iter().enumerate() {
        let sim = jaccard_similarity(query, &memory_entry_body(entry));
        if sim > best_sim {
            best_sim = sim;
            best_idx = Some(i);
        }
    }
    best_idx.map(|i| (i, best_sim))
}

/// 从内容中提取结构化字段前缀，如 `**communication style:**` 或 `**role:**`
fn extract_field_prefix(content: &str) -> Option<String> {
    let trimmed = content.trim();
    if trimmed.starts_with("**") {
        if let Some(end) = trimmed.find(":**") {
            let prefix = &trimmed[..end + 3]; // include `:**`
            return Some(prefix.to_lowercase());
        }
    }
    None
}

/// 在已有条目中找到包含相同字段前缀的条目
fn find_entry_with_same_prefix(prefix: &str, entries: &[String]) -> Option<usize> {
    for (i, entry) in entries.iter().enumerate() {
        let body = memory_entry_body(entry);
        if body.trim().to_lowercase().starts_with(prefix) {
            return Some(i);
        }
    }
    None
}

fn is_duplicate_memory_entry(new_entry: &str, existing_content: &str) -> bool {
    let new_body = memory_entry_body(new_entry);
    if new_body.trim().is_empty() || existing_content.trim().is_empty() {
        return false;
    }
    parse_memory_entries(existing_content).iter().any(|entry| {
        jaccard_similarity(&new_body, &memory_entry_body(entry))
            >= MEMORY_DEDUP_SIMILARITY_THRESHOLD
    })
}

fn parse_memory_entries(content: &str) -> Vec<String> {
    let mut entries = Vec::new();
    for part in content.split("\n\n## ") {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.starts_with("## ") {
            entries.push(trimmed.to_string());
        } else {
            entries.push(format!("## {trimmed}"));
        }
    }
    entries
}

fn memory_entry_body(entry: &str) -> String {
    entry.lines().skip(1).collect::<Vec<_>>().join("\n")
}

fn jaccard_similarity(a: &str, b: &str) -> f64 {
    let a_words = memory_words(a);
    let b_words = memory_words(b);
    if a_words.is_empty() || b_words.is_empty() {
        return 0.0;
    }
    let intersection = a_words.intersection(&b_words).count();
    let union = a_words.union(&b_words).count();
    intersection as f64 / union as f64
}

fn memory_words(text: &str) -> std::collections::HashSet<String> {
    text.to_lowercase()
        .split_whitespace()
        .map(|word| word.trim_matches(|ch: char| !ch.is_alphanumeric()))
        .filter(|word| word.chars().count() > 2)
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_evolution_executor_writes_workspace_memory() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        write_memory_evolution(files_dir, MemoryEntryType::Environment, "Remember this").unwrap();
        let memory = crate::workspace::read_workspace_file_content(files_dir, "MEMORY.md")
            .unwrap()
            .unwrap();
        assert!(memory.contains("Memory Evolution"));
        assert!(memory.contains("Remember this"));
    }
}
