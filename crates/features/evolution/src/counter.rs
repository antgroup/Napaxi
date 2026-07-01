use crate::error::{EvolutionError, EvolutionResult};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, RwLock as StdRwLock};

/// Nudge counter persistent state
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NudgeState {
    /// Conversation turn count (incremented on each user input)
    #[serde(default)]
    pub turns_since_memory: usize,

    /// Tool call count (incremented on each non-memory/non-skill tool call)
    #[serde(default)]
    pub iters_since_skill: usize,

    /// Last Memory Review time (for cooldown)
    #[serde(with = "chrono::serde::ts_seconds_option")]
    #[serde(default)]
    pub last_memory_review: Option<DateTime<Utc>>,

    /// Last Skill Review time (for cooldown)
    #[serde(with = "chrono::serde::ts_seconds_option")]
    #[serde(default)]
    pub last_skill_review: Option<DateTime<Utc>>,

    /// Thread ID (for verification)
    pub thread_id: String,
}

/// Counter storage abstraction trait
#[async_trait]
pub trait CounterStorage: Send + Sync {
    /// Load counter state
    async fn load(&self) -> EvolutionResult<NudgeState>;

    /// Save counter state
    async fn save(&self, state: &NudgeState) -> EvolutionResult<()>;
}

/// In-memory storage implementation
///
/// For unit testing, no Thread dependency required
pub struct InMemoryStorage {
    state: StdRwLock<NudgeState>,
}

impl InMemoryStorage {
    pub fn new(thread_id: impl Into<String>) -> Self {
        Self {
            state: StdRwLock::new(NudgeState {
                thread_id: thread_id.into(),
                ..Default::default()
            }),
        }
    }

    /// Get current state (test helper)
    pub fn current(&self) -> NudgeState {
        self.state
            .read()
            .expect("InMemoryStorage lock poisoned")
            .clone()
    }
}

#[async_trait]
impl CounterStorage for InMemoryStorage {
    async fn load(&self) -> EvolutionResult<NudgeState> {
        Ok(self
            .state
            .read()
            .expect("InMemoryStorage lock poisoned")
            .clone())
    }

    async fn save(&self, state: &NudgeState) -> EvolutionResult<()> {
        *self.state.write().expect("InMemoryStorage lock poisoned") = state.clone();
        Ok(())
    }
}

/// Thread metadata access abstraction (minimal intrusion design)
///
/// Avoids direct dependency on Thread type, decoupled through trait
#[async_trait]
pub trait ThreadMetadataAccessor: Send + Sync {
    fn get(&self, key: &str) -> Option<serde_json::Value>;
    fn insert(&mut self, key: String, value: serde_json::Value);
}

/// In-memory implementation (simplified; production should connect to Thread's metadata field)
#[derive(Default)]
pub struct InMemoryMetadata {
    data: std::collections::HashMap<String, serde_json::Value>,
}

impl ThreadMetadataAccessor for InMemoryMetadata {
    fn get(&self, key: &str) -> Option<serde_json::Value> {
        self.data.get(key).cloned()
    }

    fn insert(&mut self, key: String, value: serde_json::Value) {
        self.data.insert(key, value);
    }
}

/// Thread::metadata-based storage implementation
///
/// Used in production, counter state persisted to Thread::metadata
pub struct ThreadMetadataStorage {
    thread_id: Arc<str>,
    // Uses generic storage here; in practice the application layer should provide a Thread metadata accessor
    metadata_accessor: Arc<tokio::sync::RwLock<dyn ThreadMetadataAccessor>>,
}

impl ThreadMetadataStorage {
    pub fn new(thread_id: impl Into<Arc<str>>) -> Self {
        Self {
            thread_id: thread_id.into(),
            metadata_accessor: Arc::new(tokio::sync::RwLock::new(InMemoryMetadata::default())),
        }
    }

    /// Use custom metadata accessor
    pub fn with_accessor(
        thread_id: impl Into<Arc<str>>,
        accessor: Arc<tokio::sync::RwLock<dyn ThreadMetadataAccessor>>,
    ) -> Self {
        Self {
            thread_id: thread_id.into(),
            metadata_accessor: accessor,
        }
    }
}

