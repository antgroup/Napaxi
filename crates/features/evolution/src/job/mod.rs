//! Background review job for the evolution subsystem.
//!
//! Drives the periodic review cycle: aggregates suggestions, runs the LLM
//! review handler, and emits suggested skill/memory actions through the
//! execution callback.

use crate::config::EvolutionConfig;
use crate::counter::NudgeState;
use crate::error::{EvolutionError, EvolutionResult};
use crate::queue::{PendingConfirmation, PendingQueue};
use crate::tools::{ReviewMemoryTool, ReviewSkillTool};
use crate::traits::{Job, JobContext, JobError, ToolRegistry};
use crate::types::{MessageSnapshot, PendingActionType, ReviewSource, ReviewType, SuggestedAction};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use tokio::fs;

mod aggregator;
mod helpers;
pub mod llm_integration;

pub use aggregator::SuggestionAggregator;

// Embedded prompt fallbacks for mobile/device deployment where
// CARGO_MANIFEST_DIR is not available at runtime.
const EMBEDDED_SKILL_REVIEW_PROMPT: &str = include_str!("../../prompts/skill_review.md");
const EMBEDDED_MEMORY_REVIEW_PROMPT: &str = include_str!("../../prompts/memory_review.md");
const LLM_DIAGNOSTIC_PREVIEW_CHARS: usize = 800;

/// LLM review result, containing the full response content
#[derive(Debug, Clone)]
pub struct ReviewResult {
    /// LLM text response content (for diagnostics)
    pub content: String,
    /// Tool call list
    pub tool_calls: Vec<(String, serde_json::Value)>,
}

/// LLM call interface abstraction
///
/// Allows integration with different LLM implementations (e.g., napaxi's LlmProvider)
#[async_trait]
pub trait LlmReviewHandler: Send + Sync {
    /// Call LLM for review, returning the full result (including content and tool_calls)
    async fn review(
        &self,
        messages: Vec<crate::traits::Message>,
        tools: &ToolRegistry,
        timeout_secs: u64,
    ) -> Result<ReviewResult, String>;
}

/// Default LLM Handler (does not perform actual calls, only logs)
pub struct DefaultLlmHandler;

#[async_trait]
impl LlmReviewHandler for DefaultLlmHandler {
    async fn review(
        &self,
        _messages: Vec<crate::traits::Message>,
        _tools: &ToolRegistry,
        _timeout_secs: u64,
    ) -> Result<ReviewResult, String> {
        Ok(ReviewResult {
            content: "No LLM handler configured".to_string(),
            tool_calls: vec![],
        })
    }
}

/// EvolutionReviewJob input parameters
#[derive(Debug, Clone)]
pub struct EvolutionReviewInput {
    /// Associated Thread ID
    pub thread_id: String,
    /// Review type
    pub review_type: ReviewType,
    /// Conversation history snapshot
    pub conversation_snapshot: Vec<MessageSnapshot>,
    /// Nudge state snapshot
    pub nudge_state: NudgeState,
    /// Turn count at trigger time
    pub trigger_turns: usize,
    /// Tool call count at trigger time
    pub trigger_tool_calls: usize,
    /// Existing memory content (grouped by entry_type), for LLM deduplication
    #[allow(clippy::zero_sized_map_values)]
    pub existing_memory: std::collections::HashMap<crate::types::MemoryEntryType, String>,
}

/// EvolutionReviewJob output result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionReviewOutput {
    pub job_id: String,
    pub review_type: ReviewType,
    pub suggestions_count: usize,
    #[serde(default)]
    pub auto_applied_count: usize,
    pub pending_ids: Vec<uuid::Uuid>,
    #[serde(default)]
    pub tool_calls: Vec<String>,
    pub completed_at: DateTime<Utc>,
    pub error: Option<String>,
    /// Bounded preview of LLM output, for diagnosing why no suggestions were produced.
    pub llm_summary: Option<String>,
}

impl Default for EvolutionReviewOutput {
    fn default() -> Self {
        Self {
            job_id: String::new(),
            review_type: ReviewType::Memory,
            suggestions_count: 0,
            auto_applied_count: 0,
            pending_ids: Vec::new(),
            tool_calls: Vec::new(),
            completed_at: Utc::now(),
            error: None,
            llm_summary: None,
        }
    }
}

