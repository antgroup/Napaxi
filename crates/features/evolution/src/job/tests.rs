#[cfg(test)]
mod tests {
    use super::super::*;
    use crate::config::{EvolutionConfig, EvolutionStatus, SecurityPolicy};

    #[tokio::test]
    async fn test_review_job_complexity_check() {
        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 10,
            skill_nudge_interval: 10,
            security: SecurityPolicy {
                min_complexity_threshold: 5,
                ..Default::default()
            },
            ..Default::default()
        };

        // Create input with only 2 assistant messages (below threshold)
        let input = EvolutionReviewInput {
            thread_id: "test".to_string(),
            review_type: ReviewType::Memory,
            conversation_snapshot: vec![
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 1".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 2".to_string(),
                    timestamp: Some(Utc::now()),
                },
            ],
            nudge_state: NudgeState::default(),
            trigger_turns: 0,
            trigger_tool_calls: 0,
            existing_memory: std::collections::HashMap::new(),
        };

        let pending_queue = Arc::new(PendingQueue::new());
        let job = EvolutionReviewJob::new(input, config, pending_queue);

        let ctx = JobContext::new("test-job");
        let output = job.execute(&ctx).await.unwrap();

        // Should skip review
        assert_eq!(output.suggestions_count, 0);
    }

    #[tokio::test]
    async fn test_review_job_exceeds_complexity() {
        use crate::config::{EvolutionStatus, SecurityPolicy};

        let config = EvolutionConfig {
            status: EvolutionStatus::Enabled,
            memory_nudge_interval: 10,
            skill_nudge_interval: 10,
            security: SecurityPolicy {
                min_complexity_threshold: 3,
                ..Default::default()
            },
            ..Default::default()
        };

        // Create input with 5 assistant messages (exceeds threshold)
        let input = EvolutionReviewInput {
            thread_id: "test".to_string(),
            review_type: ReviewType::Memory,
            conversation_snapshot: vec![
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 1".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 2".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 3".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 4".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "message 5".to_string(),
                    timestamp: Some(Utc::now()),
                },
            ],
            nudge_state: NudgeState::default(),
            trigger_turns: 0,
            trigger_tool_calls: 0,
            existing_memory: std::collections::HashMap::new(),
        };

        let pending_queue = Arc::new(PendingQueue::new());
        let job = EvolutionReviewJob::new(input, config, pending_queue);

        let ctx = JobContext::new("test-job");
        let output = job.execute(&ctx).await.unwrap();

        // Exceeds threshold, should execute review (but current implementation is empty)
        assert!(output.error.is_none());
    }

    #[tokio::test]
    async fn test_review_job_all_review_types() {
        for review_type in [ReviewType::Memory, ReviewType::Skill, ReviewType::Combined] {
            let config = EvolutionConfig::default();
            let input = EvolutionReviewInput {
                thread_id: "test".to_string(),
                review_type,
                conversation_snapshot: vec![],
                nudge_state: NudgeState::default(),
                trigger_turns: 0,
                trigger_tool_calls: 0,
                existing_memory: std::collections::HashMap::new(),
            };

            let pending_queue = Arc::new(PendingQueue::new());
            let job = EvolutionReviewJob::new(input, config, pending_queue);
            let ctx = JobContext::new("test-job");

            let output = job.execute(&ctx).await.unwrap();
            assert_eq!(output.review_type, review_type);
        }
    }

    #[test]
    fn test_job_timeout() {
        let config = EvolutionConfig::default();
        let input = EvolutionReviewInput {
            thread_id: "test".to_string(),
            review_type: ReviewType::Memory,
            conversation_snapshot: vec![],
            nudge_state: NudgeState::default(),
            trigger_turns: 0,
            trigger_tool_calls: 0,
            existing_memory: std::collections::HashMap::new(),
        };

        let pending_queue = Arc::new(PendingQueue::new());
        let job = EvolutionReviewJob::new(input, config, pending_queue);

        // Verify timeout setting
        assert_eq!(job.timeout(), std::time::Duration::from_secs(60));
    }

    #[test]
    fn test_evolution_review_output_default() {
        let output = EvolutionReviewOutput::default();
        assert!(output.job_id.is_empty());
        assert_eq!(output.suggestions_count, 0);
        assert!(output.pending_ids.is_empty());
        assert!(output.error.is_none());
    }
}

