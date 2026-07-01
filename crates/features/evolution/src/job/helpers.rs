//! Prompt loading, skill-list injection, tool-call parsing, and review
//! message construction for [`EvolutionReviewJob`]. Split out of
//! `job/mod.rs` as a second impl block; pure code motion.

use super::*;

impl EvolutionReviewJob {
    /// Load system prompt from file
    pub(super) async fn load_prompt_from_file(&self, path: &str) -> EvolutionResult<String> {
        // Try loading from prompts/ under the crate directory
        let crate_prompt_path = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("prompts")
            .join(path);

        let content = if crate_prompt_path.exists() {
            fs::read_to_string(&crate_prompt_path)
                .await
                .map_err(EvolutionError::Io)?
        } else {
            // Try loading directly from the given path
            let direct_path = Path::new(path);
            if direct_path.exists() {
                fs::read_to_string(direct_path)
                    .await
                    .map_err(EvolutionError::Io)?
            } else {
                // Fallback to embedded prompt (via include_str!), critical for
                // mobile/device deployment where CARGO_MANIFEST_DIR is unavailable.
                let path_lower = path.to_ascii_lowercase();
                if path_lower.contains("skill_review") {
                    EMBEDDED_SKILL_REVIEW_PROMPT.to_string()
                } else if path_lower.contains("memory_review") {
                    EMBEDDED_MEMORY_REVIEW_PROMPT.to_string()
                } else {
                    return Err(EvolutionError::InvalidInput(format!(
                        "Prompt file not found: {:?}",
                        crate_prompt_path
                    )));
                }
            }
        };

        // If this is skill_review.md, inject the existing skill list
        if path.to_ascii_lowercase().contains("skill_review") {
            return self.inject_skill_list_into_prompt(content).await;
        }

        Ok(content)
    }

    /// Inject existing skill list into the prompt
    async fn inject_skill_list_into_prompt(&self, prompt: String) -> EvolutionResult<String> {
        let skills_dir = self
            .skills_dir_override
            .clone()
            .unwrap_or_else(|| crate::get_user_skills_dir(&self.config.user_id));
        self.inject_skill_list_into_prompt_with_dir(prompt, skills_dir)
            .await
    }

    /// Inject existing skill list into the prompt (supports specifying directory, for testing)
    #[cfg(test)]
    pub(super) async fn inject_skill_list_into_prompt_test(
        &self,
        prompt: String,
        skills_dir_override: Option<std::path::PathBuf>,
    ) -> EvolutionResult<String> {
        let skills_dir =
            skills_dir_override.unwrap_or_else(|| crate::get_user_skills_dir(&self.config.user_id));
        self.inject_skill_list_into_prompt_with_dir(prompt, skills_dir)
            .await
    }

