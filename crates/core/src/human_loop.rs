//! Human-in-the-loop broker for active mobile sessions.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};

use serde_json::Value;
use tokio::sync::oneshot;

use crate::session::SessionAppendMessage;
use crate::tool_registry::ToolDescriptor;
use crate::types::ChatEvent;

pub const ASK_HUMAN_TOOL_NAME: &str = "ask_human";

static REQUEST_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone)]
pub struct HumanInterjection {
    pub content: String,
    pub raw_message: Value,
}

struct PendingHumanRequest {
    scope_key: String,
    session_key_json: String,
    files_dir: String,
    sender: oneshot::Sender<Result<String, String>>,
}

#[derive(Default)]
struct HumanLoopState {
    active_queues: HashMap<String, Vec<HumanInterjection>>,
    pending_requests: HashMap<String, PendingHumanRequest>,
}

fn state() -> &'static Mutex<HumanLoopState> {
    static STATE: OnceLock<Mutex<HumanLoopState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(HumanLoopState::default()))
}

pub struct ActiveHumanLoopSessionGuard {
    scope_key: String,
}

impl Drop for ActiveHumanLoopSessionGuard {
    fn drop(&mut self) {
        if let Ok(mut guard) = state().lock() {
            guard.active_queues.remove(&self.scope_key);
        }
    }
}

pub fn activate_session_scoped(
    files_dir: &str,
    session_key_json: &str,
) -> ActiveHumanLoopSessionGuard {
    let scope_key = session_scope_key(files_dir, session_key_json);
    if let Ok(mut guard) = state().lock() {
        guard.active_queues.entry(scope_key.clone()).or_default();
    }
    ActiveHumanLoopSessionGuard { scope_key }
}

pub fn enqueue_interjection_scoped(
    files_dir: &str,
    session_key_json: &str,
    interjection: HumanInterjection,
) -> bool {
    let Ok(mut guard) = state().lock() else {
        return false;
    };
    let scope_key = session_scope_key(files_dir, session_key_json);
    let Some(queue) = guard.active_queues.get_mut(&scope_key) else {
        return false;
    };
    queue.push(interjection);
    true
}

pub fn retract_latest_interjection_scoped(
    files_dir: &str,
    session_key_json: &str,
    content: &str,
) -> bool {
    let Ok(mut guard) = state().lock() else {
        return false;
    };
    let scope_key = session_scope_key(files_dir, session_key_json);
    let Some(queue) = guard.active_queues.get_mut(&scope_key) else {
        return false;
    };
    let Some(index) = queue.iter().rposition(|item| item.content == content) else {
        return false;
    };
    queue.remove(index);
    true
}

pub fn drain_interjections_scoped(
    files_dir: &str,
    session_key_json: Option<&str>,
) -> Vec<HumanInterjection> {
    let Some(session_key_json) = session_key_json else {
        return Vec::new();
    };
    let Ok(mut guard) = state().lock() else {
        return Vec::new();
    };
    let scope_key = session_scope_key(files_dir, session_key_json);
    guard
        .active_queues
        .get_mut(&scope_key)
        .map(std::mem::take)
        .unwrap_or_default()
}

pub fn cancel_session_scoped(files_dir: &str, session_key_json: &str) {
    let pending_to_cancel: Vec<(String, PendingHumanRequest)> = {
        let Ok(mut guard) = state().lock() else {
            return;
        };
        let scope_key = session_scope_key(files_dir, session_key_json);
        guard.active_queues.remove(&scope_key);
        let pending_ids = guard
            .pending_requests
            .iter()
            .filter(|&(_request_id, request)| request.scope_key == scope_key)
            .map(|(request_id, _request)| request_id.clone())
            .collect::<Vec<_>>();
        pending_ids
            .into_iter()
            .filter_map(|id| guard.pending_requests.remove(&id).map(|req| (id, req)))
            .collect()
    };
    for (request_id, request) in pending_to_cancel {
        let _ = crate::session::mark_asking_human_interrupted(
            &request.files_dir,
            &request.session_key_json,
            &request_id,
        );
        let _ = request
            .sender
            .send(Err("Human request cancelled".to_string()));
    }
}