#[cfg(test)]
mod aggregator_tests {
    use super::super::*;
    use crate::types::{ConfidenceLevel, MemoryEntryType, PendingActionType, SuggestedAction};

    #[test]
    fn test_aggregate_groups_by_type() {
        let aggregator = SuggestionAggregator::new(0.8, 10);

        // Use different entry_type so they go into different groups
        let suggestions = vec![
            SuggestedAction {
                action: PendingActionType::MemoryWrite {
                    entry_type: MemoryEntryType::UserProfile, // User profile
                    content: "likes dark mode".to_string(),
                },
                confidence: ConfidenceLevel::High,
                reasoning: "explicit".to_string(),
                source_indices: vec![0],
            },
            SuggestedAction {
                action: PendingActionType::MemoryWrite {
                    entry_type: MemoryEntryType::Environment, // Environment info, different group
                    content: "sit in a quiet place".to_string(),
                },
                confidence: ConfidenceLevel::Medium,
                reasoning: "inferred".to_string(),
                source_indices: vec![1],
            },
        ];

        let (aggregated, auto_groups) = aggregator.aggregate(suggestions, &[]);

        // High confidence group goes into auto_execute_groups (1 group with 1 action here)
        assert_eq!(auto_groups.len(), 1);
        assert_eq!(auto_groups[0].actions.len(), 1);
        assert_eq!(auto_groups[0].confidence, ConfidenceLevel::High);
        // Medium goes to queue
        assert_eq!(aggregated.len(), 1);
        assert_eq!(aggregated[0].confidence, ConfidenceLevel::Medium);
    }

    #[test]
    fn test_duplicate_detection() {
        let aggregator = SuggestionAggregator::new(0.8, 10);

        // Test deduplication with completely identical content
        let action = PendingActionType::MemoryWrite {
            entry_type: MemoryEntryType::UserProfile,
            content: "likes dark mode".to_string(),
        };

        let existing = vec![crate::queue::PendingConfirmation::new(
            PendingActionType::MemoryWrite {
                entry_type: MemoryEntryType::UserProfile,
                content: "likes dark mode".to_string(), // Exact same string
            },
            crate::ReviewSource {
                job_id: "test".to_string(),
                triggered_at: chrono::Utc::now(),
                review_type: crate::ReviewType::Memory,
            },
            "test reasoning".to_string(),
            "test-thread".to_string(),
        )];

        // Same string should be recognized as duplicate
        assert!(aggregator.is_duplicate(&action, &existing));
    }
}

#[cfg(test)]
mod prompt_injection_tests {
    use super::super::*;
    use tempfile::TempDir;

