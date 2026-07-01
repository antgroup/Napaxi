//! Agent turn lifecycle orchestration for the mobile SDK runtime.
//!
//! This module owns the business flow for one chat turn: prompt preparation,
//! message and attachment persistence, tool-loop execution, trace persistence,
//! journal updates, and post-turn evolution scheduling. Runtime handle and
//! bridge-facing JSON concerns stay in `runtime`.

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::tool_loop::InternalToolHandler;
use crate::tool_registry::{ToolDescriptor, ToolExecutionContext, ToolRegistry};
use crate::types::ChatEvent;

mod attachments;
mod diagnostics;
mod finalize;
mod history;
mod orchestration;
mod prepare;
mod prompt;

use diagnostics::TurnDiagnosticsRecorder;
pub(crate) use finalize::{TurnOutcomeSummary, finish_cancelled_turn, finish_successful_turn};
use history::turn_history_recorder_for;
#[cfg(test)]
pub(crate) use orchestration::run_turn_with_hooks;
pub use orchestration::{run_turn, stream_turn};
#[cfg(test)]
pub(crate) use prepare::prepare_turn;
pub(crate) use prepare::{
    PreparedTurn, prepare_turn_with_hooks, reprepare_turn_after_context_overflow_with_hooks,
};
use prompt::PromptPlanSummary;
#[cfg(test)]
use prompt::{PromptPlan, compile_prompt_sections, prepare_prompt_sections};

#[cfg(test)]
pub(crate) use attachments::raw_history_with_attachments;
pub(crate) use attachments::{
    attachment_content_parts_with_mode, attachment_metadata_json, parse_scene_prompt_attachments,
    persist_attachment_files,
};
pub(crate) use history::{TurnHistoryRecorder, persist_turn_history_segments};
#[cfg(test)]
pub use prompt::ChatRuntimeInput;
#[allow(unused_imports)]
pub use prompt::prepare_chat_config;

#[cfg(test)]
use diagnostics::{
    TURN_DIAGNOSTICS_LIMIT, TurnDiagnosticRecord, TurnDiagnosticStageStatus, TurnDiagnosticStatus,
    append_turn_diagnostic_record, list_turn_diagnostics, now_rfc3339,
};

#[cfg(test)]
use prompt::{
    PromptPriority, PromptSection, PromptSectionSource, PromptSectionVisibility,
    test_sha256_hex as sha256_hex,
};

#[cfg(test)]
use crate::types::PlatformLlmConfig;
#[cfg(test)]
use crate::types::{AttachmentKind, IncomingAttachment};

pub struct TurnInput {
    pub files_dir: String,
    pub workspace_files_dir: String,
    pub config_json: String,
    pub agent_id: String,
    pub session_key_json: String,
    pub message: String,
    pub display_message: Option<String>,
    pub attachments_json: String,
    pub tools: Option<Arc<ToolRegistry>>,
    pub max_iterations: i32,
    pub extra_tools: Vec<ToolDescriptor>,
    pub internal_tool_handler: Option<InternalToolHandler>,
    pub is_group_context: bool,
    pub agent_engine: Option<crate::agent_engine::AgentEngineSelection>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TurnMode {
    Collected,
    Streaming,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum TurnStage {
    ParseInput,
    PreparePrompt,
    PersistUserMessage,
    BuildHistory,
    ExecuteToolLoop,
    PersistAssistantTrace,
    AppendJournal,
    QueueEvolution,
    EmitFinalEvents,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TurnLifecycleContext {
    pub(crate) mode: TurnMode,
    pub(crate) agent_id: String,
    pub(crate) thread_id: Option<String>,
    pub(crate) is_group_context: bool,
}

impl TurnLifecycleContext {
    fn new(mode: TurnMode, agent_id: &str, is_group_context: bool) -> Self {
        Self {
            mode,
            agent_id: agent_id.to_string(),
            thread_id: None,
            is_group_context,
        }
    }
}

pub(crate) trait TurnLifecycleHooks {
    fn stage_started(&mut self, _context: &TurnLifecycleContext, _stage: TurnStage) {}

    fn stage_completed(&mut self, _context: &TurnLifecycleContext, _stage: TurnStage) {}

    fn stage_warning(
        &mut self,
        _context: &TurnLifecycleContext,
        _stage: TurnStage,
        _message: &str,
    ) {
    }

    fn stage_failed(&mut self, _context: &TurnLifecycleContext, _stage: TurnStage, _message: &str) {
    }

    fn prompt_prepared(&mut self, _context: &TurnLifecycleContext, _summary: &PromptPlanSummary) {}

    /// Return true when the event has already been delivered to the caller.
    fn context_event(&mut self, _context: &TurnLifecycleContext, _event: &ChatEvent) -> bool {
        false
    }

    fn turn_completed(&mut self, _context: &TurnLifecycleContext, _summary: &TurnOutcomeSummary) {}
}

fn tool_execution_context(
    files_dir: &str,
    workspace_files_dir: &str,
    agent_id: &str,
    session_key_json: &str,
) -> ToolExecutionContext {
    ToolExecutionContext {
        files_dir: files_dir.to_string(),
        workspace_files_dir: workspace_files_dir.to_string(),
        agent_id: agent_id.to_string(),
        session_key_json: Some(session_key_json.to_string()),
    }
}

fn chat_error(message: impl Into<String>) -> ChatEvent {
    ChatEvent::Error {
        message: message.into(),
    }
}

pub(crate) fn session_thread_id(session_key_json: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(session_key_json)
        .ok()
        .and_then(|key| {
            key.get("thread_id")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
}

#[cfg(test)]
mod integration_tests;
#[cfg(test)]
mod tests;