fn session_scope_key(files_dir: &str, session_key_json: &str) -> String {
    format!("{}\x1f{}", files_dir, session_key_json)
}

pub fn descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: ASK_HUMAN_TOOL_NAME.to_string(),
        description: "Ask the user for clarification, confirmation, or missing information before continuing.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The question to show to the user."
                },
                "options": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Optional short choices the user can select."
                },
                "context": {
                    "type": "string",
                    "description": "Optional context explaining why the question is needed."
                }
            },
            "required": ["question"]
        }),
        effect: crate::tool_registry::ToolEffect::Deliver,
    }
}

pub fn is_ask_human_tool(name: &str) -> bool {
    name == ASK_HUMAN_TOOL_NAME
}

pub async fn execute_ask_human<F>(
    files_dir: &str,
    session_key_json: &str,
    params: Value,
    mut emit: F,
) -> Result<String, String>
where
    F: FnMut(ChatEvent),
{
    let question = params
        .get("question")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "ask_human requires a non-empty question".to_string())?
        .to_string();
    let options = params
        .get("options")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let context = params
        .get("context")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let request_id = format!("human_{}", REQUEST_COUNTER.fetch_add(1, Ordering::Relaxed));

    let content = serde_json::json!({
        "request_id": request_id,
        "question": question,
        "options": options,
        "context": context,
    })
    .to_string();
    let _ = crate::session::append_messages(
        files_dir,
        session_key_json,
        &[SessionAppendMessage {
            role: "asking_human".to_string(),
            content,
            interrupted: false,
            turn_id: None,
        }],
    );

    let (sender, receiver) = oneshot::channel();
    {
        let mut guard = state()
            .lock()
            .map_err(|e| format!("Human loop lock poisoned: {e}"))?;
        guard.pending_requests.insert(
            request_id.clone(),
            PendingHumanRequest {
                scope_key: session_scope_key(files_dir, session_key_json),
                session_key_json: session_key_json.to_string(),
                files_dir: files_dir.to_string(),
                sender,
            },
        );
    }

    emit(ChatEvent::AskingHuman {
        question,
        request_id: request_id.clone(),
        options,
        context,
    });

    let response = receiver
        .await
        .map_err(|_| "Human request was dropped".to_string())??;
    emit(ChatEvent::HumanResponse {
        request_id,
        response: response.clone(),
    });
    Ok(serde_json::json!({ "response": response }).to_string())
}