/// Execution callback trait; the main flow implements the actual execution logic
#[async_trait]
pub trait ExecutionCallback: Send + Sync {
    /// Execute an action, returning the execution result message
    async fn execute(&self, action: &PendingActionType) -> Result<String, String>;
}

/// Skill evolution review Job
///
/// Implements the `Job` trait, reusing the existing Job execution system.
pub struct EvolutionReviewJob {
    input: EvolutionReviewInput,
    config: EvolutionConfig,
    pending_queue: Arc<PendingQueue>,
    llm_handler: Option<Arc<dyn LlmReviewHandler>>,
    /// Callback for executing high-confidence suggestions (injected by the main flow)
    /// If None, auto_apply will not execute and suggestions go to the pending queue for confirmation
    execution_callback: Option<Arc<dyn ExecutionCallback>>,
    /// Override the default skills directory (for mobile etc. where files_dir is used)
    skills_dir_override: Option<std::path::PathBuf>,
}

impl std::fmt::Debug for EvolutionReviewJob {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EvolutionReviewJob")
            .field("input", &self.input)
            .field("config", &self.config)
            .field("pending_queue", &self.pending_queue)
            .field(
                "llm_handler",
                &self.llm_handler.as_ref().map(|_| "<dyn LlmReviewHandler>"),
            )
            .finish()
    }
}

impl EvolutionReviewJob {
    pub fn new(
        input: EvolutionReviewInput,
        config: EvolutionConfig,
        pending_queue: Arc<PendingQueue>,
    ) -> Self {
        Self {
            input,
            config,
            pending_queue,
            llm_handler: None,
            execution_callback: None,
            skills_dir_override: None,
        }
    }

    /// Set LLM Handler (for actual review)
    pub fn with_llm_handler(mut self, handler: Arc<dyn LlmReviewHandler>) -> Self {
        self.llm_handler = Some(handler);
        self
    }

    /// Set Execution Callback (injected by the main flow, for executing high-confidence suggestions)
    pub fn with_execution_callback(mut self, callback: Arc<dyn ExecutionCallback>) -> Self {
        self.execution_callback = Some(callback);
        self
    }

    /// Override the default skills directory (for mobile files_dir scenario).
    ///
    /// When set, `inject_skill_list_into_prompt()` will use this directory
    /// instead of `get_user_skills_dir()` to read the existing skill list.
    pub fn with_skills_dir(mut self, dir: std::path::PathBuf) -> Self {
        self.skills_dir_override = Some(dir);
        self
    }

    /// Exported review entry point for external use.
    /// Does not depend on JobContext; can be called from any context.
    pub async fn perform_review(&self) -> EvolutionResult<EvolutionReviewOutput> {
        self.run_review_internal().await
    }

    /// Execute review logic (used internally by the Job trait)
    async fn run_review(&self, ctx: &JobContext) -> EvolutionResult<EvolutionReviewOutput> {
        self.run_review_internal_with_id(&ctx.job_id).await
    }

    /// Execute review logic (core implementation)
    async fn run_review_internal(&self) -> EvolutionResult<EvolutionReviewOutput> {
        // Generate temporary job_id
        let job_id = uuid::Uuid::new_v4().to_string();
        self.run_review_internal_with_id(&job_id).await
    }

    /// Execute review logic (with specified job_id)
    async fn run_review_internal_with_id(
        &self,
        job_id: &str,
    ) -> EvolutionResult<EvolutionReviewOutput> {
        let start_time = Utc::now();
        tracing::info!(
            job_id,
            review_type = ?self.input.review_type,
            thread_id = %self.input.thread_id,
            "[Evolution] Review job executing"
        );

        // 1. Check complexity threshold
        let tool_call_count = self
            .input
            .conversation_snapshot
            .iter()
            .filter(|m| m.role == "assistant")
            .count();

        tracing::info!(
            job_id,
            tool_calls = tool_call_count,
            threshold = self.config.security.min_complexity_threshold,
            "[Evolution] Checking complexity threshold"
        );

        if tool_call_count < self.config.security.min_complexity_threshold {
            tracing::info!(
                job_id,
                tool_calls = tool_call_count,
                threshold = self.config.security.min_complexity_threshold,
                "[Evolution] Skipping review: below complexity threshold"
            );
            return Ok(EvolutionReviewOutput {
                job_id: job_id.to_string(),
                review_type: self.input.review_type,
                suggestions_count: 0,
                auto_applied_count: 0,
                pending_ids: vec![],
                tool_calls: vec![],
                completed_at: Utc::now(),
                error: None,
                llm_summary: Some(format!(
                    "Skipped: conversation complexity {} below threshold {}",
                    tool_call_count, self.config.security.min_complexity_threshold
                )),
            });
        }

        // 2. Load system prompt from file
        let system_prompt_path = self.input.review_type.prompt_file();
        let system_prompt = match self.load_prompt_from_file(system_prompt_path).await {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("Failed to load prompt from file, using fallback: {}", e);
                self.load_prompt_fallback()?
            }
        };

