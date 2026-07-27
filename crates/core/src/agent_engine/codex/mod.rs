//! Core-owned Codex app-server agent engine.
//!
//! The public engine id is `napaxi.agent_engine.codex`; Android runs it inside
//! the Napaxi Linux sandbox PTY. Other platforms keep the same API surface and
//! return an explicit unsupported error.

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
mod events;
mod process;
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
mod protocol;
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
mod state;

#[cfg(test)]
pub(crate) use events::map_app_server_message;
pub(crate) use process::answer_human_request;
pub(crate) use process::configure_codex_agent_engine_json;
pub(crate) use process::run_codex_turn;
pub(crate) use state::register_android_native_library_dir;

pub const CODEX_ENGINE_ID: &str = "codex";
pub const CODEX_ENGINE_CAPABILITY_ID: &str = "napaxi.agent_engine.codex";

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::types::ChatEvent;

    #[test]
    fn maps_assistant_delta_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "assistant_delta", "delta": "hello"}
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ResponseDelta { content }) if content == "hello")
        );
    }

    #[test]
    fn maps_reasoning_delta_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "reasoning_delta", "delta": "thinking"}
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ReasoningDelta { content }) if content == "thinking")
        );
    }

    #[test]
    fn maps_command_output_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {
                "type": "command_output_delta",
                "call_id": "c1",
                "stream": "stdout",
                "delta": "out"
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::ToolOutputChunk { call_id, content, stream }) if call_id == "c1" && content == "out" && stream == "stdout")
        );
    }

    #[test]
    fn maps_turn_completed_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "turn_completed"}
        }));
        assert!(outcome.completed);
        assert!(!outcome.failed);
    }

    #[test]
    fn maps_turn_error_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {"type": "turn_error", "message": "boom"}
        }));
        assert!(outcome.completed);
        assert!(outcome.failed);
        assert!(matches!(outcome.event, Some(ChatEvent::Error { message }) if message == "boom"));
    }

    #[test]
    fn maps_user_input_request_fixture() {
        let outcome = map_app_server_message(&json!({
            "method": "thread/event",
            "params": {
                "type": "user_input_request",
                "request_id": "h1",
                "question": "Continue?",
                "options": ["yes", "no"]
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::AskingHuman { request_id, question, options, .. }) if request_id == "h1" && question == "Continue?" && options.len() == 2)
        );
        assert!(!outcome.completed);
        assert!(!outcome.failed);
    }
    #[test]
    fn maps_real_app_server_notifications() {
        let assistant = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/agentMessage/delta",
            "params": {"itemId": "i1", "delta": "hello"}
        }));
        assert!(
            matches!(assistant.event, Some(ChatEvent::ResponseDelta { content }) if content == "hello")
        );

        let reasoning = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/reasoning/textDelta",
            "params": {"itemId": "r1", "delta": "why"}
        }));
        assert!(
            matches!(reasoning.event, Some(ChatEvent::ReasoningDelta { content }) if content == "why")
        );

        let output = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "item/commandExecution/outputDelta",
            "params": {"itemId": "cmd1", "delta": "out"}
        }));
        assert!(
            matches!(output.event, Some(ChatEvent::ToolOutputChunk { call_id, content, stream }) if call_id == "cmd1" && content == "out" && stream == "stdout")
        );

        let done = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "method": "turn/completed",
            "params": {}
        }));
        assert!(done.completed);
    }

    #[test]
    fn maps_real_user_input_request() {
        let outcome = map_app_server_message(&json!({
            "jsonrpc": "2.0",
            "id": 9,
            "method": "item/tool/requestUserInput",
            "params": {
                "questions": [{
                    "id": "approval",
                    "header": "Confirm",
                    "question": "Proceed?",
                    "options": [{"label": "yes"}, {"label": "no"}]
                }]
            }
        }));
        assert!(
            matches!(outcome.event, Some(ChatEvent::AskingHuman { request_id, question, options, context }) if request_id.starts_with("codex:") && question == "Proceed?" && options == vec!["yes", "no"] && context.as_deref() == Some("Confirm"))
        );
        assert!(!outcome.completed);
    }
}