pub fn answer_human_request(request_id: &str, response: &str) -> bool {
    let request = {
        let Ok(mut guard) = state().lock() else {
            return false;
        };
        guard.pending_requests.remove(request_id)
    };
    let Some(request) = request else {
        return false;
    };

    let _ = crate::session::inject_user_message(
        &request.files_dir,
        &request.session_key_json,
        response,
        "[]",
    );
    request.sender.send(Ok(response.to_string())).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ask_human_descriptor_has_expected_schema() {
        let descriptor = descriptor();
        assert_eq!(descriptor.name, ASK_HUMAN_TOOL_NAME);
        assert_eq!(descriptor.parameters["required"][0], "question");
        assert!(descriptor.parameters["properties"]["options"].is_object());
    }

    #[tokio::test]
    async fn ask_human_waits_for_answer_and_persists_history() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy().to_string();
        let session_key_json =
            crate::session::create_session(&files_dir, "agent-a", "app", "user-a", None);
        let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
        let files_dir_for_task = files_dir.clone();
        let session_key_for_task = session_key_json.clone();

        let task = tokio::spawn(async move {
            execute_ask_human(
                &files_dir_for_task,
                &session_key_for_task,
                serde_json::json!({
                    "question": "Continue?",
                    "options": ["yes", "no"],
                    "context": "Need approval",
                }),
                |event| {
                    sender.send(event).unwrap();
                },
            )
            .await
        });

        let event = receiver.recv().await.unwrap();
        let request_id = match event {
            ChatEvent::AskingHuman {
                request_id,
                question,
                options,
                context,
            } => {
                assert_eq!(question, "Continue?");
                assert_eq!(options, ["yes", "no"]);
                assert_eq!(context.as_deref(), Some("Need approval"));
                request_id
            }
            other => panic!("unexpected event: {other:?}"),
        };
        assert!(answer_human_request(&request_id, "yes"));
        let output = task.await.unwrap().unwrap();
        assert_eq!(output, serde_json::json!({ "response": "yes" }).to_string());

        let thread_id =
            serde_json::from_str::<serde_json::Value>(&session_key_json).unwrap()["thread_id"]
                .as_str()
                .unwrap()
                .to_string();
        let history = serde_json::from_str::<Vec<serde_json::Value>>(&crate::session::get_history(
            &files_dir, &thread_id,
        ))
        .unwrap();
        assert_eq!(history[0]["role"], "asking_human");
        assert_eq!(history[1]["role"], "user");
        assert_eq!(history[1]["content"], "yes");
    }

    #[tokio::test]
    async fn cancel_session_marks_pending_asking_human_interrupted() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_string_lossy().to_string();
        let session_key_json =
            crate::session::create_session(&files_dir, "agent-a", "app", "user-a", None);
        let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
        let files_dir_for_task = files_dir.clone();
        let session_key_for_task = session_key_json.clone();

        let task = tokio::spawn(async move {
            execute_ask_human(
                &files_dir_for_task,
                &session_key_for_task,
                serde_json::json!({ "question": "Continue?" }),
                |event| {
                    sender.send(event).unwrap();
                },
            )
            .await
        });

        let _event = receiver.recv().await.unwrap();
        cancel_session_scoped(&files_dir, &session_key_json);
        let result = task.await.unwrap();
        assert!(result.is_err());

        let thread_id =
            serde_json::from_str::<serde_json::Value>(&session_key_json).unwrap()["thread_id"]
                .as_str()
                .unwrap()
                .to_string();
        let history = serde_json::from_str::<Vec<serde_json::Value>>(&crate::session::get_history(
            &files_dir, &thread_id,
        ))
        .unwrap();
        assert_eq!(history[0]["role"], "asking_human");
        assert_eq!(history[0]["interrupted"], serde_json::Value::Bool(true));
    }

    #[test]
    fn active_interjections_are_scoped_by_files_dir() {
        let session_key_json = r#"{"thread_id":"same","agent_id":"agent"}"#;
        let _first = activate_session_scoped("/tmp/first", session_key_json);
        let _second = activate_session_scoped("/tmp/second", session_key_json);

        assert!(enqueue_interjection_scoped(
            "/tmp/first",
            session_key_json,
            HumanInterjection {
                content: "one".to_string(),
                raw_message: serde_json::json!({"role":"user","content":"one"}),
            },
        ));

        assert!(drain_interjections_scoped("/tmp/second", Some(session_key_json)).is_empty());
        let drained = drain_interjections_scoped("/tmp/first", Some(session_key_json));
        assert_eq!(drained.len(), 1);
        assert_eq!(drained[0].content, "one");
    }

    #[tokio::test]
    async fn cancelling_one_files_dir_does_not_cancel_matching_session_elsewhere() {
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        let first_dir = first.path().to_string_lossy().to_string();
        let second_dir = second.path().to_string_lossy().to_string();
        let session_key_json = r#"{"thread_id":"same","agent_id":"agent"}"#;

        let (first_tx, first_rx) = oneshot::channel();
        let (second_tx, mut second_rx) = oneshot::channel();
        {
            let mut guard = state().lock().unwrap();
            guard.pending_requests.insert(
                "first".to_string(),
                PendingHumanRequest {
                    scope_key: session_scope_key(&first_dir, session_key_json),
                    session_key_json: session_key_json.to_string(),
                    files_dir: first_dir.clone(),
                    sender: first_tx,
                },
            );
            guard.pending_requests.insert(
                "second".to_string(),
                PendingHumanRequest {
                    scope_key: session_scope_key(&second_dir, session_key_json),
                    session_key_json: session_key_json.to_string(),
                    files_dir: second_dir.clone(),
                    sender: second_tx,
                },
            );
        }

        cancel_session_scoped(&first_dir, session_key_json);
        assert_eq!(
            first_rx.await.unwrap().unwrap_err(),
            "Human request cancelled"
        );
        assert!(second_rx.try_recv().is_err());
        assert!(answer_human_request("second", "ok"));
    }
}