        // 3. Build tool registry
        let tool_registry = self.build_tool_registry();

        // 4. Prepare messages
        let messages = self.build_review_messages(&system_prompt);

        // 5. Execute LLM call or simulation
        let (llm_content, tool_calls) = if let Some(ref handler) = self.llm_handler {
            // Actual LLM call
            match handler
                .review(messages, &tool_registry, self.config.review_timeout_secs)
                .await
            {
                Ok(result) => {
                    let content = result.content.clone();
                    let calls = result.tool_calls;
                    (content, calls)
                }
                Err(e) => {
                    tracing::error!("LLM review failed: {}", e);
                    return Ok(EvolutionReviewOutput {
                        job_id: job_id.to_string(),
                        review_type: self.input.review_type,
                        suggestions_count: 0,
                        auto_applied_count: 0,
                        pending_ids: vec![],
                        tool_calls: vec![],
                        completed_at: Utc::now(),
                        error: Some(format!("LLM review failed: {}", e)),
                        llm_summary: Some(format!("Error: {}", e)),
                    });
                }
            }
        } else {
            tracing::info!(
                job_id,
                review_type = ?self.input.review_type,
                "[Evolution] No LLM handler configured, returning empty suggestions"
            );
            ("No LLM handler configured".to_string(), vec![])
        };

        tracing::info!(
            job_id,
            tool_calls_count = tool_calls.len(),
            llm_content_len = llm_content.len(),
            tool_calls = ?tool_calls.iter().map(|(name, _)| name).collect::<Vec<_>>(),
            "[Evolution] LLM returned tool calls"
        );