#[async_trait]
impl CounterStorage for ThreadMetadataStorage {
    async fn load(&self) -> EvolutionResult<NudgeState> {
        let accessor = self.metadata_accessor.read().await;

        let value = accessor
            .get("nudge_state")
            .ok_or_else(|| EvolutionError::Storage {
                message: "nudge_state key not found".to_string(),
            })?;

        // Clone value before dropping the lock to avoid holding the lock during deserialization
        drop(accessor);

        let mut state: NudgeState =
            serde_json::from_value(value).map_err(|e| EvolutionError::Storage {
                message: format!("Failed to deserialize nudge_state: {}", e),
            })?;

        state.thread_id = self.thread_id.to_string();
        Ok(state)
    }

    async fn save(&self, state: &NudgeState) -> EvolutionResult<()> {
        let value = serde_json::to_value(state)
            .map_err(|e| EvolutionError::Serialization(e.to_string()))?;

        let mut accessor = self.metadata_accessor.write().await;
        accessor.insert("nudge_state".to_string(), value);

        Ok(())
    }
}

/// Single user's counter state
#[derive(Debug, Default)]
struct UserCounters {
    turns: AtomicUsize,
    tool_calls: AtomicUsize,
}

/// Runtime atomic counter (isolated by thread_id)
///
/// Thread-safe, shared between Hook and Job via Arc
/// Each thread_id has independent counters for user isolation
#[derive(Debug)]
pub struct AtomicNudgeCounter {
    counters: StdRwLock<HashMap<String, UserCounters>>,
}

impl AtomicNudgeCounter {
    pub fn new() -> Self {
        Self {
            counters: StdRwLock::new(HashMap::new()),
        }
    }

    /// Restore from persistent state
    pub fn restore(&self, thread_id: &str, state: &NudgeState) {
        let mut counters = self.counters.write().expect("counter map lock poisoned");
        let user_counters = counters.entry(thread_id.to_string()).or_default();
        user_counters
            .turns
            .store(state.turns_since_memory, Ordering::SeqCst);
        user_counters
            .tool_calls
            .store(state.iters_since_skill, Ordering::SeqCst);
    }

    /// Conversation turn count
    pub fn increment_turns(&self, thread_id: &str) -> usize {
        let mut counters = self.counters.write().expect("counter map lock poisoned");
        let user_counters = counters.entry(thread_id.to_string()).or_default();
        user_counters.turns.fetch_add(1, Ordering::SeqCst) + 1
    }

    /// Tool call count
    pub fn increment_tool_calls(&self, thread_id: &str) -> usize {
        let mut counters = self.counters.write().expect("counter map lock poisoned");
        let user_counters = counters.entry(thread_id.to_string()).or_default();
        user_counters.tool_calls.fetch_add(1, Ordering::SeqCst) + 1
    }

    /// Reset conversation turn count (on memory tool call)
    pub fn reset_turns(&self, thread_id: &str) {
        // Read lock suffices: the map is not mutated, only the per-thread
        // atomic counter is reset through interior mutability.
        let counters = self.counters.read().expect("counter map lock poisoned");
        if let Some(user_counters) = counters.get(thread_id) {
            user_counters.turns.store(0, Ordering::SeqCst);
        }
    }

    /// Reset tool call count (on skill tool call)
    pub fn reset_tool_calls(&self, thread_id: &str) {
        // Read lock suffices: see `reset_turns`.
        let counters = self.counters.read().expect("counter map lock poisoned");
        if let Some(user_counters) = counters.get(thread_id) {
            user_counters.tool_calls.store(0, Ordering::SeqCst);
        }
    }

    /// Get current counts
    pub fn current(&self, thread_id: &str) -> (usize, usize) {
        let counters = self.counters.read().expect("counter map lock poisoned");
        if let Some(user_counters) = counters.get(thread_id) {
            (
                user_counters.turns.load(Ordering::SeqCst),
                user_counters.tool_calls.load(Ordering::SeqCst),
            )
        } else {
            (0, 0)
        }
    }

