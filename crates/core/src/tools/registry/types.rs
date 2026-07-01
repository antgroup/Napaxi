//! Public DTOs for the host tool boundary.

use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use super::pending::PendingToolRequests;

/// Per-turn context for host-side tool execution.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ToolExecutionContext {
    pub files_dir: String,
    pub workspace_files_dir: String,
    pub agent_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_key_json: Option<String>,
}

/// Callback type for dispatching async tool requests to the host app.
pub type ToolRequestDispatcher =
    Arc<dyn Fn(u64, &str, &str, Option<&ToolExecutionContext>) + Send + Sync>;

#[derive(Clone)]
pub(crate) struct ToolRequestBridge {
    pub(super) dispatcher: ToolRequestDispatcher,
    pub(super) pending_requests: Arc<PendingToolRequests>,
}

impl ToolRequestBridge {
    pub(crate) fn process_scoped(dispatcher: ToolRequestDispatcher) -> Self {
        Self {
            dispatcher,
            pending_requests: Arc::clone(&super::pending::PROCESS_PENDING_REQUESTS),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolDescriptor {
    pub name: String,
    pub description: String,
    #[serde(default = "default_parameters")]
    pub parameters: serde_json::Value,
    #[serde(default)]
    pub effect: ToolEffect,
}

fn default_parameters() -> serde_json::Value {
    serde_json::json!({"type": "object", "properties": {}})
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum ToolEffect {
    Read,
    Write,
    Execute,
    Deliver,
    External,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Copy)]
pub(super) struct ToolRateLimit {
    pub(super) max_calls: usize,
    pub(super) window: Duration,
}
