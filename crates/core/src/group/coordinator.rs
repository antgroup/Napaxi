//! Coordinator prompt, system prompt overlay, session key, event helpers.

use crate::types::ChatEvent;

use super::crud::get_group_value;

// Default-language convenience wrapper. Production callers pass the resolved
// response language via `build_coordinator_prompt_with_language`; this shim is
// exercised by the group unit tests.
#[allow(dead_code)]
pub fn build_coordinator_prompt(files_dir: &str, group_id: &str) -> Option<String> {
    build_coordinator_prompt_with_language(files_dir, group_id, "en")
}

pub fn build_coordinator_prompt_with_language(
    files_dir: &str,
    group_id: &str,
    response_language: &str,
) -> Option<String> {
    let group = get_group_value(files_dir, group_id)?;
    let agent_defs: Vec<crate::agent_definitions::AgentDefinition> =
        serde_json::from_str(&crate::agents::list_definitions(files_dir)).unwrap_or_default();

    let is_chinese = uses_chinese_prompt(response_language);
    let mut prompt = if is_chinese {
        "你是 Agent 群聊的协调者。理解用户请求，判断哪位群成员可以帮助，并产出清晰的最终回答。如果需要专门成员处理，请说明哪个成员负责哪一部分。\n\n"
            .to_string()
    } else {
        "You are the coordinator of an agent group chat. Understand the user's request, decide which group member can help, and produce a clear final response. If a specialized member is needed, explain which member should handle which part.\n\n"
            .to_string()
    };
    if is_chinese {
        prompt.push_str(&format!("群组名称: {}\n", group.name));
        prompt.push_str("群组成员:\n");
    } else {
        prompt.push_str(&format!("Group Name: {}\n", group.name));
        prompt.push_str("Group Members:\n");
    }
    for member_id in &group.members {
        if let Some(def) = agent_defs.iter().find(|def| def.id == *member_id) {
            prompt.push_str(&format!(
                "- {} ({}): {}\n",
                def.id, def.name, def.description
            ));
        } else {
            prompt.push_str(&format!("- {member_id}\n"));
        }
    }
    if let Some(custom) = &group.custom_prompt
        && !custom.trim().is_empty()
    {
        if is_chinese {
            prompt.push_str("\n自定义指令:\n");
        } else {
            prompt.push_str("\nCustom Instructions:\n");
        }
        prompt.push_str(custom);
        prompt.push('\n');
    }
    Some(prompt)
}

fn uses_chinese_prompt(response_language: &str) -> bool {
    matches!(
        response_language.trim().to_ascii_lowercase().as_str(),
        "zh" | "zh-cn" | "chinese" | "中文"
    )
}

pub fn append_system_prompt(config_json: &str, prompt: &str) -> String {
    let Ok(mut config) = serde_json::from_str::<serde_json::Value>(config_json) else {
        return config_json.to_string();
    };
    let current = config
        .get("system_prompt")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let next = if current.trim().is_empty() {
        prompt.to_string()
    } else {
        format!("{current}\n\n{prompt}")
    };
    config["system_prompt"] = serde_json::Value::String(next);
    serde_json::to_string(&config).unwrap_or_else(|_| config_json.to_string())
}

pub fn session_key(files_dir: &str, group_id: &str, agent_id: &str) -> String {
    crate::session::create_session(files_dir, agent_id, "group", group_id, Some(group_id))
}

pub fn extract_response(events_json: &str) -> Option<String> {
    let events = serde_json::from_str::<Vec<serde_json::Value>>(events_json).ok()?;
    events.iter().rev().find_map(|event| {
        if event.get("type").and_then(serde_json::Value::as_str) == Some("response") {
            event
                .get("content")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        } else {
            None
        }
    })
}

#[allow(dead_code)] // Helper for upcoming group event-wrapping flows.
pub fn wrap_events(start: serde_json::Value, events_json: &str, end: serde_json::Value) -> String {
    let mut events = vec![start];
    match serde_json::from_str::<Vec<serde_json::Value>>(events_json) {
        Ok(mut tail) => events.append(&mut tail),
        Err(_) => events.push(serde_json::json!({
            "type": "error",
            "message": events_json,
        })),
    }
    events.push(end);
    serde_json::to_string(&events).unwrap_or_else(|_| "[]".to_string())
}

pub fn group_members_text(files_dir: &str, group_id: &str) -> String {
    let Some(group) = get_group_value(files_dir, group_id) else {
        return format!("Group not found: {group_id}");
    };
    let defs: Vec<crate::agent_definitions::AgentDefinition> =
        serde_json::from_str(&crate::agents::list_definitions(files_dir)).unwrap_or_default();
    let mut out = format!(
        "Group: {}\nCoordinator: {}\nMembers:",
        group.name, group.coordinator
    );
    for member in group.members {
        if let Some(def) = defs.iter().find(|def| def.id == member) {
            out.push_str(&format!(
                "\n- {} ({}) - {}",
                def.id, def.name, def.description
            ));
        } else {
            out.push_str(&format!("\n- {member}"));
        }
    }
    out
}

pub(super) fn events_json(events: &[ChatEvent]) -> String {
    serde_json::to_string(events).unwrap_or_else(|_| "[]".to_string())
}

pub(super) fn response_from_events(events: &[ChatEvent]) -> Option<String> {
    events.iter().rev().find_map(|event| match event {
        ChatEvent::Response { content } => Some(content.clone()),
        _ => None,
    })
}