    /// Internal implementation: inject skill list into the prompt
    async fn inject_skill_list_into_prompt_with_dir(
        &self,
        prompt: String,
        skills_dir: std::path::PathBuf,
    ) -> EvolutionResult<String> {
        const SKILL_LIST_BUDGET_BYTES: usize = 16 * 1024;
        let mut skill_list = String::new();
        let mut skill_count = 0;
        let mut budget_exceeded = false;

        tracing::info!(
            skills_dir = %skills_dir.display(),
            user_id = %self.config.user_id,
            "[Evolution] Loading skills for prompt injection"
        );

        // Read all skills under the user directory
        match fs::read_dir(&skills_dir).await {
            Ok(mut entries) => {
                let mut total_entries = 0;
                let mut dir_entries = 0;
                let mut skill_files_found = 0;

                while let Ok(Some(entry)) = entries.next_entry().await {
                    total_entries += 1;
                    let entry_name = entry.file_name().to_string_lossy().to_string();

                    match entry.metadata().await {
                        Ok(metadata) => {
                            if metadata.is_dir() {
                                dir_entries += 1;
                                let skill_file = entry.path().join(crate::types::SKILL_FILE_NAME);
                                let skill_file_exists = skill_file.exists();

                                tracing::info!(
                                    entry_name = %entry_name,
                                    skill_file = %skill_file.display(),
                                    exists = skill_file_exists,
                                    "[Evolution] Checking skill directory"
                                );

                                if skill_file_exists {
                                    skill_files_found += 1;
                                    let name = entry_name;
                                    skill_count += 1;

                                    // Read full content (for patch/edit reference)
                                    let (description, full_content) = if let Ok(content) =
                                        fs::read_to_string(&skill_file).await
                                    {
                                        let desc = content
                                            .lines()
                                            .find(|l| {
                                                l.trim().starts_with("description:")
                                                    || l.trim().starts_with("## Description")
                                                    || l.trim().starts_with("## Purpose")
                                                    || l.trim().starts_with("## Description (Chinese)")
                                            })
                                            .map(|l| {
                                                if l.contains(':') {
                                                    l.split_once(':')
                                                        .map(|x| x.1)
                                                        .unwrap_or("")
                                                        .trim()
                                                        .to_string()
                                                } else {
                                                    "See skill file".to_string()
                                                }
                                            })
                                            .unwrap_or_else(|| {
                                                "No description available".to_string()
                                            });

                                        (desc, content)
                                    } else {
                                        (
                                            "No description available".to_string(),
                                            "Unable to read content".to_string(),
                                        )
                                    };

                                    skill_list
                                        .push_str(&format!("- **{}**: {}\n", name, description));
                                    if !budget_exceeded {
                                        let details = format!("  <details>\n  <summary>Full content for patch/edit reference</summary>\n\n  ```markdown\n  {}\n  ```\n  </details>\n\n", full_content.replace('\n', "\n  "));
                                        if skill_list.len() + details.len()
                                            <= SKILL_LIST_BUDGET_BYTES
                                        {
                                            skill_list.push_str(&details);
                                        } else {
                                            budget_exceeded = true;
                                            tracing::info!(
                                                budget = SKILL_LIST_BUDGET_BYTES,
                                                current_len = skill_list.len(),
                                                "[Evolution] Skill list budget exceeded, omitting full content for remaining skills"
                                            );
                                        }
                                    }
                                }
                            } else {
                                tracing::info!(
                                    entry_name = %entry_name,
                                    "[Evolution] Entry is not a directory"
                                );
                            }
                        }
                        Err(e) => {
                            tracing::warn!(
                                entry_name = %entry_name,
                                error = %e,
                                "[Evolution] Failed to get entry metadata"
                            );
                        }
                    }
                }

                tracing::info!(
                    total_entries = total_entries,
                    dir_entries = dir_entries,
                    skill_files_found = skill_files_found,
                    "[Evolution] Directory scan complete"
                );
            }
            Err(e) => {
                tracing::warn!(
                    skills_dir = %skills_dir.display(),
                    error = %e,
                    "[Evolution] Failed to read skills directory"
                );
            }
        }

        tracing::info!(
            skill_count = skill_count,
            skills_dir = %skills_dir.display(),
            "[Evolution] Loaded skills for prompt injection"
        );

        // If no skills, show hint
        let skill_list_str = if skill_list.is_empty() {
            "_No existing skills. All new skills will be created._\n".to_string()
        } else {
            skill_list
        };

        // Replace template variable
        let result = prompt.replace("{{SKILL_LIST}}", &skill_list_str);

        Ok(result)
    }

    /// Fallback prompt (used when file loading fails)
    pub(super) fn load_prompt_fallback(&self) -> EvolutionResult<String> {
        let prompt = match self.input.review_type {
            ReviewType::Memory => "Review the conversation and save to memory if appropriate. \
                 Focus on: user preferences, work style, personal details worth remembering."
                .to_string(),
            ReviewType::Skill => {
                "Review the conversation and update/create skills if appropriate. \
                 Focus on: non-trivial approaches requiring trial and error, reusable patterns."
                    .to_string()
            }
            ReviewType::Combined => {
                "Review for memory (user preferences) and skills (reusable patterns).".to_string()
            }
        };
        Ok(prompt)
    }

    /// Build review tool registry (closed tool set)
    pub(super) fn build_tool_registry(&self) -> ToolRegistry {
        let mut registry = ToolRegistry::new();

        match self.input.review_type {
            ReviewType::Memory => registry.register::<ReviewMemoryTool>(),
            ReviewType::Skill => registry.register::<ReviewSkillTool>(),
            ReviewType::Combined => {
                registry.register::<ReviewMemoryTool>();
                registry.register::<ReviewSkillTool>();
            }
        }

        registry
    }

