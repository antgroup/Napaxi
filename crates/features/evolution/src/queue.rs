use crate::error::{EvolutionError, EvolutionResult};
use crate::types::{PendingActionType, ReviewSource, ScanSummary};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

const DEFAULT_PENDING_CONFIRMATION_TTL_DAYS: i64 = 7;

/// User confirmation status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ConfirmationStatus {
    /// Awaiting user confirmation
    #[default]
    Pending,
    /// User confirmed
    Confirmed,
    /// User rejected
    Rejected,
    /// Expired
    Expired,
    /// Auto-approved (no confirmation needed)
    AutoApproved,
    /// Executed
    Executed,
}

/// Pending action awaiting user confirmation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingConfirmation {
    /// Unique identifier
    pub id: Uuid,
    /// Creation time
    pub created_at: DateTime<Utc>,
    /// Expiration time (default 7 days)
    pub expires_at: DateTime<Utc>,
    /// Action type (primary action of the aggregated group)
    pub action: PendingActionType,
    /// All aggregated actions (if aggregated)
    #[serde(default)]
    pub aggregated_actions: Vec<PendingActionType>,
    /// Review source
    pub source: ReviewSource,
    /// Security scan result (if any)
    pub scan_result: Option<ScanSummary>,
    /// Review reasoning
    pub reasoning: String,
    /// Associated Thread ID
    #[serde(default)]
    pub thread_id: String,
    /// Current status (not serialized to storage)
    #[serde(skip)]
    pub status: ConfirmationStatus,
}

impl PendingConfirmation {
    pub fn new(
        action: PendingActionType,
        source: ReviewSource,
        reasoning: String,
        thread_id: String,
    ) -> Self {
        let now = Utc::now();
        Self {
            id: Uuid::new_v4(),
            created_at: now,
            expires_at: now + chrono::Duration::days(DEFAULT_PENDING_CONFIRMATION_TTL_DAYS),
            action,
            aggregated_actions: Vec::new(),
            source,
            scan_result: None,
            reasoning,
            thread_id,
            status: ConfirmationStatus::Pending,
        }
    }

    pub fn with_scan_result(mut self, scan_result: ScanSummary) -> Self {
        self.scan_result = Some(scan_result);
        self
    }

    pub fn is_expired(&self) -> bool {
        Utc::now() > self.expires_at
    }
}

/// Pending confirmation queue
///
/// Thread-safe, can be shared between Hook and Job
#[derive(Debug)]
pub struct PendingQueue {
    inner: RwLock<HashMap<Uuid, PendingConfirmation>>,
}

impl PendingQueue {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(HashMap::new()),
        }
    }

    const MAX_QUEUE_SIZE: usize = 200;
    const CLEANUP_THRESHOLD: usize = 100;

    /// Add new confirmation item
    pub async fn push(&self, confirmation: PendingConfirmation) -> Uuid {
        let id = confirmation.id;
        let mut queue = self.inner.write().await;

        if queue.len() >= Self::CLEANUP_THRESHOLD {
            queue.retain(|_, c| !(c.status == ConfirmationStatus::Pending && c.is_expired()));
        }

        if queue.len() >= Self::MAX_QUEUE_SIZE {
            let mut expired_or_done: Vec<Uuid> = queue
                .iter()
                .filter(|(_, c)| c.status != ConfirmationStatus::Pending || c.is_expired())
                .map(|(id, _)| *id)
                .collect();
            expired_or_done.sort_by_key(|id| queue.get(id).map(|c| c.created_at));
            for old_id in expired_or_done
                .iter()
                .take(queue.len() - Self::MAX_QUEUE_SIZE + 1)
            {
                queue.remove(old_id);
            }
        }

        queue.insert(id, confirmation);
        id
    }

    /// Get all pending items (filtering out expired)
    pub async fn get_pending(&self) -> Vec<PendingConfirmation> {
        let queue = self.inner.read().await;
        queue
            .values()
            .filter(|c| c.status == ConfirmationStatus::Pending && !c.is_expired())
            .cloned()
            .collect()
    }

    /// Get specific item
    pub async fn get(&self, id: Uuid) -> EvolutionResult<PendingConfirmation> {
        let queue = self.inner.read().await;
        queue
            .get(&id)
            .cloned()
            .ok_or(EvolutionError::ConfirmationNotFound(id))
    }

    /// Confirm action (mark as Confirmed, but do not execute)
    pub async fn confirm(&self, id: Uuid) -> EvolutionResult<PendingConfirmation> {
        let mut queue = self.inner.write().await;

        let pending = queue
            .get_mut(&id)
            .ok_or(EvolutionError::ConfirmationNotFound(id))?;

        if pending.status != ConfirmationStatus::Pending {
            return Err(EvolutionError::InvalidStatus(format!(
                "Confirmation already {:?}",
                pending.status
            )));
        }

        if pending.is_expired() {
            pending.status = ConfirmationStatus::Expired;
            return Err(EvolutionError::ConfirmationExpired(id));
        }

        pending.status = ConfirmationStatus::Confirmed;
        Ok(pending.clone())
    }

    /// Mark as executed
    pub async fn mark_executed(&self, id: Uuid) -> EvolutionResult<()> {
        let mut queue = self.inner.write().await;

        let pending = queue
            .get_mut(&id)
            .ok_or(EvolutionError::ConfirmationNotFound(id))?;

        if pending.status != ConfirmationStatus::Confirmed {
            return Err(EvolutionError::InvalidStatus(
                "Confirmation must be confirmed before execution".to_string(),
            ));
        }

        pending.status = ConfirmationStatus::Executed;
        Ok(())
    }

    /// Reject action
    pub async fn reject(&self, id: Uuid) -> EvolutionResult<()> {
        let mut queue = self.inner.write().await;

        let pending = queue
            .get_mut(&id)
            .ok_or(EvolutionError::ConfirmationNotFound(id))?;

        if pending.status != ConfirmationStatus::Pending {
            return Err(EvolutionError::InvalidStatus(format!(
                "Confirmation already {:?}",
                pending.status
            )));
        }

        pending.status = ConfirmationStatus::Rejected;
        Ok(())
    }

    /// Cleanup expired items
    pub async fn cleanup_expired(&self) -> usize {
        let mut queue = self.inner.write().await;
        let before = queue.len();

        queue.retain(|_, c| !(c.status == ConfirmationStatus::Pending && c.is_expired()));

        before - queue.len()
    }

    /// Get queue size
    pub async fn len(&self) -> usize {
        self.inner.read().await.len()
    }

    /// Whether empty
    pub async fn is_empty(&self) -> bool {
        self.inner.read().await.is_empty()
    }
}