        // 6. Parse tool calls, generating SuggestedAction (including confidence)
        let suggestions = match self.parse_tool_calls_with_confidence(&tool_calls).await {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(
                    job_id,
                    error = %e,
                    tool_calls = ?tool_calls,
                    "[Evolution] Failed to parse tool calls - possible format mismatch or validation failure"
                );
                return Ok(EvolutionReviewOutput {
                    job_id: job_id.to_string(),
                    review_type: self.input.review_type,
                    suggestions_count: 0,
                    auto_applied_count: 0,
                    pending_ids: vec![],
                    tool_calls: tool_calls.iter().map(|(name, _)| name.clone()).collect(),
                    completed_at: Utc::now(),
                    error: Some(format!("Failed to parse tool calls: {}", e)),
                    llm_summary: Some(format!("Parse error: {}", e)),
                });
            }
        };

        // Detailed logging of suggestions analysis
        if suggestions.is_empty() {
            tracing::warn!(
                job_id,
                tool_calls_count = tool_calls.len(),
                conversation_turns = self.input.conversation_snapshot.len(),
                review_type = ?self.input.review_type,
                "[Evolution] No suggestions generated from LLM tool calls - check if tool calls were valid and matched expected format"
            );
        } else {
            let high_conf = suggestions
                .iter()
                .filter(|s| matches!(s.confidence, crate::types::ConfidenceLevel::High))
                .count();
            let medium_conf = suggestions
                .iter()
                .filter(|s| matches!(s.confidence, crate::types::ConfidenceLevel::Medium))
                .count();
            let low_conf = suggestions
                .iter()
                .filter(|s| matches!(s.confidence, crate::types::ConfidenceLevel::Low))
                .count();

            tracing::info!(
                job_id,
                total_suggestions = suggestions.len(),
                high_confidence = high_conf,
                medium_confidence = medium_conf,
                low_confidence = low_conf,
                suggestions_by_confidence = ?suggestions.iter().map(|s| format!("{:?}", s.confidence)).collect::<Vec<_>>(),
                "[Evolution] Parsed suggestions from tool calls"
            );

            // Log detailed info for each suggestion
            for (i, suggestion) in suggestions.iter().enumerate() {
                tracing::info!(
                    index = i,
                    confidence = ?suggestion.confidence,
                    reasoning = %suggestion.reasoning,
                    action_type = %suggestion.action.action_type_name(),
                    "[Evolution] Suggestion detail"
                );
            }
        }

        // 7. Get existing pending for deduplication
        let existing_pending = self.pending_queue.get_pending().await;
        tracing::info!(
            job_id,
            existing_pending_count = existing_pending.len(),
            "[Evolution] Existing pending suggestions for deduplication"
        );

        // 8. Use SuggestionAggregator to aggregate and route
        let aggregator = SuggestionAggregator::new(
            self.config.security.similarity_threshold,
            self.config.security.max_suggestions_per_review,
        );

        let (aggregated, auto_execute_groups) =
            aggregator.aggregate(suggestions, &existing_pending);

        // Count actual high-confidence suggestions (original suggestions before aggregation)
        let auto_execute_count: usize = auto_execute_groups.iter().map(|g| g.actions.len()).sum();

        tracing::info!(
            job_id,
            aggregated_groups = aggregated.len(),
            auto_execute_groups = auto_execute_groups.len(),
            auto_execute_total_actions = auto_execute_count,
            auto_apply_enabled = self.config.security.auto_apply_high_confidence,
            similarity_threshold = self.config.security.similarity_threshold,
            "[Evolution] Aggregation complete"
        );

        // pending_ids needs to be accumulated throughout the process
        let mut pending_ids: Vec<uuid::Uuid> = Vec::new();

        // 9. Auto-execute high-confidence suggestions (if config enabled and execution_callback is set)
        let mut auto_executed: usize = 0;
        if self.config.security.auto_apply_high_confidence {
            if let Some(ref callback) = self.execution_callback {
                // Collect auto-apply failed actions to enqueue to pending later
                let mut failed_actions: Vec<(PendingActionType, String)> = Vec::new();

                for group in &auto_execute_groups {
                    tracing::info!(
                        group_actions = group.actions.len(),
                        confidence = ?group.confidence,
                        "[Evolution] Auto-executing high confidence group"
                    );

                    // Group by action type; same-type actions are batched
                    let mut memory_groups: std::collections::HashMap<
                        crate::types::MemoryEntryType,
                        Vec<String>,
                    > = std::collections::HashMap::new();
                    let mut other_actions: Vec<PendingActionType> = Vec::new();

                    for action in &group.actions {
                        match action {
                            PendingActionType::MemoryWrite {
                                entry_type,
                                content,
                            } => {
                                memory_groups
                                    .entry(*entry_type)
                                    .or_default()
                                    .push(content.clone());
                            }
                            other => {
                                other_actions.push(other.clone());
                            }
                        }
                    }

                    // Execute MemoryWrite actions individually, ensuring each memory has an independent entry header
                    for (entry_type, contents) in memory_groups {
                        tracing::info!(
                            entry_type = ?entry_type,
                            content_count = contents.len(),
                            "[Evolution] Executing MemoryWrite actions individually"
                        );

                        for content in &contents {
                            let single_action = PendingActionType::MemoryWrite {
                                entry_type,
                                content: content.clone(),
                            };
                            match callback.execute(&single_action).await {
                                Ok(message) => {
                                    auto_executed += 1;
                                    tracing::info!(
                                        message = message,
                                        "[Evolution] MemoryWrite auto-execution successful"
                                    );
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        error = %e,
                                        "[Evolution] MemoryWrite auto-execution failed, will queue to pending"
                                    );
                                    failed_actions.push((single_action, e));
                                }
                            }
                        }
                    }

                    // Execute other action types (one by one)
                    for action in other_actions {
                        match callback.execute(&action).await {
                            Ok(message) => {
                                auto_executed += 1;
                                tracing::info!(
                                    message = message,
                                    "[Evolution] Auto-execution successful"
                                );
                            }
                            Err(e) => {
                                tracing::warn!(
                                    error = %e,
                                    action_type = action.action_type_name(),
                                    "[Evolution] Auto-execution failed, will queue to pending"
                                );
                                // Record failed action to add to pending later
                                failed_actions.push((action, e));
                            }
                        }
                    }
                }

                // Add auto-apply failed actions to pending queue (create separate confirmations)
                for (failed_action, error) in failed_actions {
                    let mut confirmation = PendingConfirmation::new(
                        failed_action.clone(),
                        ReviewSource {
                            job_id: job_id.to_string(),
                            triggered_at: start_time,
                            review_type: self.input.review_type,
                        },
                        format!(
                            "Auto-apply failed: {}. Please review and confirm manually.",
                            error
                        ),
                        self.input.thread_id.clone(),
                    );
                    // Store all aggregated actions
                    confirmation.aggregated_actions = vec![failed_action.clone()];

                    let id = self.pending_queue.push(confirmation).await;
                    pending_ids.push(id);
                    tracing::info!(
                        pending_id = ?id,
                        action_type = failed_action.action_type_name(),
                        "[Evolution] Failed auto-apply action moved to pending queue"
                    );
                }
            } else {
                // auto_apply enabled but no callback; high-confidence suggestions go to pending queue for confirmation
                tracing::info!(
                    high_conf_groups = auto_execute_groups.len(),
                    high_conf_total_actions = auto_execute_count,
                    "[Evolution] Auto-apply enabled but no callback configured, queuing high confidence groups"
                );
                queue_auto_execute_groups(
                    &self.pending_queue,
                    &auto_execute_groups,
                    job_id,
                    start_time,
                    &self.input.thread_id,
                    self.input.review_type,
                    &mut pending_ids,
                )
                .await;
            }
        } else {
            // When auto-apply config is disabled, high-confidence suggestions also go to the queue
            tracing::info!(
                high_conf_groups = auto_execute_groups.len(),
                high_conf_total_actions = auto_execute_count,
                "[Evolution] Auto-apply disabled, queuing high confidence groups"
            );
        }

        // 10. Add aggregated medium/low-confidence suggestions to the pending confirmation queue
        // pending_ids already contains auto-apply failed actions (if any)

        // When auto_apply is off, high-confidence groups also go to pending (added by group)
        if !self.config.security.auto_apply_high_confidence {
            queue_auto_execute_groups(
                &self.pending_queue,
                &auto_execute_groups,
                job_id,
                start_time,
                &self.input.thread_id,
                self.input.review_type,
                &mut pending_ids,
            )
            .await;
        }
        // 10. Add aggregated medium/low-confidence suggestions to the pending confirmation queue
        for agg in aggregated {
            // The first action of each aggregated suggestion serves as the representative
            if let Some(action) = agg.actions.first() {
                tracing::info!(
                    action = ?action,
                    confidence = ?agg.confidence,
                    actions_count = agg.actions.len(),
                    "[Evolution] Aggregated suggestion queued"
                );

                let mut confirmation = PendingConfirmation::new(
                    action.clone(),
                    ReviewSource {
                        job_id: job_id.to_string(),
                        triggered_at: start_time,
                        review_type: self.input.review_type,
                    },
                    agg.reasoning,
                    self.input.thread_id.clone(),
                );
                // Store all aggregated actions
                confirmation.aggregated_actions = agg.actions.clone();

                let id = self.pending_queue.push(confirmation).await;
                pending_ids.push(id);
            }
        }

        // 11. Return result
        // total_suggestions is aggregated group count + auto-executed original suggestion count
        let total_groups = pending_ids.len();
        let total_suggestions = total_groups + auto_executed;

        let llm_summary = Some(bounded_text_preview(
            &llm_content,
            LLM_DIAGNOSTIC_PREVIEW_CHARS,
        ));

        tracing::info!(
            job_id,
            llm_content_preview = %llm_content.chars().take(300).collect::<String>(),
            "[Evolution] LLM review content (full content available in llm_summary)"
        );

        let output = EvolutionReviewOutput {
            job_id: job_id.to_string(),
            review_type: self.input.review_type,
            suggestions_count: total_suggestions,
            auto_applied_count: auto_executed,
            pending_ids: pending_ids.clone(),
            tool_calls: tool_calls.iter().map(|(name, _)| name.clone()).collect(),
            completed_at: Utc::now(),
            error: None,
            llm_summary,
        };

        // If no suggestions were produced, log detailed diagnostic info
        if total_suggestions == 0 {
            // Detailed diagnostic logs, using multi-line printing to avoid truncation
            tracing::warn!(
                job_id,
                "[Evolution] ========== NO SUGGESTIONS DIAGNOSTIC =========="
            );
            tracing::warn!(job_id, review_type = ?output.review_type, "[Evolution] Review type");
            tracing::warn!(
                job_id,
                conversation_turns = self.input.conversation_snapshot.len(),
                "[Evolution] Conversation turns"
            );
            tracing::warn!(
                job_id,
                assistant_message_count = tool_call_count,
                "[Evolution] Assistant message (tool call) count"
            );
            tracing::warn!(
                job_id,
                complexity_threshold = self.config.security.min_complexity_threshold,
                "[Evolution] Complexity threshold"
            );
            tracing::warn!(
                job_id,
                tool_calls_received = tool_calls.len(),
                "[Evolution] Raw tool calls from LLM"
            );
            tracing::warn!(
                job_id,
                auto_apply = self.config.security.auto_apply_high_confidence,
                "[Evolution] Auto-apply enabled"
            );
            tracing::warn!(job_id, llm_content = %llm_content, "[Evolution] Full LLM response content");
            if !tool_calls.is_empty() {
                for (i, (name, args)) in tool_calls.iter().enumerate() {
                    tracing::warn!(job_id, index = i, tool_name = name, args = %args, "[Evolution] Raw tool call from LLM");
                }
            }
            tracing::warn!(job_id, "[Evolution] ========== END DIAGNOSTIC ==========");
        } else {
            tracing::info!(
                job_id,
                review_type = ?output.review_type,
                suggestions_count = output.suggestions_count,
                pending_groups = total_groups,
                auto_executed_actions = auto_executed,
                auto_apply_enabled = self.config.security.auto_apply_high_confidence,
                "[Evolution] Review job completed successfully"
            );
        }

        Ok(output)
    }
}

