//! End-to-end agent-turn integration tests.
//!
//! Unlike the unit tests in `tests.rs` (which assert individual stages and
//! diagnostics) these drive a FULL multi-iteration tool loop offline: the
//! scripted LLM seam (`crate::llm::dispatch::with_scripted_turns`) feeds turn 1
//! a tool call, the controllable internal tool runs, its result is fed back,
//! and turn 2 returns final text. This exercises the real path
//! `run_turn`/`stream_turn` → `run_tool_loop[_streaming]` →
//! `execute_turn_tool_calls` → dispatch re-invocation → session persistence,
//! which the empty-turn `__test_noop__` seam alone cannot reach.

use std::sync::{Arc, Mutex};

use super::{TurnInput, run_turn, stream_turn};
use crate::llm::with_scripted_turns;
use crate::llm::{LlmToolCall, LlmTurn};
use crate::tool_loop::{InternalToolFuture, InternalToolHandler, InternalToolResult};
use crate::tool_registry::{ToolDescriptor, ToolEffect};
use crate::types::ChatEvent;

/// Minimal offline LLM config selecting the `__test_noop__` provider, so the
/// scripted-turn seam supplies responses instead of any network call. The
/// `custom_host` tool capability is declared host-supported and explicitly
/// enabled so a host-dispatched tool (`echo`) survives admission filtering in
/// the tool loop's `tool_descriptors`.
fn noop_config_json() -> String {
    serde_json::json!({
        "provider": "__test_noop__",
        "api_key": "test",
        "base_url": null,
        "model": "test-model",
        "system_prompt": "",
        "max_tokens": 128,
        "capability_profile": {
            "platform": "test",
            "supported_capabilities": ["napaxi.tool.custom_host"]
        },
        "capability_selection": {
            "enabled_capabilities": ["napaxi.tool.custom_host"]
        }
    })
    .to_string()
}

/// An internal tool handler exposing a single `echo` tool that records the
/// arguments it was invoked with into `recorded` and returns a fixed result.
fn echo_handler(recorded: Arc<Mutex<Vec<String>>>) -> InternalToolHandler {
    Arc::new(move |name: &str, args: serde_json::Value, _progress| {
        if name != "echo" {
            return None;
        }
        recorded.lock().unwrap().push(args.to_string());
        Some(Box::pin(async move {
            Ok(InternalToolResult {
                output: r#"{"echoed":true}"#.to_string(),
                events: Vec::new(),
            })
        }) as InternalToolFuture)
    })
}

fn echo_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "echo".to_string(),
        description: "Echo the input back".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": { "msg": { "type": "string" } },
            "required": ["msg"]
        }),
        effect: ToolEffect::Read,
    }
}

/// The two scripted turns: turn 1 requests the `echo` tool, turn 2 returns the
/// final assistant text after the tool result is fed back.
fn scripted_tool_then_text() -> Vec<LlmTurn> {
    vec![
        LlmTurn {
            content: String::new(),
            reasoning_content: None,
            tool_calls: vec![LlmToolCall {
                id: "call-1".to_string(),
                name: "echo".to_string(),
                arguments: r#"{"msg":"hi"}"#.to_string(),
            }],
            usage: None,
        },
        LlmTurn {
            content: "done: tool said echoed".to_string(),
            reasoning_content: None,
            tool_calls: Vec::new(),
            usage: None,
        },
    ]
}

/// Drives a full scripted tool loop through either the collected (`run_turn`)
/// or streaming (`stream_turn`) path and asserts the tool ran, its result fed
/// back into a second LLM turn, and the final assistant text was persisted.
async fn run_scripted_tool_turn(stream: bool) {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let recorded = Arc::new(Mutex::new(Vec::<String>::new()));
    let handler = echo_handler(Arc::clone(&recorded));

    let input = TurnInput {
        files_dir: files_dir.clone(),
        workspace_files_dir: files_dir.clone(),
        config_json: noop_config_json(),
        agent_id: "napaxi".to_string(),
        session_key_json: session_key_json.clone(),
        message: "use the echo tool".to_string(),
        display_message: None,
        attachments_json: "[]".to_string(),
        tools: None,
        max_iterations: 4,
        extra_tools: vec![echo_descriptor()],
        internal_tool_handler: Some(handler),
        is_group_context: false,
        agent_engine: None,
    };

    let events: Vec<ChatEvent> = with_scripted_turns(scripted_tool_then_text(), async {
        if stream {
            let mut collected: Vec<ChatEvent> = Vec::new();
            stream_turn(input, |event| collected.push(event), || false).await;
            collected
        } else {
            run_turn(input, || false).await
        }
    })
    .await;

    // (1) The tool was invoked exactly once, with the scripted arguments.
    let calls = recorded.lock().unwrap().clone();
    assert_eq!(
        calls,
        vec![r#"{"msg":"hi"}"#.to_string()],
        "echo tool should be called once with the scripted args"
    );

    // (2) The loop iterated: a tool result was produced and fed back. The run
    // emitted a tool-result event for the call.
    assert!(
        events.iter().any(
            |event| matches!(event, ChatEvent::ToolResult { call_id, .. } if call_id == "call-1")
        ),
        "expected a ToolResult event for call-1, got: {events:?}"
    );

    // (3) The user message and the final assistant text were persisted.
    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let history = crate::session::get_history(&files_dir, &key.thread_id);
    assert!(
        history.contains("use the echo tool"),
        "user message should be persisted: {history}"
    );
    assert!(
        history.contains("done: tool said echoed"),
        "final assistant text (turn 2) should be persisted: {history}"
    );
}

#[tokio::test]
async fn collected_turn_runs_full_tool_loop_offline() {
    run_scripted_tool_turn(false).await;
}

#[tokio::test]
async fn streaming_turn_runs_full_tool_loop_offline() {
    run_scripted_tool_turn(true).await;
}

/// Sanity check that the scripted seam is strictly opt-in: with no queue in
/// scope, the `__test_noop__` provider still returns an empty turn (today's
/// behavior), so a turn with no scripted tool call simply finalizes with no
/// model output and persists only the user message.
#[tokio::test]
async fn unscripted_noop_turn_still_finalizes_empty() {
    let tmp = tempfile::tempdir().unwrap();
    let files_dir = tmp.path().to_string_lossy().to_string();
    let session_key_json = crate::session::create_session(&files_dir, "napaxi", "app", "user", None);

    let input = TurnInput {
        files_dir: files_dir.clone(),
        workspace_files_dir: files_dir.clone(),
        config_json: noop_config_json(),
        agent_id: "napaxi".to_string(),
        session_key_json: session_key_json.clone(),
        message: "hello".to_string(),
        display_message: None,
        attachments_json: "[]".to_string(),
        tools: None,
        max_iterations: 0,
        extra_tools: Vec::new(),
        internal_tool_handler: None,
        is_group_context: false,
        agent_engine: None,
    };

    let _events = run_turn(input, || false).await;

    let key: crate::session::SessionKey = serde_json::from_str(&session_key_json).unwrap();
    let history = crate::session::get_history(&files_dir, &key.thread_id);
    assert!(
        history.contains("hello"),
        "user message should persist even with an empty model response: {history}"
    );
}