impl Default for PendingQueue {
    fn default() -> Self {
        Self::new()
    }
}

/// User-isolated pending queue manager.
/// Manages separate PendingQueue instances for each user.
#[derive(Debug)]
pub struct UserPendingQueue {
    inner: RwLock<HashMap<String, Arc<PendingQueue>>>,
}

impl UserPendingQueue {
    pub fn new() -> Self {
        Self {
            inner: RwLock::new(HashMap::new()),
        }
    }

    /// Get or create a PendingQueue for the specified user.
    pub async fn get_or_create_queue(&self, user_id: &str) -> Arc<PendingQueue> {
        let queues: tokio::sync::RwLockReadGuard<'_, HashMap<String, Arc<PendingQueue>>> =
            self.inner.read().await;
        if let Some(queue) = queues.get(user_id) {
            return Arc::clone(queue);
        }
        drop(queues);

        let mut queues: tokio::sync::RwLockWriteGuard<'_, HashMap<String, Arc<PendingQueue>>> =
            self.inner.write().await;
        // Double-check after acquiring write lock
        if let Some(queue) = queues.get(user_id) {
            return Arc::clone(queue);
        }

        let queue: Arc<PendingQueue> = Arc::new(PendingQueue::new());
        queues.insert(user_id.to_string(), Arc::clone(&queue));
        queue
    }

    /// Get all pending confirmations for a specific user.
    pub async fn get_pending(&self, user_id: &str) -> Vec<PendingConfirmation> {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.get_pending().await
    }

    /// Get a specific confirmation for a user.
    pub async fn get(&self, user_id: &str, id: Uuid) -> EvolutionResult<PendingConfirmation> {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.get(id).await
    }

    /// Push a new confirmation for a specific user.
    pub async fn push(&self, user_id: &str, confirmation: PendingConfirmation) -> Uuid {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.push(confirmation).await
    }

    /// Confirm an operation for a specific user.
    pub async fn confirm(&self, user_id: &str, id: Uuid) -> EvolutionResult<PendingConfirmation> {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.confirm(id).await
    }

    /// Mark as executed for a specific user.
    pub async fn mark_executed(&self, user_id: &str, id: Uuid) -> EvolutionResult<()> {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.mark_executed(id).await
    }

    /// Reject an operation for a specific user.
    pub async fn reject(&self, user_id: &str, id: Uuid) -> EvolutionResult<()> {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.reject(id).await
    }

    /// Cleanup expired items for a specific user.
    pub async fn cleanup_expired(&self, user_id: &str) -> usize {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.cleanup_expired().await
    }

    /// Get queue size for a specific user.
    pub async fn len(&self, user_id: &str) -> usize {
        let queue: Arc<PendingQueue> = self.get_or_create_queue(user_id).await;
        queue.len().await
    }