    /// Parse tool calls returned by LLM
    #[allow(dead_code)]
    async fn parse_tool_calls(
        &self,
        tool_calls: &[(String, serde_json::Value)],
    ) -> EvolutionResult<Vec<PendingActionType>> {
        let mut suggestions = Vec::new();

        for (tool_name, tool_input) in tool_calls {
            match tool_name.as_str() {
                "review_memory" => {
                    // Parse review_memory input
                    let input: crate::tools::ReviewMemoryInput =
                        serde_json::from_value(tool_input.clone())
                            .map_err(|e| EvolutionError::InvalidInput(e.to_string()))?;

                    suggestions.push(PendingActionType::MemoryWrite {
                        entry_type: input.entry_type,
                        content: input.content,
                    });
                }
                "review_skill" => {
                    // Parse review_skill input
                    let input: crate::tools::ReviewSkillInput =
                        serde_json::from_value(tool_input.clone())
                            .map_err(|e| EvolutionError::InvalidInput(e.to_string()))?;

                    let action = match input.action.as_str() {
                        "create" => PendingActionType::Create {
                            skill_name: input.name,
                            content: input.content.unwrap_or_default(),
                            category: input.category,
                        },
                        "edit" => PendingActionType::Edit {
                            skill_name: input.name,
                            new_content: input.content.unwrap_or_default(),
                        },
                        "patch" => PendingActionType::Patch {
                            skill_name: input.name,
                            old_string: input.old_string.unwrap_or_default(),
                            new_string: input.new_string.unwrap_or_default(),
                            file_path: input.file_path,
                            replace_all: false,
                        },
                        "delete" => PendingActionType::Delete {
                            skill_name: input.name,
                            absorbed_into: input.absorbed_into,
                        },
                        "write_file" => PendingActionType::WriteFile {
                            skill_name: input.name,
                            file_path: input.file_path.unwrap_or_default(),
                            file_content: input.content.unwrap_or_default(),
                        },
                        "remove_file" => PendingActionType::RemoveFile {
                            skill_name: input.name,
                            file_path: input.file_path.unwrap_or_default(),
                        },
                        other => {
                            tracing::warn!("Unknown review_skill action: {}", other);
                            continue;
                        }
                    };
                    suggestions.push(action);
                }
                _ => {
                    tracing::warn!("Unknown tool call in review: {}", tool_name);
                }
            }
        }

        Ok(suggestions)
    }

    /// Parse tool calls returned by LLM, including confidence
    pub(super) async fn parse_tool_calls_with_confidence(
        &self,
        tool_calls: &[(String, serde_json::Value)],
    ) -> EvolutionResult<Vec<SuggestedAction>> {
        use crate::types::{ConfidenceLevel, SuggestedAction};

        let mut suggestions = Vec::new();

        for (tool_name, tool_input) in tool_calls {
            // Parse confidence
            let confidence_str = tool_input
                .get("confidence")
                .and_then(|v| v.as_str())
                .unwrap_or("medium");

            let confidence = match confidence_str.to_lowercase().as_str() {
                "high" => ConfidenceLevel::High,
                "medium" => ConfidenceLevel::Medium,
                "low" => ConfidenceLevel::Low,
                _ => ConfidenceLevel::Medium,
            };

            // Parse reasoning
            let reasoning = tool_input
                .get("reasoning")
                .and_then(|v| v.as_str())
                .unwrap_or("Review agent suggestion")
                .to_string();

            match tool_name.as_str() {
                "review_memory" => {
                    let input: crate::tools::ReviewMemoryInput =
                        serde_json::from_value(tool_input.clone())
                            .map_err(|e| EvolutionError::InvalidInput(e.to_string()))?;

                    suggestions.push(SuggestedAction {
                        action: PendingActionType::MemoryWrite {
                            entry_type: input.entry_type,
                            content: input.content,
                        },
                        confidence,
                        reasoning,
                        source_indices: vec![],
                    });
                }
                "review_skill" => {
                    let input: crate::tools::ReviewSkillInput =
                        serde_json::from_value(tool_input.clone())
                            .map_err(|e| EvolutionError::InvalidInput(e.to_string()))?;

                    let action = match input.action.as_str() {
                        "create" => {
                            // LLM autonomously decides create/edit/patch based on the skill list in the prompt
                            // No second conversion at the system level; trust the LLM's judgment
                            PendingActionType::Create {
                                skill_name: input.name,
                                content: input.content.unwrap_or_default(),
                                category: input.category,
                            }
                        }
                        "edit" => PendingActionType::Edit {
                            skill_name: input.name,
                            new_content: input.content.unwrap_or_default(),
                        },
                        "patch" => PendingActionType::Patch {
                            skill_name: input.name,
                            old_string: input.old_string.unwrap_or_default(),
                            new_string: input.new_string.unwrap_or_default(),
                            file_path: input.file_path,
                            replace_all: false,
                        },
                        "delete" => PendingActionType::Delete {
                            skill_name: input.name,
                            absorbed_into: input.absorbed_into,
                        },
                        "write_file" => PendingActionType::WriteFile {
                            skill_name: input.name,
                            file_path: input.file_path.unwrap_or_default(),
                            file_content: input.content.unwrap_or_default(),
                        },
                        "remove_file" => PendingActionType::RemoveFile {
                            skill_name: input.name,
                            file_path: input.file_path.unwrap_or_default(),
                        },
                        other => {
                            tracing::warn!("Unknown review_skill action: {}", other);
                            continue;
                        }
                    };

                    suggestions.push(SuggestedAction {
                        action,
                        confidence,
                        reasoning,
                        source_indices: vec![],
                    });
                }
                _ => {
                    tracing::warn!("Unknown tool call in review: {}", tool_name);
                }
            }
        }

        Ok(suggestions)
    }

