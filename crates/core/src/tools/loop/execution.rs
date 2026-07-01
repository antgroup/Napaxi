use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use crate::llm;
use crate::tool_registry::{
    ToolDescriptor, ToolEffect, ToolExecutionContext, ToolRegistry, prepare_tool_arguments,
    redact_tool_arguments_json, sanitize_tool_output,
};
use crate::types::{ChatEvent, PlatformLlmConfig};
use tokio::sync::mpsc;
use tokio::time::{MissedTickBehavior, interval};

use super::runtime::prepare_tool_invocation;
use super::types::TOOL_CALL_CANCEL;
use super::{InternalToolHandler, InternalToolProgressEvent, ToolTrace};

const TOOL_CANCEL_POLL_INTERVAL: Duration = Duration::from_millis(100);
/// Bounded wait between cancel-flag flip and force-returning. Even cooperative
/// handlers can spend a few hundred ms killing a child process; uncooperative
/// handlers (Reqwest in flight, host-side custom tools that ignore cancel)
/// must still let the turn return so the UI can render a terminal state and
/// the orchestration layer can persist the cancelled turn.
const TOOL_CANCEL_GRACE_PERIOD: Duration = Duration::from_secs(2);
const TOOL_CANCEL_OUTPUT: &str = "Tool execution cancelled by user.";

pub(super) async fn execute_turn_tool_calls<F, C>(
    turn: llm::LlmTurn,
    config: &PlatformLlmConfig,
    tools: Option<&Arc<ToolRegistry>>,
    internal_tool_handler: Option<&InternalToolHandler>,
    descriptors: &[ToolDescriptor],
    tool_execution_context: Option<&ToolExecutionContext>,
    messages: &mut Vec<serde_json::Value>,
    trace: &mut ToolTrace,
    allow_human_loop: bool,
    mut should_cancel: C,
    emit: &mut F,
) -> Result<usize, String>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    let mut tool_call_count = 0usize;
    push_assistant_tool_call_message(messages, &turn);

    for call in turn.tool_calls {
        if should_cancel() {
            return Err("Chat cancelled".to_string());
        }
        if crate::skills::is_hidden_skill_tool(&call.name) {
            let (output, _is_error, events) = execute_tool_call(
                &call.id,
                config,
                tools,
                internal_tool_handler,
                descriptors,
                &call.name,
                &call.arguments,
                tool_execution_context,
                &mut should_cancel,
                emit,
            )
            .await;
            for event in events {
                emit(event);
            }
            messages.push(serde_json::json!({
                "role": "tool",
                "tool_call_id": call.id,
                "content": sanitize_tool_output(&output),
            }));
            continue;
        }
        if crate::human_loop::is_ask_human_tool(&call.name) {
            let arguments = redact_tool_arguments_json(&call.arguments);
            let effect = descriptor_effect(descriptors, &call.name);
            trace.push_tool_call(
                call.id.clone(),
                call.name.clone(),
                arguments.clone(),
                effect,
            );
            emit(ChatEvent::ToolCall {
                call_id: call.id.clone(),
                name: call.name.clone(),
                arguments,
            });
            let output = execute_ask_human_call(
                descriptors,
                &call.arguments,
                tool_execution_context,
                allow_human_loop,
                emit,
            )
            .await;
            let output = sanitize_tool_output(&output);
            trace.finish_tool_call(&call.id, output.clone(), false);
            emit(ChatEvent::ToolResult {
                call_id: call.id.clone(),
                name: call.name.clone(),
                output: output.clone(),
                is_error: false,
            });
            messages.push(serde_json::json!({
                "role": "tool",
                "tool_call_id": call.id,
                "content": output,
            }));
            tool_call_count = tool_call_count.saturating_add(1);
            continue;
        }
        let arguments = redact_tool_arguments_json(&call.arguments);
        let effect = descriptor_effect(descriptors, &call.name);
        trace.push_tool_call(
            call.id.clone(),
            call.name.clone(),
            arguments.clone(),
            effect,
        );
        emit(ChatEvent::ToolCall {
            call_id: call.id.clone(),
            name: call.name.clone(),
            arguments,
        });
        let (output, is_error, events) = execute_tool_call(
            &call.id,
            config,
            tools,
            internal_tool_handler,
            descriptors,
            &call.name,
            &call.arguments,
            tool_execution_context,
            &mut should_cancel,
            emit,
        )
        .await;
        for event in events {
            emit(event);
        }
        let output = sanitize_tool_output(&output);
        trace.finish_tool_call(&call.id, output.clone(), is_error);
        emit(ChatEvent::ToolResult {
            call_id: call.id.clone(),
            name: call.name.clone(),
            output: output.clone(),
            is_error,
        });
        messages.push(serde_json::json!({
            "role": "tool",
            "tool_call_id": call.id,
            "content": output,
        }));
        tool_call_count = tool_call_count.saturating_add(1);
    }

    Ok(tool_call_count)
}