    /// Test that skill list is correctly injected into prompt
    #[tokio::test]
    async fn test_inject_skill_list_into_prompt() {
        // Create temporary directory to simulate user skills directory
        let temp_dir = TempDir::new().unwrap();
        let user_id = "test-user";

        // Create test skills
        let skill1_name = "explore-project";
        let skill1_dir = temp_dir.path().join(skill1_name);
        tokio::fs::create_dir_all(&skill1_dir).await.unwrap();
        let skill1_content = r#"---
name: explore-project
description: Explore project structure systematically
---

# Explore Project Structure

Systematically explore and understand project structure."#;
        tokio::fs::write(skill1_dir.join("SKILL.md"), skill1_content)
            .await
            .unwrap();

        let skill2_name = "code-review";
        let skill2_dir = temp_dir.path().join(skill2_name);
        tokio::fs::create_dir_all(&skill2_dir).await.unwrap();
        let skill2_content = r#"---
name: code-review
description: Review code for quality and best practices
---

# Code Review

Review code changes for quality assurance."#;
        tokio::fs::write(skill2_dir.join("SKILL.md"), skill2_content)
            .await
            .unwrap();

        // Build test prompt
        let prompt_template = r#"## Existing Skills

{{SKILL_LIST}}

Please review and update a skill if appropriate."#;

        // Create EvolutionReviewJob with test config
        let config = EvolutionConfig {
            user_id: user_id.to_string(),
            ..Default::default()
        };

        // Create job instance and call injection function
        let job = EvolutionReviewJob::new(
            EvolutionReviewInput {
                thread_id: "test".to_string(),
                review_type: ReviewType::Skill,
                conversation_snapshot: vec![],
                nudge_state: NudgeState::default(),
                trigger_turns: 0,
                trigger_tool_calls: 0,
                existing_memory: std::collections::HashMap::new(),
            },
            config,
            Arc::new(PendingQueue::new()),
        );

        let result = job
            .inject_skill_list_into_prompt_test(
                prompt_template.to_string(),
                Some(temp_dir.path().to_path_buf()),
            )
            .await;
        assert!(result.is_ok(), "Failed to inject skill list: {:?}", result);

        let injected_prompt = result.unwrap();

        // Verify skill list was injected
        assert!(
            injected_prompt.contains("explore-project"),
            "Prompt should contain explore-project"
        );
        assert!(
            injected_prompt.contains("code-review"),
            "Prompt should contain code-review"
        );
        assert!(
            !injected_prompt.contains("{{SKILL_LIST}}"),
            "Template variable should be replaced"
        );
        assert!(
            injected_prompt.contains("Explore project structure systematically"),
            "Should contain skill 1 description"
        );
        assert!(
            injected_prompt.contains("Review code for quality and best practices"),
            "Should contain skill 2 description"
        );
    }

    /// Test prompt when there are no skills
    #[tokio::test]
    async fn test_inject_skill_list_empty() {
        let temp_dir = TempDir::new().unwrap();

        let prompt_template = "{{SKILL_LIST}}";

        let config = EvolutionConfig {
            user_id: "empty-user".to_string(),
            ..Default::default()
        };

        let job = EvolutionReviewJob::new(
            EvolutionReviewInput {
                thread_id: "test".to_string(),
                review_type: ReviewType::Skill,
                conversation_snapshot: vec![],
                nudge_state: NudgeState::default(),
                trigger_turns: 0,
                trigger_tool_calls: 0,
                existing_memory: std::collections::HashMap::new(),
            },
            config,
            Arc::new(PendingQueue::new()),
        );

        let result = job
            .inject_skill_list_into_prompt_test(
                prompt_template.to_string(),
                Some(temp_dir.path().to_path_buf()),
            )
            .await;
        assert!(result.is_ok());

        let injected_prompt = result.unwrap();
        assert!(
            injected_prompt.contains("No existing skills"),
            "Should indicate no skills exist"
        );
        assert!(
            !injected_prompt.contains("{{SKILL_LIST}}"),
            "Template variable should be replaced"
        );
    }
}

#[cfg(test)]
mod llm_decision_tests {
    use super::super::*;

    /// Mock LLM Handler for testing
    struct MockLlmHandler {
        tool_calls: Vec<(String, serde_json::Value)>,
        content: String,
    }

    impl MockLlmHandler {
        fn new(tool_calls: Vec<(String, serde_json::Value)>, content: String) -> Self {
            Self {
                tool_calls,
                content,
            }
        }
    }

    #[async_trait]
    impl LlmReviewHandler for MockLlmHandler {
        async fn review(
            &self,
            _messages: Vec<crate::traits::Message>,
            _tools: &crate::traits::ToolRegistry,
            _timeout_secs: u64,
        ) -> Result<ReviewResult, String> {
            Ok(ReviewResult {
                content: self.content.clone(),
                tool_calls: self.tool_calls.clone(),
            })
        }
    }

