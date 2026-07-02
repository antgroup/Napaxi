//! napaxi `LlmProvider`-backed review handler. Split out of `job/mod.rs`;
//! re-exported as `job::llm_integration` for API compatibility.

use super::*;
use crate::traits::{LlmProvider, Message as LlmMessage, Role};

/// Review handler implementation backed by napaxi LlmProvider
pub struct NapaxiLlmHandler {
    provider: Arc<dyn LlmProvider>,
}

impl NapaxiLlmHandler {
    pub fn new(provider: Arc<dyn LlmProvider>) -> Self {
        Self { provider }
    }
}

#[async_trait]
impl super::LlmReviewHandler for NapaxiLlmHandler {
    async fn review(
        &self,
        messages: Vec<crate::traits::Message>,
        tools: &ToolRegistry,
        timeout_secs: u64,
    ) -> Result<super::ReviewResult, String> {
        // Convert message format
        let llm_messages: Vec<LlmMessage> = messages
            .into_iter()
            .filter_map(|m| {
                let role = match m.role {
                    crate::traits::Role::System => Role::System,
                    crate::traits::Role::User => Role::User,
                    crate::traits::Role::Assistant => Role::Assistant,
                    crate::traits::Role::Tool => {
                        // Tool role messages are not forwarded (simplified handling)
                        return None;
                    }
                };
                Some(LlmMessage {
                    role,
                    content: m.content,
                })
            })
            .collect();

        // Call LLM (using tool use mode)
        tracing::info!(
            message_count = llm_messages.len(),
            timeout_secs = timeout_secs,
            "[Evolution] Calling LLM for review..."
        );

        let response = self
            .provider
            .complete_with_tools(&llm_messages, tools.list(), timeout_secs as f64)
            .await
            .map_err(|e| format!("LLM call failed: {}", e))?;

        // Log full LLM response (including text content and tool calls)
        tracing::info!(
            content_len = response.content.len(),
            tool_calls_count = response.tool_calls.len(),
            content_preview = %response.content.chars().take(200).collect::<String>(),
            "[Evolution] LLM response received"
        );

        // Print full LLM response content (for diagnostics)
        tracing::info!(
            content = %response.content,
            "[Evolution] LLM full response content"
        );

        // If no tool calls, log a warning (for diagnosing why no suggestion was produced)
        if response.tool_calls.is_empty() {
            tracing::warn!(
                content = %response.content,
                "[Evolution] LLM returned no tool calls - review produced no suggestions"
            );
        } else {
            // Log details of each tool call
            for (i, call) in response.tool_calls.iter().enumerate() {
                tracing::info!(
                    index = i,
                    tool_name = %call.name,
                    arguments_preview = %serde_json::to_string(&call.arguments).unwrap_or_default().chars().take(100).collect::<String>(),
                    "[Evolution] LLM tool call"
                );
            }
        }

        // Parse tool_calls
        let mut tool_calls = Vec::new();
        for call in response.tool_calls {
            tool_calls.push((call.name, call.arguments));
        }

        Ok(super::ReviewResult {
            content: response.content,
            tool_calls,
        })
    }
}
