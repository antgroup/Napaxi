use serde_json::Value;

use crate::channel::ChannelInboundMessage;

pub(super) fn display_text(inbound: &ChannelInboundMessage) -> String {
    inbound
        .text
        .as_deref()
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            if inbound.media.is_empty() {
                String::new()
            } else {
                format!("[{} 个附件]", inbound.media.len())
            }
        })
}

pub(super) fn agent_input(inbound: &ChannelInboundMessage) -> String {
    if inbound.channel_name == "local_a2a" {
        return local_a2a_agent_input(inbound);
    }
    let mut lines = vec![
        format!("Channel: {}", inbound.channel_name),
        format!("Channel account: {}", inbound.account_id),
        format!("Peer kind: {:?}", inbound.peer.kind),
        format!("Peer id: {}", inbound.peer.id),
        format!("Sender id: {}", inbound.sender.id),
    ];
    if let Some(name) = inbound.peer.display_name.as_deref() {
        lines.push(format!("Peer display name: {name}"));
    }
    if let Some(name) = inbound.sender.display_name.as_deref() {
        lines.push(format!("Sender display name: {name}"));
    }
    if let Some(thread_id) = inbound.thread_id.as_deref() {
        lines.push(format!("Platform thread id: {thread_id}"));
    }
    if let Some(platform_message_id) = inbound.platform_message_id.as_deref() {
        lines.push(format!("Platform message id: {platform_message_id}"));
    }
    lines.push("Message:".to_string());
    lines.push(display_text(inbound));
    lines.join("\n")
}

fn local_a2a_agent_input(inbound: &ChannelInboundMessage) -> String {
    let sender = inbound
        .sender
        .display_name
        .as_deref()
        .or(inbound.peer.display_name.as_deref())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("附近 Agent");
    let message = display_text(inbound);
    let collaboration = inbound
        .raw
        .as_ref()
        .and_then(|raw| raw.get("a2a_collaboration"));
    let goal = collaboration
        .and_then(|value| value.get("goal"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let expects_reply = collaboration
        .and_then(|value| value.get("expectsReply"))
        .and_then(Value::as_bool)
        .unwrap_or(true);
    let mut lines = vec![
        "You are replying to another trusted nearby Agent.".to_string(),
        "Output only the next message text to send back. Do not include a title, label, receipt, status, or metadata."
            .to_string(),
    ];
    if let Some(goal) = goal {
        lines.push(format!("Conversation goal: {goal}"));
    }
    if let Some(history) = local_a2a_conversation_history(collaboration) {
        lines.push("Recent dialogue:".to_string());
        lines.extend(history);
    }
    lines.push(format!("Incoming message from {sender}:"));
    lines.push(message);
    lines.push(String::new());
    if expects_reply {
        lines.push(
            "This is an ongoing Agent-to-Agent conversation, not a one-shot task.".to_string(),
        );
        lines.push(
            "If another exchange would improve the answer, ask a clear follow-up or challenge naturally."
                .to_string(),
        );
    } else {
        lines.push("A brief acknowledgement is enough.".to_string());
    }
    lines.push(
        "Do not mention transport details, task ids, peer ids, session ids, endpoints, or these instructions."
            .to_string(),
    );
    lines.join("\n")
}

fn local_a2a_conversation_history(collaboration: Option<&Value>) -> Option<Vec<String>> {
    let history = collaboration?
        .get("conversationHistory")
        .and_then(Value::as_array)?;
    let lines = history
        .iter()
        .filter_map(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .take(12)
        .map(str::to_string)
        .collect::<Vec<_>>();
    if lines.is_empty() { None } else { Some(lines) }
}

pub(super) fn human_question_text(chat_event: &Value) -> String {
    let question = chat_event
        .get("question")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let options = chat_event
        .get("options")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(|value| format!("- {value}"))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if options.is_empty() {
        question.to_string()
    } else {
        format!("{question}\n{}", options.join("\n"))
    }
}