    /// Check if user queue is empty.
    pub async fn is_empty(&self, user_id: &str) -> bool {
        self.len(user_id).await == 0
    }
}

impl Default for UserPendingQueue {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ReviewType;

    #[tokio::test]
    async fn test_pending_queue_lifecycle() {
        let queue = PendingQueue::new();

        let action = PendingActionType::Create {
            skill_name: "test-skill".to_string(),
            content: "test content".to_string(),
            category: None,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "test reasoning".to_string(),
            "thread-1".to_string(),
        );

        // Add
        let id = queue.push(confirmation).await;
        assert_eq!(queue.len().await, 1);

        // Get pending list
        let pending = queue.get_pending().await;
        assert_eq!(pending.len(), 1);

        // Confirm
        let confirmed = queue.confirm(id).await.unwrap();
        assert_eq!(confirmed.id, id);

        // Mark executed
        queue.mark_executed(id).await.unwrap();

        // Verify status
        let item = queue.get(id).await.unwrap();
        assert_eq!(item.status, ConfirmationStatus::Executed);

        // Get pending list (should be empty)
        let pending = queue.get_pending().await;
        assert!(pending.is_empty());
    }

    #[tokio::test]
    async fn test_reject_operation() {
        let queue = PendingQueue::new();

        let action = PendingActionType::Delete {
            skill_name: "test-skill".to_string(),
            absorbed_into: None,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "delete reasoning".to_string(),
            "thread-1".to_string(),
        );

        let id = queue.push(confirmation).await;

        // Reject
        queue.reject(id).await.unwrap();

        // Verify status
        let item = queue.get(id).await.unwrap();
        assert_eq!(item.status, ConfirmationStatus::Rejected);
    }

    #[tokio::test]
    async fn test_get_nonexistent_confirmation() {
        let queue = PendingQueue::new();
        let fake_id = Uuid::new_v4();

        let result = queue.get(fake_id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_confirm_already_confirmed() {
        let queue = PendingQueue::new();

        let action = PendingActionType::Create {
            skill_name: "test".to_string(),
            content: "test".to_string(),
            category: None,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );

        let id = queue.push(confirmation).await;

        // First confirmation
        queue.confirm(id).await.unwrap();

        // Second confirmation should fail
        let result = queue.confirm(id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_reject_already_rejected() {
        let queue = PendingQueue::new();

        let action = PendingActionType::Delete {
            skill_name: "test".to_string(),
            absorbed_into: None,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );

        let id = queue.push(confirmation).await;

        // First rejection
        queue.reject(id).await.unwrap();

        // Second rejection should fail
        let result = queue.reject(id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_mark_executed_without_confirm() {
        let queue = PendingQueue::new();

        let action = PendingActionType::Create {
            skill_name: "test".to_string(),
            content: "test".to_string(),
            category: None,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );

        let id = queue.push(confirmation).await;

        // Mark executed directly without confirming first, should fail
        let result = queue.mark_executed(id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_expired_confirmation() {
        let queue = PendingQueue::new();

        // Create an expired confirmation (manually constructed)
        let action = PendingActionType::Create {
            skill_name: "test".to_string(),
            content: "test".to_string(),
            category: None,
        };

        let mut confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );

        // Manually set as expired
        confirmation.expires_at = Utc::now() - chrono::Duration::minutes(1);
        let id = queue.push(confirmation).await;

        // Attempting to confirm expired item should fail
        let result = queue.confirm(id).await;
        assert!(result.is_err());

        // Should not appear in pending list
        let pending = queue.get_pending().await;
        assert!(pending.is_empty());
    }

    #[tokio::test]
    async fn test_cleanup_expired() {
        let queue = PendingQueue::new();

        // Add normal item
        let action1 = PendingActionType::Create {
            skill_name: "test1".to_string(),
            content: "test".to_string(),
            category: None,
        };
        let confirmation1 = PendingConfirmation::new(
            action1,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );
        queue.push(confirmation1).await;

        // Add expired item (manually constructed)
        let action2 = PendingActionType::Create {
            skill_name: "test2".to_string(),
            content: "test".to_string(),
            category: None,
        };
        let mut confirmation2 = PendingConfirmation::new(
            action2,
            ReviewSource {
                job_id: "test".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "reasoning".to_string(),
            "thread-1".to_string(),
        );
        confirmation2.expires_at = Utc::now() - chrono::Duration::minutes(1);
        queue.push(confirmation2).await;

        // Should have 2 items before cleanup
        assert_eq!(queue.len().await, 2);

        // Cleanup expired items
        let cleaned = queue.cleanup_expired().await;
        assert_eq!(cleaned, 1);

        // Should have 1 item after cleanup
        assert_eq!(queue.len().await, 1);
    }
}