    /// Persist as NudgeState
    pub fn to_state(&self, thread_id: impl Into<String>) -> NudgeState {
        let thread_id_str = thread_id.into();
        let counters = self.counters.read().expect("counter map lock poisoned");
        if let Some(user_counters) = counters.get(&thread_id_str) {
            NudgeState {
                turns_since_memory: user_counters.turns.load(Ordering::SeqCst),
                iters_since_skill: user_counters.tool_calls.load(Ordering::SeqCst),
                last_memory_review: None,
                last_skill_review: None,
                thread_id: thread_id_str,
            }
        } else {
            NudgeState {
                turns_since_memory: 0,
                iters_since_skill: 0,
                last_memory_review: None,
                last_skill_review: None,
                thread_id: thread_id_str,
            }
        }
    }
}

impl Default for AtomicNudgeCounter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use tokio::sync::RwLock;

    /// Mock ThreadMetadataAccessor for testing
    #[derive(Default)]
    struct MockMetadataAccessor {
        data: HashMap<String, serde_json::Value>,
    }

    impl ThreadMetadataAccessor for MockMetadataAccessor {
        fn get(&self, key: &str) -> Option<serde_json::Value> {
            self.data.get(key).cloned()
        }

        fn insert(&mut self, key: String, value: serde_json::Value) {
            self.data.insert(key, value);
        }
    }

    #[tokio::test]
    async fn test_thread_metadata_storage() {
        let accessor = Arc::new(RwLock::new(MockMetadataAccessor::default()));
        let storage = ThreadMetadataStorage::with_accessor("test-thread", accessor);

        // Initial state should error (key not found)
        assert!(storage.load().await.is_err());

        // Save state
        let state = NudgeState {
            thread_id: "test-thread".to_string(),
            turns_since_memory: 5,
            iters_since_skill: 10,
            last_memory_review: Some(Utc::now()),
            last_skill_review: Some(Utc::now()),
        };
        storage.save(&state).await.unwrap();

        // Load and verify
        let loaded = storage.load().await.unwrap();
        assert_eq!(loaded.turns_since_memory, 5);
        assert_eq!(loaded.iters_since_skill, 10);
        // thread_id should be set correctly on load
        assert_eq!(loaded.thread_id, "test-thread");
    }

    #[tokio::test]
    async fn test_thread_metadata_storage_corrupted_data() {
        let accessor = Arc::new(RwLock::new(MockMetadataAccessor::default()));
        let storage = ThreadMetadataStorage::with_accessor("test-thread", accessor.clone());

        // Write corrupted data
        {
            let mut acc = accessor.write().await;
            acc.insert("nudge_state".to_string(), serde_json::json!("invalid"));
        }

        // Load should fail
        let result = storage.load().await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_in_memory_storage() {
        let storage = InMemoryStorage::new("test-thread");

        // Initially empty
        assert!(storage.load().await.is_ok());

        // Save state
        let state = NudgeState {
            thread_id: "test-thread".to_string(),
            turns_since_memory: 5,
            iters_since_skill: 10,
            ..Default::default()
        };
        storage.save(&state).await.unwrap();

        // Load and verify
        let loaded = storage.load().await.unwrap();
        assert_eq!(loaded.turns_since_memory, 5);
        assert_eq!(loaded.iters_since_skill, 10);
    }

    #[test]
    fn test_atomic_counter() {
        let counter = AtomicNudgeCounter::new();
        let thread_id = "test-thread";

        // Initially 0
        assert_eq!(counter.current(thread_id), (0, 0));

        // Increment turns
        assert_eq!(counter.increment_turns(thread_id), 1);
        assert_eq!(counter.increment_turns(thread_id), 2);
        assert_eq!(counter.current(thread_id).0, 2);

        // Increment tool calls
        assert_eq!(counter.increment_tool_calls(thread_id), 1);
        assert_eq!(counter.increment_tool_calls(thread_id), 2);
        assert_eq!(counter.increment_tool_calls(thread_id), 3);
        assert_eq!(counter.current(thread_id).1, 3);

        // Reset
        counter.reset_turns(thread_id);
        assert_eq!(counter.current(thread_id).0, 0);

        counter.reset_tool_calls(thread_id);
        assert_eq!(counter.current(thread_id).1, 0);
    }

    #[test]
    fn test_counter_restore() {
        let counter = AtomicNudgeCounter::new();
        let thread_id = "test-thread";

        let state = NudgeState {
            thread_id: thread_id.to_string(),
            turns_since_memory: 42,
            iters_since_skill: 100,
            ..Default::default()
        };

        counter.restore(thread_id, &state);
        assert_eq!(counter.current(thread_id), (42, 100));
    }
}