    /// Build review messages
    pub(super) fn build_review_messages(&self, system_prompt: &str) -> Vec<crate::traits::Message> {
        const MEMORY_PREVIEW_CHARS: usize = 2_000;

        let mut messages = vec![crate::traits::Message {
            role: crate::traits::Role::System,
            content: system_prompt.to_string(),
        }];

        // Inject existing memory content so LLM can make substantive dedup decisions
        if matches!(
            self.input.review_type,
            ReviewType::Memory | ReviewType::Combined
        ) && !self.input.existing_memory.is_empty()
        {
            let mut memory_ctx = String::from(
                "[System] Current memory file contents — \
                 do NOT save information that is already present below, \
                 even if worded differently.\n",
            );
            for (entry_type, label, filename) in [
                (
                    crate::types::MemoryEntryType::Environment,
                    "environment",
                    "MEMORY.md",
                ),
                (
                    crate::types::MemoryEntryType::UserProfile,
                    "user_profile",
                    "USER.md",
                ),
                (
                    crate::types::MemoryEntryType::Project,
                    "project",
                    "PROJECT.md",
                ),
            ] {
                memory_ctx.push_str(&format!("\n### {} ({})\n", filename, label));
                match self.input.existing_memory.get(&entry_type) {
                    Some(content) if !content.trim().is_empty() => {
                        let preview: String =
                            content.chars().take(MEMORY_PREVIEW_CHARS).collect();
                        memory_ctx.push_str(&preview);
                        if content.chars().count() > MEMORY_PREVIEW_CHARS {
                            memory_ctx.push_str("\n...(truncated)");
                        }
                    }
                    _ => memory_ctx.push_str("(empty)"),
                }
                memory_ctx.push('\n');
            }
            messages.push(crate::traits::Message {
                role: crate::traits::Role::User,
                content: memory_ctx,
            });
        }

        // Add conversation history
        for snapshot in &self.input.conversation_snapshot {
            let role = match snapshot.role.as_str() {
                "user" => crate::traits::Role::User,
                "assistant" => crate::traits::Role::Assistant,
                "system" => crate::traits::Role::System,
                _ => crate::traits::Role::User,
            };
            messages.push(crate::traits::Message {
                role,
                content: snapshot.content.clone(),
            });
        }

        let trailing_content = match self.input.review_type {
            ReviewType::Memory => "[System] The above is a conversation snapshot for your review. \
                      Analyze it for memory-worthy information and call review_memory \
                      if warranted, or explain why nothing needs to be remembered.",
            ReviewType::Skill => "[System] The above is a conversation snapshot for your review. \
                      Analyze it for skill evolution opportunities and call review_skill \
                      if warranted, or explain why no skill is needed.",
            ReviewType::Combined => "[System] The above is a conversation snapshot for your review. \
                      Analyze it for both memory-worthy information and skill evolution \
                      opportunities. Call review_memory or review_skill as appropriate.",
        };
        messages.push(crate::traits::Message {
            role: crate::traits::Role::User,
            content: trailing_content.to_string(),
        });

        messages
    }
}