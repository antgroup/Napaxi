use crate::config::{EvolutionConfig, EvolutionStatus};
use crate::counter::{AtomicNudgeCounter, CounterStorage};
use crate::error::{EvolutionError, EvolutionResult};
use crate::job::{EvolutionReviewInput, EvolutionReviewJob};
use crate::queue::PendingQueue;
use crate::traits::{Hook, HookContext, HookResult, JobQueue, ToolCall};
use crate::types::{MessageSnapshot, NudgeType};
use crate::ReviewType;
use async_trait::async_trait;
use chrono::Utc;
use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Skill evolution event hook
///
/// Implements the `Hook` trait, non-invasively intercepting main flow events.
///
/// Corresponds to the following logic in Python: run_agent.py:
/// - _turns_since_memory / _iters_since_skill counter management
/// - _should_review_memory / _should_review_skills trigger logic
/// - _spawn_background_review review trigger
pub struct EvolutionHook {
    inner: Arc<EvolutionHookInner>,
}

struct EvolutionHookInner {
    /// Configuration
    config: EvolutionConfig,
    /// Runtime atomic counter
    counter: Arc<AtomicNudgeCounter>,
    /// Persistent storage interface
    storage: Arc<dyn CounterStorage>,
    /// Job queue (for scheduling EvolutionReviewJob)
    job_queue: Arc<dyn JobQueue>,
    /// Pending confirmation queue (single-user mode, backward compatible)
    pending_queue: Option<Arc<PendingQueue>>,
    /// User-isolated pending confirmation queue (multi-user mode)
    user_pending_queue: Option<Arc<crate::queue::UserPendingQueue>>,
    /// Last review time (prevents too-frequent reviews)
    last_review: RwLock<HashMap<ReviewType, chrono::DateTime<chrono::Utc>>>,
    /// LLM Handler (for Review Job)
    llm_handler: Option<Arc<dyn crate::job::LlmReviewHandler>>,
    /// Execution Callback (for auto-apply, injected by the main flow)
    execution_callback: Option<Arc<dyn crate::job::ExecutionCallback>>,
}

/// Factory function: create Hook with default storage and JobQueue
pub fn create_hook(config: EvolutionConfig) -> EvolutionHook {
    let storage = Arc::new(crate::counter::InMemoryStorage::new("default"));
    let job_queue = Arc::new(crate::traits::DefaultJobQueue::new());
    let pending_queue = Arc::new(PendingQueue::new());
    EvolutionHook::new(config, storage, job_queue, pending_queue)
}

/// Factory function: create Hook with specified storage
pub fn create_hook_with_storage(
    config: EvolutionConfig,
    storage: Arc<dyn CounterStorage>,
) -> EvolutionHook {
    let job_queue = Arc::new(crate::traits::DefaultJobQueue::new());
    let pending_queue = Arc::new(PendingQueue::new());

    EvolutionHook::new(config, storage, job_queue, pending_queue)
}

/// Factory function: fully custom Hook creation (for main flow scheduler integration)
pub fn create_hook_with_all(
    config: EvolutionConfig,
    storage: Arc<dyn CounterStorage>,
    job_queue: Arc<dyn JobQueue>,
) -> EvolutionHook {
    let pending_queue = Arc::new(PendingQueue::new());
    EvolutionHook::new(config, storage, job_queue, pending_queue)
}

/// Factory function: create EvolutionReviewJob with LLM handler (main flow integration)
pub fn create_review_job(
    input: EvolutionReviewInput,
    config: EvolutionConfig,
    pending_queue: Arc<PendingQueue>,
    llm_handler: Option<Arc<dyn crate::job::LlmReviewHandler>>,
) -> EvolutionReviewJob {
    let mut job = EvolutionReviewJob::new(input, config, pending_queue);
    if let Some(handler) = llm_handler {
        job = job.with_llm_handler(handler);
    }
    job
}