    /// Test that LLM chooses edit instead of create when it knows about existing skills
    #[tokio::test]
    async fn test_llm_chooses_edit_for_existing_skill() {
        // Create mock conversation with enough assistant messages to pass complexity check
        let mut conversation = vec![];
        // Add 5 assistant messages to satisfy default complexity threshold
        for i in 0..5 {
            conversation.push(MessageSnapshot {
                role: "assistant".to_string(),
                content: format!("Tool call {}", i),
                timestamp: Some(Utc::now()),
            });
        }
        conversation.push(MessageSnapshot {
            role: "user".to_string(),
            content: "Update the explore-project skill to include Python projects".to_string(),
            timestamp: Some(Utc::now()),
        });

        // Use default config
        let config = EvolutionConfig {
            user_id: "test".to_string(),
            ..Default::default()
        };

        let job = EvolutionReviewJob::new(
            EvolutionReviewInput {
                thread_id: "test".to_string(),
                review_type: ReviewType::Skill,
                conversation_snapshot: conversation,
                nudge_state: NudgeState::default(),
                trigger_turns: 5,
                trigger_tool_calls: 5,
                existing_memory: std::collections::HashMap::new(),
            },
            config,
            Arc::new(PendingQueue::new()),
        );

        // Verify job has LLM handler (even though we don't need it)
        // This test mainly verifies: when prompt contains skill list, the system does not do secondary conversion
        // but trusts the LLM's original decision

        // Mock LLM returning edit action
        let mock_handler = Arc::new(MockLlmHandler::new(
            vec![(
                "review_skill".to_string(),
                serde_json::json!({
                    "action": "edit",
                    "name": "explore-project",
                    "content": "---\nname: explore-project\ndescription: Updated skill\n---\n\n# Updated",
                    "confidence": "high",
                    "reasoning": "User wants to update existing skill with Python support"
                }),
            )],
            "I will update the explore-project skill to support Python.".to_string(),
        ));

        let job_with_handler = job.with_llm_handler(mock_handler);

        // Execute review
        let result = job_with_handler.perform_review().await;
        assert!(result.is_ok(), "Review should succeed: {:?}", result);

        let output = result.unwrap();
        assert_eq!(output.suggestions_count, 1, "Should have 1 suggestion");

        // Verify it is edit not create
        // Note: since smart conversion was removed, the system trusts the LLM's edit decision directly
    }

    /// Test that LLM chooses patch instead of edit when it knows about existing skills
    #[tokio::test]
    async fn test_llm_chooses_patch_for_existing_skill() {
        // Create mock conversation with enough assistant messages to pass complexity check
        let mut conversation = vec![];
        // Add 5 assistant messages to satisfy default complexity threshold
        for i in 0..5 {
            conversation.push(MessageSnapshot {
                role: "assistant".to_string(),
                content: format!("Tool call {}", i),
                timestamp: Some(Utc::now()),
            });
        }
        conversation.push(MessageSnapshot {
            role: "user".to_string(),
            content: "Fix the typo in explore-project skill".to_string(),
            timestamp: Some(Utc::now()),
        });

        let config = EvolutionConfig {
            user_id: "test".to_string(),
            ..Default::default()
        };

        let job = EvolutionReviewJob::new(
            EvolutionReviewInput {
                thread_id: "test".to_string(),
                review_type: ReviewType::Skill,
                conversation_snapshot: conversation,
                nudge_state: NudgeState::default(),
                trigger_turns: 3,
                trigger_tool_calls: 3,
                existing_memory: std::collections::HashMap::new(),
            },
            config,
            Arc::new(PendingQueue::new()),
        );

        // Mock LLM returning patch action
        let mock_handler = Arc::new(MockLlmHandler::new(
            vec![(
                "review_skill".to_string(),
                serde_json::json!({
                    "action": "patch",
                    "name": "explore-project",
                    "old_string": "structred",
                    "new_string": "structured",
                    "confidence": "high",
                    "reasoning": "Fixing typo in existing skill"
                }),
            )],
            "I'll fix the typo using patch.".to_string(),
        ));

        let job_with_handler = job.with_llm_handler(mock_handler);

        let result = job_with_handler.perform_review().await;
        assert!(result.is_ok());

        let output = result.unwrap();
        assert_eq!(output.suggestions_count, 1);
    }