fn descriptor_effect(descriptors: &[ToolDescriptor], name: &str) -> ToolEffect {
    descriptors
        .iter()
        .find(|descriptor| descriptor.name == name)
        .map(|descriptor| descriptor.effect)
        .unwrap_or_default()
}

pub(super) async fn execute_tool_call<F, C>(
    call_id: &str,
    config: &PlatformLlmConfig,
    tools: Option<&Arc<ToolRegistry>>,
    internal_tool_handler: Option<&InternalToolHandler>,
    descriptors: &[ToolDescriptor],
    name: &str,
    arguments: &str,
    tool_execution_context: Option<&ToolExecutionContext>,
    should_cancel: &mut C,
    emit: &mut F,
) -> (String, bool, Vec<ChatEvent>)
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool + ?Sized,
{
    let prepared = match prepare_tool_invocation(config, descriptors, name, arguments) {
        Ok(prepared) => prepared,
        Err(error) => return (error.into_model_output(), true, Vec::new()),
    };
    let params = prepared.params;
    let route = prepared.route;
    let execute_name = prepared.name;
    if let Some(handler) = internal_tool_handler {
        let (progress_tx, mut progress_rx) = mpsc::unbounded_channel();
        if let Some(handler_future) = handler(&execute_name, params.clone(), Some(progress_tx)) {
            let cancel_flag: Arc<AtomicBool> = Arc::new(AtomicBool::new(should_cancel()));
            let scoped_future = TOOL_CALL_CANCEL.scope(cancel_flag.clone(), handler_future);
            let mut future = Box::pin(scoped_future);
            let mut cancel_ticker = interval(TOOL_CANCEL_POLL_INTERVAL);
            cancel_ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);
            cancel_ticker.tick().await;
            let cancel_signalled = cancel_flag.load(Ordering::Relaxed);
            loop {
                tokio::select! {
                    result = &mut future => {
                        let _ = drain_progress_events(Some(call_id), &mut progress_rx, emit);
                        return finalize_internal_tool_result(
                            call_id,
                            &execute_name,
                            result,
                            cancel_signalled,
                            emit,
                        );
                    }
                    maybe_progress = progress_rx.recv() => {
                        match maybe_progress {
                            Some(progress) => (*emit)(ChatEvent::ToolOutputChunk {
                                call_id: call_id.to_string(),
                                content: progress.content,
                                stream: progress.stream,
                            }),
                            None => continue,
                        }
                    }
                    _ = cancel_ticker.tick(), if !cancel_signalled => {
                        if should_cancel() || cancel_flag.load(Ordering::Relaxed) {
                            cancel_flag.store(true, Ordering::Relaxed);
                            break;
                        }
                    }
                }
            }

            return wait_for_cancel_with_grace(call_id, name, future, progress_rx, emit).await;
        }
    }

    match tools {
        Some(tools) => {
            let custom_future = tools.execute_custom_tool_with_context(
                &execute_name,
                params,
                tool_execution_context,
            );
            let mut custom_future = Box::pin(custom_future);
            let mut cancel_ticker = interval(TOOL_CANCEL_POLL_INTERVAL);
            cancel_ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);
            cancel_ticker.tick().await;
            loop {
                tokio::select! {
                    result = &mut custom_future => {
                        return match result {
                            Ok(output) => (annotate_routed_tool_output(output, route.as_ref()), false, Vec::new()),
                            Err(error) => (error, true, Vec::new()),
                        };
                    }
                    _ = cancel_ticker.tick() => {
                        if should_cancel() {
                            return wait_for_custom_cancel_with_grace(custom_future).await;
                        }
                    }
                }
            }
        }
        None => (format!("Tool not found: {name}"), true, Vec::new()),
    }
}