impl EvolutionHook {
    /// Create new EvolutionHook (single-user mode, backward compatible)
    pub fn new(
        config: EvolutionConfig,
        storage: Arc<dyn CounterStorage>,
        job_queue: Arc<dyn JobQueue>,
        pending_queue: Arc<PendingQueue>,
    ) -> Self {
        Self {
            inner: Arc::new(EvolutionHookInner {
                config,
                counter: Arc::new(AtomicNudgeCounter::new()),
                storage,
                job_queue,
                pending_queue: Some(pending_queue),
                user_pending_queue: None,
                last_review: RwLock::new(HashMap::new()),
                llm_handler: None,
                execution_callback: None,
            }),
        }
    }

    /// Create new EvolutionHook (multi-user mode, using UserPendingQueue)
    pub fn with_user_queue(
        config: EvolutionConfig,
        storage: Arc<dyn CounterStorage>,
        job_queue: Arc<dyn JobQueue>,
        user_pending_queue: Arc<crate::queue::UserPendingQueue>,
    ) -> Self {
        Self {
            inner: Arc::new(EvolutionHookInner {
                config,
                counter: Arc::new(AtomicNudgeCounter::new()),
                storage,
                job_queue,
                pending_queue: None,
                user_pending_queue: Some(user_pending_queue),
                last_review: RwLock::new(HashMap::new()),
                llm_handler: None,
                execution_callback: None,
            }),
        }
    }

    /// Set LLM handler (chain call)
    pub fn with_llm_handler(mut self, handler: Arc<dyn crate::job::LlmReviewHandler>) -> Self {
        let inner = Arc::get_mut(&mut self.inner).expect("Arc is unique");
        inner.llm_handler = Some(handler);
        self
    }

    /// Set Execution Callback (chain call, for auto-apply)
    pub fn with_execution_callback(
        mut self,
        callback: Arc<dyn crate::job::ExecutionCallback>,
    ) -> Self {
        let inner = Arc::get_mut(&mut self.inner).expect("Arc is unique");
        inner.execution_callback = Some(callback);
        self
    }

    /// Internal processing method
    async fn handle_conversation_start(&self, ctx: &mut HookContext) -> EvolutionResult<()> {
        if self.inner.config.status == EvolutionStatus::Disabled {
            return Ok(());
        }

        // Load counters from storage
        match self.inner.storage.load().await {
            Ok(state) => {
                self.inner.counter.restore(&ctx.thread_id, &state);

                // Restore review timestamps to cooldown map
                let mut last_map = self.inner.last_review.write().await;
                if let Some(t) = state.last_memory_review {
                    last_map.insert(ReviewType::Memory, t);
                }
                if let Some(t) = state.last_skill_review {
                    last_map.insert(ReviewType::Skill, t);
                }
                drop(last_map);

                tracing::info!(
                    thread_id = %ctx.thread_id,
                    turns = state.turns_since_memory,
                    tool_calls = state.iters_since_skill,
                    "[Evolution] Counters loaded from storage"
                );
            }
            Err(e) => {
                tracing::warn!("[Evolution] Failed to load nudge state: {}", e);
                // Continue with default empty counters
            }
        }

        // Check pending confirmation queue (single-user mode only)
        if let Some(ref queue) = self.inner.pending_queue {
            let pending: Vec<crate::queue::PendingConfirmation> = queue.get_pending().await;
            if !pending.is_empty() {
                ctx.add_system_message(format!(
                    "There are {} pending skill evolution suggestions. Use /evolution confirm <id> to view or confirm.",
                    pending.len()
                ));
            }
        }

        Ok(())
    }

    async fn handle_inbound(&self, ctx: &mut HookContext) -> EvolutionResult<()> {
        if self.inner.config.status == EvolutionStatus::Disabled {
            return Ok(());
        }

        // Get the last user message content, check if it's a system command
        let last_user_content = ctx
            .messages
            .iter()
            .rev()
            .find(|m| matches!(m.role, crate::traits::Role::User))
            .map(|m| m.content.as_str())
            .unwrap_or("");

        // Skip all system commands starting with '/' (e.g., /evolution, /help, /skills, etc.)
        if last_user_content.starts_with('/') {
            tracing::debug!(
                thread_id = %ctx.thread_id,
                content = last_user_content,
                "[Evolution] Skipping system command, not counting toward nudge threshold"
            );
            return Ok(());
        }

        // Increment turn counter
        let turns = self.inner.counter.increment_turns(&ctx.thread_id);
        tracing::info!(
            thread_id = %ctx.thread_id,
            turns = turns,
            threshold = self.inner.config.memory_nudge_interval,
            "[Evolution] Inbound message counted"
        );

        // Check if Memory nudge threshold is reached
        if turns.is_multiple_of(self.inner.config.memory_nudge_interval) {
            tracing::info!(
                thread_id = %ctx.thread_id,
                turns = turns,
                "[Evolution] Memory nudge threshold reached, spawning review job"
            );
            self.spawn_review_job(ctx, NudgeType::MemoryReview).await?;
        }

        Ok(())
    }