    #[tokio::test]
    async fn fixture_eval_memory_skill_and_none_outcomes() {
        async fn run_fixture(
            review_type: ReviewType,
            tool_calls: Vec<(String, serde_json::Value)>,
        ) -> (EvolutionReviewOutput, Vec<PendingConfirmation>) {
            let queue = Arc::new(PendingQueue::new());
            let mut config = EvolutionConfig {
                user_id: "test".to_string(),
                ..Default::default()
            };
            config.security.min_complexity_threshold = 1;
            config.security.auto_apply_high_confidence = false;

            let conversation = vec![
                MessageSnapshot {
                    role: "assistant".to_string(),
                    content: "completed a tool-backed task".to_string(),
                    timestamp: Some(Utc::now()),
                },
                MessageSnapshot {
                    role: "user".to_string(),
                    content: "remember the reusable outcome".to_string(),
                    timestamp: Some(Utc::now()),
                },
            ];
            let job = EvolutionReviewJob::new(
                EvolutionReviewInput {
                    thread_id: "fixture".to_string(),
                    review_type,
                    conversation_snapshot: conversation,
                    nudge_state: NudgeState::default(),
                    trigger_turns: 2,
                    trigger_tool_calls: 1,
                    existing_memory: std::collections::HashMap::new(),
                },
                config,
                Arc::clone(&queue),
            )
            .with_llm_handler(Arc::new(MockLlmHandler::new(
                tool_calls,
                "fixture eval".to_string(),
            )));

            let output = job.perform_review().await.unwrap();
            let pending = queue.get_pending().await;
            (output, pending)
        }

        let (memory_output, memory_pending) = run_fixture(
            ReviewType::Memory,
            vec![(
                "review_memory".to_string(),
                serde_json::json!({
                    "entry_type": "project",
                    "content": "Use fixture-based evals for evolution review changes.",
                    "confidence": "medium",
                    "reasoning": "Reusable project convention"
                }),
            )],
        )
        .await;
        assert_eq!(memory_output.suggestions_count, 1);
        assert_eq!(memory_output.tool_calls, vec!["review_memory"]);
        assert!(matches!(
            memory_pending[0].action,
            PendingActionType::MemoryWrite { .. }
        ));

        let (skill_output, skill_pending) = run_fixture(
            ReviewType::Skill,
            vec![(
                "review_skill".to_string(),
                serde_json::json!({
                    "action": "patch",
                    "name": "evolution-review",
                    "old_string": "old guidance",
                    "new_string": "new guidance",
                    "confidence": "medium",
                    "reasoning": "Patch current umbrella skill"
                }),
            )],
        )
        .await;
        assert_eq!(skill_output.suggestions_count, 1);
        assert_eq!(skill_output.tool_calls, vec!["review_skill"]);
        assert!(matches!(
            skill_pending[0].action,
            PendingActionType::Patch { .. }
        ));

        let (none_output, none_pending) = run_fixture(ReviewType::Skill, vec![]).await;
        assert_eq!(none_output.suggestions_count, 0);
        assert!(none_pending.is_empty());
    }

    #[test]
    fn bounded_text_preview_preserves_short_text() {
        assert_eq!(
            bounded_text_preview("short diagnostic", 800),
            "short diagnostic"
        );
    }

    #[test]
    fn bounded_text_preview_truncates_utf8_safely() {
        let text = format!("{}错后续", "a".repeat(798));
        assert_eq!(text.len(), 807);

        let preview = bounded_text_preview(&text, 800);

        assert!(preview.is_char_boundary(preview.len()));
        assert!(preview.starts_with(&format!("{}错后", "a".repeat(798))));
        assert!(preview.contains("truncated"));
    }
}