fn annotate_routed_tool_output(
    output: String,
    route: Option<&super::runtime::ToolIntentRouteMetadata>,
) -> String {
    let Some(route) = route else {
        return output;
    };
    match serde_json::from_str::<serde_json::Value>(&output) {
        Ok(serde_json::Value::Object(mut object)) => {
            object
                .entry("intent".to_string())
                .or_insert_with(|| serde_json::Value::String(route.intent_id.to_string()));
            object
                .entry("routedFromTool".to_string())
                .or_insert_with(|| serde_json::Value::String(route.source_tool.to_string()));
            object
                .entry("routedToTool".to_string())
                .or_insert_with(|| serde_json::Value::String(route.target_tool.to_string()));
            serde_json::Value::Object(object).to_string()
        }
        _ => serde_json::json!({
            "success": true,
            "output": output,
            "intent": route.intent_id,
            "routedFromTool": route.source_tool,
            "routedToTool": route.target_tool,
        })
        .to_string(),
    }
}

pub(crate) async fn execute_single_tool_call_for_broker<F, C>(
    call_id: &str,
    config: &PlatformLlmConfig,
    tools: Option<&Arc<ToolRegistry>>,
    internal_tool_handler: Option<&InternalToolHandler>,
    descriptors: &[ToolDescriptor],
    name: &str,
    arguments: &str,
    tool_execution_context: Option<&ToolExecutionContext>,
    should_cancel: &mut C,
    emit: &mut F,
) -> (String, bool, Vec<ChatEvent>, ToolEffect)
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool + ?Sized,
{
    let effect = descriptor_effect(descriptors, name);
    let (output, is_error, events) = execute_tool_call(
        call_id,
        config,
        tools,
        internal_tool_handler,
        descriptors,
        name,
        arguments,
        tool_execution_context,
        should_cancel,
        emit,
    )
    .await;
    (output, is_error, events, effect)
}

fn finalize_internal_tool_result<F>(
    call_id: &str,
    _name: &str,
    result: Result<crate::tool_loop::InternalToolResult, String>,
    cancel_signalled: bool,
    _emit: &mut F,
) -> (String, bool, Vec<ChatEvent>)
where
    F: FnMut(ChatEvent),
{
    let _ = call_id;
    match result {
        Ok(result) if cancel_signalled => (TOOL_CANCEL_OUTPUT.to_string(), true, result.events),
        Ok(result) => (result.output, false, result.events),
        Err(_) if cancel_signalled => (TOOL_CANCEL_OUTPUT.to_string(), true, Vec::new()),
        Err(error) => (error, true, Vec::new()),
    }
}

async fn wait_for_cancel_with_grace<F, Fut>(
    call_id: &str,
    name: &str,
    mut future: std::pin::Pin<Box<Fut>>,
    mut progress_rx: mpsc::UnboundedReceiver<InternalToolProgressEvent>,
    emit: &mut F,
) -> (String, bool, Vec<ChatEvent>)
where
    F: FnMut(ChatEvent),
    Fut:
        std::future::Future<Output = Result<crate::tool_loop::InternalToolResult, String>> + ?Sized,
{
    let deadline = tokio::time::Instant::now() + TOOL_CANCEL_GRACE_PERIOD;
    loop {
        tokio::select! {
            result = &mut future => {
                let _ = drain_progress_events(Some(call_id), &mut progress_rx, emit);
                return finalize_internal_tool_result(call_id, name, result, true, emit);
            }
            maybe_progress = progress_rx.recv() => {
                if let Some(progress) = maybe_progress {
                    emit(ChatEvent::ToolOutputChunk {
                        call_id: call_id.to_string(),
                        content: progress.content,
                        stream: progress.stream,
                    });
                }
            }
            _ = tokio::time::sleep_until(deadline) => {
                drop(future);
                let _ = drain_progress_events(Some(call_id), &mut progress_rx, emit);
                return (TOOL_CANCEL_OUTPUT.to_string(), true, Vec::new());
            }
        }
    }
}

async fn wait_for_custom_cancel_with_grace<F>(
    mut custom_future: std::pin::Pin<Box<F>>,
) -> (String, bool, Vec<ChatEvent>)
where
    F: std::future::Future<Output = Result<String, String>> + ?Sized,
{
    let deadline = tokio::time::Instant::now() + TOOL_CANCEL_GRACE_PERIOD;
    tokio::select! {
        result = &mut custom_future => match result {
            Ok(_) | Err(_) => (TOOL_CANCEL_OUTPUT.to_string(), true, Vec::new()),
        },
        _ = tokio::time::sleep_until(deadline) => {
            drop(custom_future);
            (TOOL_CANCEL_OUTPUT.to_string(), true, Vec::new())
        }
    }
}