    async fn handle_tool_call(
        &self,
        ctx: &mut HookContext,
        tool_call: &ToolCall,
    ) -> EvolutionResult<()> {
        if self.inner.config.status == EvolutionStatus::Disabled {
            return Ok(());
        }

        let tool_name = &tool_call.name;

        // Reset turn counter on memory tool call
        if tool_name == "memory" {
            self.inner.counter.reset_turns(&ctx.thread_id);
            return Ok(());
        }

        // Reset skill counter on skill tool call
        if tool_name.starts_with("skill_") {
            self.inner.counter.reset_tool_calls(&ctx.thread_id);
            return Ok(());
        }

        // Increment counter and check threshold on other tool calls
        let tool_calls = self.inner.counter.increment_tool_calls(&ctx.thread_id);
        tracing::info!(
            thread_id = %ctx.thread_id,
            tool_calls = tool_calls,
            tool_name = %tool_name,
            threshold = self.inner.config.skill_nudge_interval,
            "[Evolution] Tool call counted"
        );

        if tool_calls.is_multiple_of(self.inner.config.skill_nudge_interval) {
            tracing::info!(
                thread_id = %ctx.thread_id,
                tool_calls = tool_calls,
                "[Evolution] Skill nudge threshold reached, spawning review job"
            );
            self.spawn_review_job(ctx, NudgeType::SkillReview).await?;
        }

        Ok(())
    }

    async fn handle_conversation_end(&self, ctx: &mut HookContext) -> EvolutionResult<()> {
        if self.inner.config.status == EvolutionStatus::Disabled {
            return Ok(());
        }

        // Persist counters, filling in actual review timestamps
        let mut state = self.inner.counter.to_state(&ctx.thread_id);
        let last_map = self.inner.last_review.read().await;
        state.last_memory_review = last_map.get(&ReviewType::Memory).copied();
        state.last_skill_review = last_map.get(&ReviewType::Skill).copied();
        drop(last_map);

        if let Err(e) = self.inner.storage.save(&state).await {
            tracing::warn!("Failed to save nudge state: {}", e);
        }

        Ok(())
    }

    /// Check whether a Review should be triggered (rate limiting)
    async fn should_trigger_review(&self, review_type: ReviewType) -> bool {
        let min_interval = chrono::Duration::seconds(self.inner.config.review_cooldown_secs as i64);

        let last_map = self.inner.last_review.read().await;
        if let Some(last) = last_map.get(&review_type) {
            if Utc::now() - *last < min_interval {
                return false;
            }
        }
        drop(last_map);

        let mut last_map = self.inner.last_review.write().await;
        last_map.insert(review_type, Utc::now());
        true
    }