async fn queue_auto_execute_groups(
    pending_queue: &Arc<PendingQueue>,
    groups: &[crate::types::AggregatedSuggestion],
    job_id: &str,
    start_time: DateTime<Utc>,
    thread_id: &str,
    review_type: ReviewType,
    pending_ids: &mut Vec<uuid::Uuid>,
) {
    for group in groups {
        let Some(action) = group.actions.first() else {
            continue;
        };
        let mut confirmation = PendingConfirmation::new(
            action.clone(),
            ReviewSource {
                job_id: job_id.to_string(),
                triggered_at: start_time,
                review_type,
            },
            format!(
                "{} (aggregated {} related suggestions)",
                group.reasoning,
                group.actions.len()
            ),
            thread_id.to_string(),
        );
        confirmation.aggregated_actions = group.actions.clone();
        let id = pending_queue.push(confirmation).await;
        pending_ids.push(id);
    }
}

fn bounded_text_preview(text: &str, max_chars: usize) -> String {
    let mut chars = text.chars();
    let preview: String = chars.by_ref().take(max_chars).collect();
    let omitted = chars.count();
    if omitted == 0 {
        preview
    } else {
        format!("{preview}... (truncated, {omitted} chars omitted)")
    }
}

#[async_trait]
impl Job for EvolutionReviewJob {
    type Output = EvolutionReviewOutput;

    /// Job execution entry point
    async fn execute(&self, ctx: &JobContext) -> Result<Self::Output, JobError> {
        let result = self.run_review(ctx).await;

        match result {
            Ok(output) => Ok(output),
            Err(e) => {
                tracing::error!(error = %e, "Evolution review failed");
                // Return partial result, do not propagate error
                Ok(EvolutionReviewOutput {
                    job_id: ctx.job_id.clone(),
                    review_type: self.input.review_type,
                    suggestions_count: 0,
                    auto_applied_count: 0,
                    pending_ids: vec![],
                    tool_calls: vec![],
                    completed_at: Utc::now(),
                    error: Some(e.to_string()),
                    llm_summary: Some(format!("Job error: {}", e)),
                })
            }
        }
    }

    fn job_type() -> &'static str {
        "evolution_review"
    }

    fn timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.config.review_timeout_secs)
    }
}
#[cfg(test)]
mod tests;