fn drain_progress_events<F>(
    call_id: Option<&str>,
    receiver: &mut mpsc::UnboundedReceiver<InternalToolProgressEvent>,
    emit: &mut F,
) -> Vec<ChatEvent>
where
    F: FnMut(ChatEvent),
{
    let mut events = Vec::new();
    while let Ok(event) = receiver.try_recv() {
        if let Some(call_id) = call_id {
            let chat_event = ChatEvent::ToolOutputChunk {
                call_id: call_id.to_string(),
                content: event.content,
                stream: event.stream,
            };
            emit(chat_event.clone());
            events.push(chat_event);
        }
    }
    events
}

pub(super) async fn execute_ask_human_call<F>(
    descriptors: &[ToolDescriptor],
    arguments: &str,
    tool_execution_context: Option<&ToolExecutionContext>,
    allow_human_loop: bool,
    emit: &mut F,
) -> String
where
    F: FnMut(ChatEvent),
{
    if !allow_human_loop {
        return "ask_human is only supported in streaming session turns".to_string();
    }
    let Some(context) = tool_execution_context else {
        return "ask_human is unavailable without a session context".to_string();
    };
    let Some(session_key_json) = context.session_key_json.as_deref() else {
        return "ask_human is unavailable without a session key".to_string();
    };
    let params = serde_json::from_str::<serde_json::Value>(arguments)
        .unwrap_or_else(|_| serde_json::json!({}));
    let Some(descriptor) = descriptors
        .iter()
        .find(|descriptor| crate::human_loop::is_ask_human_tool(&descriptor.name))
    else {
        return "Tool not found: ask_human".to_string();
    };
    let params = match prepare_tool_arguments(descriptor, params) {
        Ok(params) => params,
        Err(error) => return format!("Invalid arguments for tool 'ask_human': {error}"),
    };
    match crate::human_loop::execute_ask_human(&context.files_dir, session_key_json, params, emit)
        .await
    {
        Ok(output) => output,
        Err(error) => error,
    }
}

pub(super) fn drain_interjections_into_messages<F>(
    tool_execution_context: Option<&ToolExecutionContext>,
    messages: &mut Vec<serde_json::Value>,
    emit: &mut F,
) where
    F: FnMut(ChatEvent),
{
    let files_dir = tool_execution_context
        .map(|context| context.files_dir.as_str())
        .unwrap_or("");
    let session_key_json =
        tool_execution_context.and_then(|context| context.session_key_json.as_deref());
    for interjection in crate::human_loop::drain_interjections_scoped(files_dir, session_key_json) {
        emit(ChatEvent::MessageInjected {
            content: interjection.content,
        });
        messages.push(interjection.raw_message);
    }
}

pub(super) fn push_assistant_tool_call_message(
    messages: &mut Vec<serde_json::Value>,
    turn: &llm::LlmTurn,
) {
    let assistant_tool_calls: Vec<serde_json::Value> = turn
        .tool_calls
        .iter()
        .map(|call| {
            serde_json::json!({
                "id": call.id,
                "type": "function",
                "function": {
                    "name": call.name,
                    "arguments": call.arguments,
                }
            })
        })
        .collect();
    messages.push(serde_json::json!({
        "role": "assistant",
        "content": if turn.content.is_empty() { serde_json::Value::Null } else { serde_json::Value::String(turn.content.clone()) },
        "reasoning_content": turn.reasoning_content.clone().unwrap_or_default(),
        "tool_calls": assistant_tool_calls,
    }));
}

pub(super) fn append_tool_limit_final_message(messages: &mut Vec<serde_json::Value>, limit: usize) {
    messages.push(serde_json::json!({
        "role": "user",
        "content": tool_limit_final_message(limit),
    }));
}

fn tool_limit_final_message(limit: usize) -> String {
    format!(
        "The configured tool-call budget has been reached after {limit} visible tool turns. Do not request or call any more tools. Use the tool results already present in this conversation to produce the best possible final response. If something remains unresolved, state what is missing briefly instead of trying more tools. Answer in the user's language."
    )
}

pub(super) fn tool_limit_synthesis_error(limit: usize, error: impl std::fmt::Display) -> String {
    format!(
        "Tool execution reached max iterations after {limit} visible tool turns, and final response synthesis failed: {error}"
    )
}

pub(super) fn tool_limit_extra_tool_error(limit: usize) -> String {
    format!(
        "Tool execution reached max iterations after {limit} visible tool turns, and the model requested more tools during final response synthesis"
    )
}