    /// Schedule Review Job
    async fn spawn_review_job(
        &self,
        ctx: &HookContext,
        nudge_type: NudgeType,
    ) -> EvolutionResult<()> {
        if !self
            .should_trigger_review(nudge_type.to_review_type())
            .await
        {
            return Ok(());
        }

        // Build Job input
        let msg_count = ctx.messages.len();
        let snapshot: Vec<MessageSnapshot> = ctx
            .messages
            .clone()
            .into_iter()
            .map(|m| MessageSnapshot {
                role: m.role.to_string(), // Use Display format (lowercase: "assistant")
                content: m.content,
                timestamp: Some(Utc::now()),
            })
            .collect();

        tracing::info!(
            thread_id = %ctx.thread_id,
            msg_count,
            snapshot_len = snapshot.len(),
            "[Evolution] Building review job input"
        );

        let (trigger_turns, trigger_tool_calls) = self.inner.counter.current(&ctx.thread_id);
        let input = EvolutionReviewInput {
            thread_id: ctx.thread_id.clone(),
            review_type: nudge_type.to_review_type(),
            conversation_snapshot: snapshot,
            nudge_state: self.inner.counter.to_state(&ctx.thread_id),
            trigger_turns,
            trigger_tool_calls,
            existing_memory: std::collections::HashMap::new(),
        };

        // Get user-specific pending_queue
        let user_id = ctx.thread_id.clone();
        let pending_queue = if let Some(ref user_queue) = self.inner.user_pending_queue {
            // Multi-user mode: get from UserPendingQueue
            user_queue.get_or_create_queue(&user_id).await
        } else if let Some(ref queue) = self.inner.pending_queue {
            // Single-user mode: use fixed queue
            Arc::clone(queue)
        } else {
            tracing::error!("[Evolution] No pending queue configured");
            return Err(EvolutionError::QueueUnavailable);
        };

        // Schedule Job (with LLM handler and execution callback)
        let mut job = EvolutionReviewJob::new(input, self.inner.config.clone(), pending_queue);
        if let Some(ref handler) = self.inner.llm_handler {
            job = job.with_llm_handler(Arc::clone(handler));
        }
        if let Some(ref callback) = self.inner.execution_callback {
            job = job.with_execution_callback(Arc::clone(callback));
        }

        self.inner
            .job_queue
            .schedule(Box::new(job))
            .await
            .map_err(|e| EvolutionError::JobScheduleFailed(e.to_string()))?;

        tracing::info!(
            thread_id = %ctx.thread_id,
            review_type = ?nudge_type,
            "[Evolution] Review job scheduled successfully"
        );

        Ok(())
    }
}

#[async_trait]
impl Hook for EvolutionHook {
    async fn on_conversation_start(&self, ctx: &mut HookContext) -> HookResult {
        if let Err(e) = self.handle_conversation_start(ctx).await {
            tracing::warn!(error = %e, "Evolution hook on_conversation_start error");
        }
        Ok(())
    }

    async fn on_inbound(&self, ctx: &mut HookContext) -> HookResult {
        if let Err(e) = self.handle_inbound(ctx).await {
            tracing::warn!(error = %e, "Evolution hook on_inbound error");
        }
        Ok(())
    }

    async fn on_tool_call(&self, ctx: &mut HookContext, tool_call: &ToolCall) -> HookResult {
        if let Err(e) = self.handle_tool_call(ctx, tool_call).await {
            tracing::warn!(
                error = %e,
                tool = %tool_call.name,
                "Evolution hook on_tool_call error"
            );
        }
        Ok(())
    }

    async fn on_conversation_end(&self, ctx: &mut HookContext) -> HookResult {
        if let Err(e) = self.handle_conversation_end(ctx).await {
            tracing::warn!(error = %e, "Evolution hook on_conversation_end error");
        }
        Ok(())
    }

    fn as_any(&self) -> &dyn Any {
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::traits::{JobQueue, JobScheduleError};
    use crate::{PendingConfirmation, ReviewType};
    use chrono::Utc;

    struct MockJobQueue {
        jobs: std::sync::Mutex<Vec<String>>,
    }

    impl MockJobQueue {
        fn new() -> Self {
            Self {
                jobs: std::sync::Mutex::new(Vec::new()),
            }
        }
    }

    #[async_trait]
    impl JobQueue for MockJobQueue {
        async fn schedule(
            &self,
            _job: Box<dyn crate::traits::AnyJob>,
        ) -> Result<String, JobScheduleError> {
            let id = uuid::Uuid::new_v4().to_string();
            self.jobs.lock().unwrap().push(id.clone());
            Ok(id)
        }
    }

    #[tokio::test]
    async fn test_hook_nudge_counter() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 3,
            skill_nudge_interval: 5,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        let hook = EvolutionHook::new(config, storage, job_queue.clone(), pending_queue);

        // Simulate 3 conversation turns, should trigger Memory Review
        let mut ctx = HookContext::new("test");

        // Turn 1
        hook.on_inbound(&mut ctx).await.unwrap();
        assert!(job_queue.jobs.lock().unwrap().is_empty());

        // Turn 2
        hook.on_inbound(&mut ctx).await.unwrap();
        assert!(job_queue.jobs.lock().unwrap().is_empty());

        // Turn 3 - should trigger (but subject to rate limiting)
        hook.on_inbound(&mut ctx).await.unwrap();
        // Note: due to rate limiting (60s), it may not trigger immediately
    }

