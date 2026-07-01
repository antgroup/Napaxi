//! Suggestion aggregator: dedup, group, and confidence-promote review
//! suggestions before they become pending actions. Split out of
//! `job/mod.rs`.

use crate::types::{AggregatedSuggestion, ConfidenceLevel, SuggestedAction};

/// Suggestion aggregator
///
/// Responsible for:
/// 1. Deduplication against existing pending (content similarity)
/// 2. Clustering by topic
/// 3. Confidence promotion (multiple indirect evidence -> high confidence)
pub struct SuggestionAggregator {
    similarity_threshold: f64,
    max_suggestions: usize,
}

impl SuggestionAggregator {
    pub fn new(similarity_threshold: f64, max_suggestions: usize) -> Self {
        Self {
            similarity_threshold: similarity_threshold.clamp(0.0, 1.0),
            max_suggestions,
        }
    }

    /// Aggregate new suggestions with existing pending
    ///
    /// Returns: aggregated suggestions to enqueue (low/medium confidence) and high-confidence groups that can be executed directly
    pub fn aggregate(
        &self,
        new_suggestions: Vec<SuggestedAction>,
        existing_pending: &[crate::queue::PendingConfirmation],
    ) -> (Vec<AggregatedSuggestion>, Vec<AggregatedSuggestion>) {
        // 1. Dedup: filter out suggestions similar to existing pending
        let mut dedup_count = 0;
        let filtered: Vec<SuggestedAction> = new_suggestions
            .into_iter()
            .filter(|s| {
                let is_dup = self.is_duplicate(&s.action, existing_pending);
                if is_dup {
                    dedup_count += 1;
                    tracing::debug!(
                        action_type = ?std::mem::discriminant(&s.action),
                        "[Evolution] Deduplicated similar suggestion"
                    );
                }
                !is_dup
            })
            .collect();

        if dedup_count > 0 {
            tracing::info!(
                dedup_count,
                kept_count = filtered.len(),
                "[Evolution] Deduplication filtered out suggestions"
            );
        }

        // 2. Cluster by entry_type
        let mut groups: std::collections::HashMap<String, Vec<SuggestedAction>> =
            std::collections::HashMap::new();

        for suggestion in filtered {
            let key = self.get_group_key(&suggestion.action);
            groups.entry(key).or_default().push(suggestion);
        }

        tracing::debug!(
            group_count = groups.len(),
            group_keys = ?groups.keys().collect::<Vec<_>>(),
            "[Evolution] Grouped suggestions by type"
        );

        // 3. Generate aggregated suggestions
        let mut aggregated = Vec::new();
        let mut auto_execute_groups = Vec::new();

        for (key, group) in groups {
            tracing::debug!(
                group_key = key,
                group_size = group.len(),
                "[Evolution] Processing group"
            );
            if group.is_empty() {
                continue;
            }

            // Compute aggregated confidence (take the highest)
            let max_confidence = group
                .iter()
                .map(|s| s.confidence)
                .max_by_key(|c| match c {
                    ConfidenceLevel::High => 2,
                    ConfidenceLevel::Medium => 1,
                    ConfidenceLevel::Low => 0,
                })
                .unwrap_or(ConfidenceLevel::Medium);

            // Merge all actions
            let actions: Vec<_> = group.iter().map(|s| s.action.clone()).collect();

            // Merge reasoning (use the first as representative)
            let reasoning = group
                .first()
                .map(|s| s.reasoning.clone())
                .unwrap_or_default();

            let agg = AggregatedSuggestion {
                actions: actions.clone(),
                confidence: max_confidence,
                reasoning,
                sources: Vec::new(), // Simplified implementation
            };

            // Route: high confidence groups go to auto_execute, others are enqueued
            match max_confidence {
                ConfidenceLevel::High => {
                    // High confidence suggestions are aggregated and executed as a group
                    auto_execute_groups.push(agg);
                }
                _ => {
                    aggregated.push(agg);
                }
            }
        }

        // Limit count
        aggregated.truncate(self.max_suggestions);

        (aggregated, auto_execute_groups)
    }

    /// Check whether duplicated with existing pending
    pub(super) fn is_duplicate(
        &self,
        action: &crate::types::PendingActionType,
        existing: &[crate::queue::PendingConfirmation],
    ) -> bool {
        let action_content = self.extract_content(action);

        for pending in existing {
            let pending_content = self.extract_content(&pending.action);

            // Simplified similarity: same entry_type + similar content
            if self.similarity(&action_content, &pending_content) > self.similarity_threshold {
                return true;
            }
        }

        false
    }

    /// Extract content for comparison
    fn extract_content(&self, action: &crate::types::PendingActionType) -> String {
        use crate::types::PendingActionType;

        match action {
            PendingActionType::MemoryWrite { content, .. } => content.clone(),
            PendingActionType::Create {
                skill_name,
                content,
                ..
            } => {
                format!("{} {}", skill_name, content)
            }
            PendingActionType::Edit {
                skill_name,
                new_content,
            } => {
                format!("{} {}", skill_name, new_content)
            }
            _ => String::new(),
        }
    }

    /// Get group key
    fn get_group_key(&self, action: &crate::types::PendingActionType) -> String {
        use crate::types::PendingActionType;

        match action {
            PendingActionType::MemoryWrite { entry_type, .. } => {
                format!("memory:{:?}", entry_type)
            }
            PendingActionType::Create { skill_name, .. }
            | PendingActionType::Edit { skill_name, .. } => {
                format!("skill:{}", skill_name)
            }
            _ => "other".to_string(),
        }
    }

    /// Simple similarity calculation (based on common substring ratio)
    fn similarity(&self, a: &str, b: &str) -> f64 {
        if a.is_empty() || b.is_empty() {
            return 0.0;
        }

        let a_lower = a.to_lowercase();
        let b_lower = b.to_lowercase();

        // Simple implementation: containment relationship
        if a_lower.contains(&b_lower) || b_lower.contains(&a_lower) {
            let max_len = a.len().max(b.len());
            let min_len = a.len().min(b.len());
            return min_len as f64 / max_len as f64;
        }

        // Compute common word ratio
        let a_words: std::collections::HashSet<_> = a_lower.split_whitespace().collect();
        let b_words: std::collections::HashSet<_> = b_lower.split_whitespace().collect();

        let common = a_words.intersection(&b_words).count();
        let total = a_words.union(&b_words).count();

        if total == 0 {
            0.0
        } else {
            common as f64 / total as f64
        }
    }
}