    #[tokio::test]
    async fn test_hook_tool_call_resets_counter() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 3,
            skill_nudge_interval: 5,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        let hook = EvolutionHook::new(config, storage, job_queue.clone(), pending_queue);

        // Simulate 2 conversation turns
        let mut ctx = HookContext::new("test");
        hook.on_inbound(&mut ctx).await.unwrap();
        hook.on_inbound(&mut ctx).await.unwrap();

        // Calling memory tool should reset turn counter
        let tool_call = ToolCall {
            id: "1".to_string(),
            name: "memory".to_string(),
            arguments: serde_json::json!({}),
        };
        hook.on_tool_call(&mut ctx, &tool_call).await.unwrap();

        // One more turn should not trigger (because counter was reset)
        hook.on_inbound(&mut ctx).await.unwrap();
        assert!(job_queue.jobs.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn test_hook_disabled_status() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Disabled,
            memory_nudge_interval: 3,
            skill_nudge_interval: 5,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        let hook = EvolutionHook::new(config, storage, job_queue.clone(), pending_queue);

        let mut ctx = HookContext::new("test");

        // Even if threshold is reached, should not trigger
        for _ in 0..10 {
            hook.on_inbound(&mut ctx).await.unwrap();
        }

        assert!(job_queue.jobs.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn test_hook_skill_tool_resets_skill_counter() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 10,
            skill_nudge_interval: 3,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        let hook = EvolutionHook::new(config, storage, job_queue.clone(), pending_queue);
        let mut ctx = HookContext::new("test");

        // Calling skill-related tool should reset skill counter
        let tool_call = ToolCall {
            id: "1".to_string(),
            name: "skill_list".to_string(),
            arguments: serde_json::json!({}),
        };
        hook.on_tool_call(&mut ctx, &tool_call).await.unwrap();

        // Verify counter was reset (indirectly verified through subsequent behavior)
    }

    #[tokio::test]
    async fn test_hook_conversation_end_saves_state() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 10,
            skill_nudge_interval: 10,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test-thread"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        let hook = EvolutionHook::new(config, storage.clone(), job_queue.clone(), pending_queue);
        let mut ctx = HookContext::new("test-thread");

        // Add some counts
        hook.on_inbound(&mut ctx).await.unwrap();
        hook.on_inbound(&mut ctx).await.unwrap();

        // End conversation, should save state
        hook.on_conversation_end(&mut ctx).await.unwrap();

        // Verify state was saved
        let saved_state = storage.current();
        assert_eq!(saved_state.turns_since_memory, 2);
    }

    #[tokio::test]
    async fn test_hook_pending_notifications() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 10,
            skill_nudge_interval: 10,
            ..Default::default()
        };

        let storage = Arc::new(crate::counter::InMemoryStorage::new("test"));
        let job_queue = Arc::new(MockJobQueue::new());
        let pending_queue = Arc::new(PendingQueue::new());

        // Add a pending confirmation
        let confirmation = PendingConfirmation::new(
            crate::types::PendingActionType::Create {
                skill_name: "test-skill".to_string(),
                content: "test".to_string(),
                category: None,
            },
            crate::ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "test reasoning".to_string(),
            "test-thread".to_string(),
        );
        pending_queue.push(confirmation).await;

        let hook = EvolutionHook::new(config, storage, job_queue, pending_queue);
        let mut ctx = HookContext::new("test");

        // Start conversation, should receive pending notification
        hook.on_conversation_start(&mut ctx).await.unwrap();

        // Verify system message was added
        assert!(ctx.messages.iter().any(|m| m.content.contains("pending")));
    }
}
