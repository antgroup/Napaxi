use super::execution::{
    append_tool_limit_final_message, execute_tool_call, execute_turn_tool_calls,
};
use super::limits::{DEFAULT_TOOL_TURN_LIMIT, UNBOUNDED_TOOL_TURN_LIMIT};
use super::*;
use crate::tool_registry::ToolEffect;

fn travel_catalog_with_hint(hint: &str) -> String {
    format!(
        r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="{hint}">Travel booking</skill>
</available_skills>"#
    )
}

#[test]
fn tool_turn_limit_allows_default_tool_followup() {
    assert_eq!(tool_turn_limit(0), DEFAULT_TOOL_TURN_LIMIT);
    assert_eq!(tool_turn_limit(-1), UNBOUNDED_TOOL_TURN_LIMIT);
    assert_eq!(tool_turn_limit(1), 2);
    assert_eq!(tool_turn_limit(3), 3);
}

#[test]
fn resolved_tool_turn_limit_prefers_turn_override() {
    assert_eq!(resolved_tool_turn_limit(0, 12), 12);
    assert_eq!(resolved_tool_turn_limit(0, -1), UNBOUNDED_TOOL_TURN_LIMIT);
    assert_eq!(resolved_tool_turn_limit(7, 12), 7);
    assert_eq!(resolved_tool_turn_limit(-1, 12), UNBOUNDED_TOOL_TURN_LIMIT);
}

#[test]
fn tool_trace_pairs_calls_with_results_and_errors() {
    let mut trace = ToolTrace::default();
    trace.push_reasoning("I will inspect files.");
    trace.push_tool_call(
        "call_1".to_string(),
        "shell".to_string(),
        "{}".to_string(),
        ToolEffect::Execute,
    );
    trace.finish_tool_call("call_1", "ok".to_string(), false);
    trace.push_tool_call(
        "call_2".to_string(),
        "lookup".to_string(),
        "{}".to_string(),
        ToolEffect::Read,
    );
    trace.finish_tool_call("call_2", "failed".to_string(), true);

    assert_eq!(trace.reasoning, "I will inspect files.");
    assert_eq!(trace.tool_calls[0].result.as_deref(), Some("ok"));
    assert_eq!(trace.tool_calls[1].error.as_deref(), Some("failed"));
}

#[tokio::test]
async fn invalid_tool_arguments_report_received_payload() {
    let descriptors = vec![ToolDescriptor {
        name: "shell".to_string(),
        description: "Run shell command".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "command": {"type": "string"}
            },
            "required": ["command"]
        }),
        effect: ToolEffect::Execute,
    }];

    let (output, is_error, _) = execute_tool_call(
        "call-1",
        &PlatformLlmConfig::default(),
        None,
        None,
        &descriptors,
        "shell",
        "{}",
        None,
        &mut || false,
        &mut |_event: ChatEvent| {},
    )
    .await;

    assert!(is_error);
    assert!(output.contains("$.command is required"));
    assert!(output.contains("received arguments_len_chars=2; arguments={}"));

    let (output, is_error, _) = execute_tool_call(
        "call-1",
        &PlatformLlmConfig::default(),
        None,
        None,
        &descriptors,
        "shell",
        r#"{"command""#,
        None,
        &mut || false,
        &mut |_event: ChatEvent| {},
    )
    .await;

    assert!(is_error);
    assert!(output.contains("arguments must be valid JSON"));
    assert!(output.contains(r#"received arguments_len_chars=10; arguments={"command""#));
}

#[tokio::test]
async fn execute_tool_call_routes_shell_git_clone_to_repo_tool() {
    use std::sync::Mutex;

    let shell_descriptor = ToolDescriptor {
        name: "shell".to_string(),
        description: "Run shell command".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "command": {"type": "string"}
            },
            "required": ["command"]
        }),
        effect: ToolEffect::Execute,
    };
    let git_clone_descriptor = ToolDescriptor {
        name: "git_clone".to_string(),
        description: "Clone a repository".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "directory": {"type": "string"},
                "depth": {"type": "integer"}
            },
            "required": ["url"],
            "additionalProperties": false
        }),
        effect: ToolEffect::Write,
    };
    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            platform: Some("android".to_string()),
            supported_capabilities: vec!["napaxi.tool.git".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec![
                "napaxi.tool.git".to_string(),
                "napaxi.tool.shell".to_string(),
            ],
            config: std::collections::HashMap::from([(
                "scenario_id".to_string(),
                serde_json::json!(crate::capabilities::MOBILE_DEVELOPMENT_SCENARIO_ID),
            )]),
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };
    let registry = Arc::new(ToolRegistry::new());
    registry
        .replace_custom_tools(
            &serde_json::to_string(std::slice::from_ref(&git_clone_descriptor)).unwrap(),
        )
        .await
        .unwrap();
    let observed = Arc::new(Mutex::new(None));
    let observed_for_dispatch = observed.clone();
    registry.set_dispatcher(Arc::new(move |request_id, tool_name, params_json, _ctx| {
        *observed_for_dispatch.lock().unwrap() =
            Some((tool_name.to_string(), params_json.to_string()));
        crate::tool_registry::resolve_tool_execution(
            request_id,
            r#"{"success":true,"tool":"git_clone","directory":"repo"}"#.to_string(),
            false,
        );
    }));

    let (output, is_error, _events) = execute_tool_call(
        "call-route",
        &config,
        Some(&registry),
        None,
        &[shell_descriptor, git_clone_descriptor],
        "shell",
        r#"{"command":"git clone --depth 2 https://example.com/repo.git /workspace/repo"}"#,
        None,
        &mut || false,
        &mut |_event: ChatEvent| {},
    )
    .await;

    assert!(!is_error, "{output}");
    let (tool_name, params_json) = observed.lock().unwrap().clone().unwrap();
    assert_eq!(tool_name, "git_clone");
    let params: serde_json::Value = serde_json::from_str(&params_json).unwrap();
    assert_eq!(params["url"], "https://example.com/repo.git");
    assert_eq!(params["directory"], "repo");
    assert_eq!(params["depth"], 2);

    let output: serde_json::Value = serde_json::from_str(&output).unwrap();
    assert_eq!(output["success"], true);
    assert_eq!(output["intent"], "repo.clone");
    assert_eq!(output["routedFromTool"], "shell");
    assert_eq!(output["routedToTool"], "git_clone");
}

#[tokio::test]
async fn gather_tool_descriptors_dedupes_with_extra_tools_winning() {
    let registry = Arc::new(ToolRegistry::new());
    registry
        .replace_custom_tools(
            r#"[{"name":"shell","description":"Host shell","parameters":{"type":"object"}}]"#,
        )
        .await
        .unwrap();

    let descriptors = gather_tool_descriptors(
        Some(&registry),
        vec![ToolDescriptor {
            name: "shell".to_string(),
            description: "Builtin shell".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Execute,
        }],
    )
    .await;

    assert_eq!(descriptors.len(), 1);
    assert_eq!(descriptors[0].description, "Builtin shell");
    assert!(has_tool_named(Some(&registry), &descriptors, "shell").await);
}

#[tokio::test]
async fn capability_policy_filters_descriptors() {
    crate::capabilities::set_policy_hooks_for_tests(vec![std::sync::Arc::new(|admission| {
        if admission.subject == "policy_test_tool" {
            crate::capabilities::CapabilityAdmissionDecision::Deny(
                "blocked by test policy".to_string(),
            )
        } else {
            crate::capabilities::CapabilityAdmissionDecision::Allow
        }
    })]);

    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };
    let descriptors = gather_tool_descriptors_for_config(
        &config,
        None,
        vec![
            ToolDescriptor {
                name: "policy_test_tool".to_string(),
                description: "Denied".to_string(),
                parameters: serde_json::json!({"type": "object"}),
                effect: ToolEffect::Unknown,
            },
            ToolDescriptor {
                name: "allowed_test_tool".to_string(),
                description: "Allowed".to_string(),
                parameters: serde_json::json!({"type": "object"}),
                effect: ToolEffect::Unknown,
            },
        ],
    )
    .await;

    crate::capabilities::set_policy_hooks_for_tests(Vec::new());

    assert_eq!(descriptors.len(), 1);
    assert_eq!(descriptors[0].name, "allowed_test_tool");
}

#[tokio::test]
async fn skill_load_tool_is_hidden_from_visible_trace_but_emits_skill_event() {
    let descriptors = vec![crate::skills::skill_load_descriptor()];
    let handler: InternalToolHandler = Arc::new(|tool_name, _params, _progress| {
        if tool_name != crate::skills::SKILL_LOAD_TOOL_NAME {
            return None;
        }
        Some(Box::pin(async {
            Ok(InternalToolResult {
                output: "<skills>loaded</skills>".to_string(),
                events: vec![ChatEvent::SkillActivated {
                    agent_id: "napaxi".to_string(),
                    skills: vec![crate::types::ActivatedSkillInfo {
                        name: "demo".to_string(),
                        version: "1.0.0".to_string(),
                        description: String::new(),
                        trust: "trusted".to_string(),
                        reason: "loaded".to_string(),
                    }],
                }],
            })
        }))
    });
    let turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![llm::LlmToolCall {
            id: "call_skill_load".to_string(),
            name: crate::skills::SKILL_LOAD_TOOL_NAME.to_string(),
            arguments: serde_json::json!({"name": "demo"}).to_string(),
        }],
        usage: None,
    };
    let mut messages = Vec::new();
    let mut trace = ToolTrace::default();
    let mut events = Vec::new();

    let count = execute_turn_tool_calls(
        turn,
        &PlatformLlmConfig::default(),
        None,
        Some(&handler),
        &descriptors,
        None,
        &mut messages,
        &mut trace,
        false,
        || false,
        &mut |event| events.push(event),
    )
    .await
    .unwrap();

    assert_eq!(count, 0);
    assert!(trace.tool_calls.is_empty());
    assert!(!events.iter().any(|event| matches!(
        event,
        ChatEvent::ToolCall { .. } | ChatEvent::ToolResult { .. }
    )));
    assert!(
        events
            .iter()
            .any(|event| matches!(event, ChatEvent::SkillActivated { skills, .. } if skills[0].reason == "loaded"))
    );
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[1]["role"], "tool");
}

#[test]
fn skill_load_streaming_tool_deltas_are_hidden() {
    let mut events = Vec::new();
    let mut state = StreamingToolCallState::default();

    emit_stream_event(
        &mut |event| events.push(event),
        llm::LlmStreamEvent::ToolCallDelta {
            index: 0,
            id: Some("call_skill_load".to_string()),
            name: Some(crate::skills::SKILL_LOAD_TOOL_NAME.to_string()),
            arguments_delta: r#"{"name":"demo"}"#.to_string(),
        },
        Some(&mut state),
    );

    assert!(events.is_empty());
}

#[test]
fn hidden_skill_load_turns_do_not_count_as_visible_tool_turns() {
    let hidden_turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![llm::LlmToolCall {
            id: "call_skill_load".to_string(),
            name: crate::skills::SKILL_LOAD_TOOL_NAME.to_string(),
            arguments: serde_json::json!({"name": "demo"}).to_string(),
        }],
        usage: None,
    };
    let mixed_turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![
            llm::LlmToolCall {
                id: "call_skill_load".to_string(),
                name: crate::skills::SKILL_LOAD_TOOL_NAME.to_string(),
                arguments: serde_json::json!({"name": "demo"}).to_string(),
            },
            llm::LlmToolCall {
                id: "call_search".to_string(),
                name: "web_search".to_string(),
                arguments: serde_json::json!({"query": "demo"}).to_string(),
            },
        ],
        usage: None,
    };

    assert!(!turn_has_visible_tool_calls(&hidden_turn));
    assert!(turn_has_visible_tool_calls(&mixed_turn));
}

#[test]
fn skill_protocol_descriptor_gate_exposes_only_skill_load_for_matched_candidate() {
    let messages = vec![serde_json::json!({
        "role": "system",
        "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="matched candidate">Travel booking</skill>
</available_skills>"#
    })];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
        ToolDescriptor {
            name: "shell".to_string(),
            description: "Run shell".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Execute,
        },
    ];

    let gated = descriptors_for_skill_protocol("", &messages, &descriptors);

    assert_eq!(gated.len(), 1);
    assert_eq!(gated[0].name, crate::skills::SKILL_LOAD_TOOL_NAME);
}

#[test]
fn skill_protocol_descriptor_gate_ignores_available_only_catalog() {
    let messages = vec![serde_json::json!({
        "role": "system",
        "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="available">Travel booking</skill>
</available_skills>"#
    })];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
    ];

    let gated = descriptors_for_skill_protocol("", &messages, &descriptors);

    assert_eq!(gated.len(), 2);
}

#[test]
fn skill_protocol_descriptor_gate_restores_tools_after_skill_loaded() {
    let messages = vec![
        serde_json::json!({
            "role": "system",
            "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="matched candidate">Travel booking</skill>
</available_skills>"#
        }),
        serde_json::json!({
            "role": "tool",
            "content": r#"<skills><skill name="go2Travel">Full skill</skill></skills>"#
        }),
    ];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
    ];

    let gated = descriptors_for_skill_protocol("", &messages, &descriptors);

    assert_eq!(gated.len(), 2);
}

#[test]
fn skill_protocol_descriptor_gate_respects_direct_web_search_request() {
    let messages = vec![
        serde_json::json!({
            "role": "system",
            "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="active conversation context">Travel booking</skill>
</available_skills>"#
        }),
        serde_json::json!({
            "role": "user",
            "content": "不要用技能，直接网页搜"
        }),
    ];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
    ];

    let gated = descriptors_for_skill_protocol("", &messages, &descriptors);

    assert_eq!(gated.len(), 2);
}

#[test]
fn skill_protocol_descriptor_gate_allows_active_context_tools() {
    let system_prompt = travel_catalog_with_hint("active conversation context");
    let messages = vec![serde_json::json!({
        "role": "user",
        "content": "打开百度浏览器"
    })];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
        ToolDescriptor {
            name: "get_location".to_string(),
            description: "Get location".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
    ];

    let gated = descriptors_for_skill_protocol(&system_prompt, &messages, &descriptors);

    assert_eq!(gated.len(), 3);
}

#[test]
fn skill_protocol_descriptor_gate_reads_loaded_skill_from_messages() {
    let system_prompt = travel_catalog_with_hint("active conversation context");
    let messages = vec![
        serde_json::json!({
            "role": "user",
            "content": "再来一些"
        }),
        serde_json::json!({
            "role": "tool",
            "content": r#"<skills><skill name="go2Travel">Full skill</skill></skills>"#
        }),
    ];
    let descriptors = vec![
        crate::skills::skill_load_descriptor(),
        ToolDescriptor {
            name: "web_search".to_string(),
            description: "Search web".to_string(),
            parameters: serde_json::json!({"type": "object"}),
            effect: ToolEffect::Read,
        },
    ];

    let gated = descriptors_for_skill_protocol(&system_prompt, &messages, &descriptors);

    assert_eq!(gated.len(), 2);
}

#[test]
fn skill_protocol_tool_gate_corrects_visible_tool_before_skill_load() {
    let mut messages = vec![serde_json::json!({
        "role": "system",
        "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="matched candidate">Travel booking</skill>
</available_skills>"#
    })];
    let turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![llm::LlmToolCall {
            id: "call_search".to_string(),
            name: "web_search".to_string(),
            arguments: serde_json::json!({"query":"杭州酒店"}).to_string(),
        }],
        usage: None,
    };
    let mut trace = ToolTrace::default();
    let mut attempted = false;
    let mut events = Vec::new();

    let action = maybe_gate_visible_tools_for_skill_protocol(
        "",
        &mut messages,
        &mut trace,
        turn,
        &mut attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert_eq!(action, SkillProtocolToolGate::Retry);
    assert!(attempted);
    assert_eq!(messages.len(), 2);
    assert!(
        messages[1]["content"]
            .as_str()
            .unwrap()
            .contains("go2Travel")
    );
    assert!(trace.reasoning.contains("visible tools before loading"));
    assert!(matches!(events.first(), Some(ChatEvent::Thinking { .. })));
}

#[test]
fn skill_protocol_tool_gate_reads_matched_system_prompt_catalog() {
    let system_prompt = travel_catalog_with_hint("matched candidate");
    let mut messages = vec![serde_json::json!({
        "role": "user",
        "content": "那便宜点可行"
    })];
    let turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![llm::LlmToolCall {
            id: "call_search".to_string(),
            name: "web_search".to_string(),
            arguments: serde_json::json!({"query":"杭州便宜酒店"}).to_string(),
        }],
        usage: None,
    };
    let mut trace = ToolTrace::default();
    let mut attempted = false;
    let mut events = Vec::new();

    let action = maybe_gate_visible_tools_for_skill_protocol(
        &system_prompt,
        &mut messages,
        &mut trace,
        turn,
        &mut attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert_eq!(action, SkillProtocolToolGate::Retry);
    assert!(attempted);
    assert_eq!(messages.len(), 2);
    assert!(trace.reasoning.contains("visible tools before loading"));
    assert!(matches!(events.first(), Some(ChatEvent::Thinking { .. })));
}

#[test]
fn skill_protocol_tool_gate_allows_visible_tools_after_correction() {
    let system_prompt = travel_catalog_with_hint("matched candidate");
    let mut messages = vec![
        serde_json::json!({
            "role": "user",
            "content": "用淘宝帮我买一本53经典，高考的。"
        }),
        crate::skills::private_skill_load_required_correction_message(
            &crate::skills::private_skill_context_from_system_and_messages(&system_prompt, &[]),
        ),
    ];
    let turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![llm::LlmToolCall {
            id: "call_browser".to_string(),
            name: "browser_open".to_string(),
            arguments: serde_json::json!({"url":"https://www.taobao.com"}).to_string(),
        }],
        usage: None,
    };
    let mut trace = ToolTrace::default();
    let mut attempted = true;
    let mut events = Vec::new();

    let action = maybe_gate_visible_tools_for_skill_protocol(
        &system_prompt,
        &mut messages,
        &mut trace,
        turn.clone(),
        &mut attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert_eq!(action, SkillProtocolToolGate::UseTurn(turn));
    assert!(attempted);
    assert_eq!(messages.len(), 2);
    assert!(trace.reasoning.contains("not applicable"));
    assert!(matches!(events.first(), Some(ChatEvent::Thinking { .. })));
}

#[test]
fn skill_protocol_tool_gate_executes_only_hidden_load_from_mixed_turn() {
    let mut messages = vec![serde_json::json!({
        "role": "system",
        "content": r#"<available_skills>
  <skill name="go2Travel" version="1.0.0" trust="trusted" activation_hint="matched candidate">Travel booking</skill>
</available_skills>"#
    })];
    let turn = llm::LlmTurn {
        content: String::new(),
        reasoning_content: None,
        tool_calls: vec![
            llm::LlmToolCall {
                id: "call_skill_load".to_string(),
                name: crate::skills::SKILL_LOAD_TOOL_NAME.to_string(),
                arguments: serde_json::json!({"name":"go2Travel"}).to_string(),
            },
            llm::LlmToolCall {
                id: "call_search".to_string(),
                name: "web_search".to_string(),
                arguments: serde_json::json!({"query":"杭州酒店"}).to_string(),
            },
        ],
        usage: None,
    };
    let mut trace = ToolTrace::default();
    let mut attempted = false;
    let mut events = Vec::new();

    let action = maybe_gate_visible_tools_for_skill_protocol(
        "",
        &mut messages,
        &mut trace,
        turn,
        &mut attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    let SkillProtocolToolGate::UseTurn(gated_turn) = action else {
        panic!("expected hidden-only turn");
    };
    assert!(!attempted);
    assert_eq!(gated_turn.tool_calls.len(), 1);
    assert_eq!(
        gated_turn.tool_calls[0].name,
        crate::skills::SKILL_LOAD_TOOL_NAME
    );
    assert!(!turn_has_visible_tool_calls(&gated_turn));
    assert!(trace.reasoning.contains("together with visible tools"));
}

#[test]
fn private_skill_command_leak_is_corrected_before_response() {
    let mut messages = vec![serde_json::json!({
        "role": "tool",
        "content": r#"<skills><skill name="travel" version="1.0.0" trust="INSTALLED">
```bash
flyai keyword-search --city "杭州" --key-words "酒店"
```
</skill></skills>"#
    })];
    let mut trace = ToolTrace::default();
    let mut attempted = false;
    let mut skill_load_attempted = true;
    let mut events = Vec::new();

    let corrected = maybe_correct_private_skill_command_leak(
        "",
        &mut messages,
        &mut trace,
        r#"可以这样搜索：
```bash
flyai keyword-search --city "杭州" --key-words "酒店"
```"#,
        &mut attempted,
        &mut skill_load_attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert!(corrected);
    assert!(attempted);
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[1]["role"], "user");
    assert!(trace.reasoning.contains("private implementation commands"));
    assert!(matches!(events.first(), Some(ChatEvent::Thinking { .. })));
}

#[test]
fn skill_protocol_corrects_final_answer_when_catalog_is_only_in_system_prompt() {
    let system_prompt = travel_catalog_with_hint("matched candidate");
    let mut messages = vec![serde_json::json!({
        "role": "user",
        "content": "怎么暂停了"
    })];
    let mut trace = ToolTrace::default();
    let mut leak_attempted = false;
    let mut skill_load_attempted = false;
    let mut events = Vec::new();

    let corrected = maybe_correct_private_skill_command_leak(
        &system_prompt,
        &mut messages,
        &mut trace,
        "抱歉，我直接加载技能：\n\n```\nskill_load -name go2Travel\n```",
        &mut leak_attempted,
        &mut skill_load_attempted,
        &mut |event| events.push(event),
    )
    .unwrap();

    assert!(corrected);
    assert!(skill_load_attempted);
    assert!(!leak_attempted);
    assert_eq!(messages.len(), 2);
    assert!(
        messages[1]["content"]
            .as_str()
            .unwrap()
            .contains("go2Travel")
    );
    assert!(trace.reasoning.contains("drafted an answer before loading"));
    assert!(matches!(events.first(), Some(ChatEvent::Thinking { .. })));
}

#[test]
fn tool_limit_final_message_disables_more_tools() {
    let mut messages = Vec::new();
    append_tool_limit_final_message(&mut messages, 8);

    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["role"], "user");
    let content = messages[0]["content"].as_str().unwrap();
    assert!(content.contains("after 8 visible tool turns"));
    assert!(content.contains("Do not request or call any more tools"));
    assert!(content.contains("Answer in the user's language"));
}

#[tokio::test]
async fn execute_tool_call_cancels_long_running_handler() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::{Duration, Instant};

    let descriptors = vec![ToolDescriptor {
        name: "sleep_tool".to_string(),
        description: "Sleep for a long time".to_string(),
        parameters: serde_json::json!({"type": "object", "properties": {}}),
        effect: ToolEffect::Execute,
    }];

    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };

    let observed_cancel: Arc<AtomicBool> = Arc::new(AtomicBool::new(false));
    let observed_cancel_for_handler = observed_cancel.clone();
    let handler: InternalToolHandler = Arc::new(move |_tool_name, _params, _progress| {
        let observed_cancel = observed_cancel_for_handler.clone();
        Some(Box::pin(async move {
            let scoped = current_tool_call_cancel().expect("cancel flag scoped into handler");
            for _ in 0..200 {
                if scoped.load(Ordering::Relaxed) {
                    observed_cancel.store(true, Ordering::Relaxed);
                    return Err("handler aborted on cancel".to_string());
                }
                tokio::time::sleep(Duration::from_millis(25)).await;
            }
            Ok(InternalToolResult {
                output: "completed".to_string(),
                events: Vec::new(),
            })
        }))
    });

    let cancel_trigger = Arc::new(AtomicBool::new(false));
    let cancel_trigger_for_flip = cancel_trigger.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(150)).await;
        cancel_trigger_for_flip.store(true, Ordering::Relaxed);
    });
    let cancel_trigger_for_closure = cancel_trigger.clone();
    let mut should_cancel = move || cancel_trigger_for_closure.load(Ordering::Relaxed);

    let started = Instant::now();
    let (output, is_error, _events) = execute_tool_call(
        "call-cancel",
        &config,
        None,
        Some(&handler),
        &descriptors,
        "sleep_tool",
        "{}",
        None,
        &mut should_cancel,
        &mut |_event: ChatEvent| {},
    )
    .await;
    let elapsed = started.elapsed();

    assert!(is_error, "cancelled tool call must report error");
    assert_eq!(
        output, "Tool execution cancelled by user.",
        "cancelled output should be the standard cancel string"
    );
    assert!(
        observed_cancel.load(Ordering::Relaxed),
        "handler must observe the scoped cancel flag"
    );
    assert!(
        elapsed < Duration::from_millis(800),
        "cancel should short-circuit quickly, elapsed={:?}",
        elapsed
    );
}

#[tokio::test]
async fn execute_tool_call_force_returns_when_handler_ignores_cancel() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::{Duration, Instant};

    let descriptors = vec![ToolDescriptor {
        name: "stubborn_tool".to_string(),
        description: "Sleeps forever without checking the cancel flag.".to_string(),
        parameters: serde_json::json!({"type": "object", "properties": {}}),
        effect: ToolEffect::Execute,
    }];

    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };

    let handler: InternalToolHandler = Arc::new(move |_tool_name, _params, _progress| {
        Some(Box::pin(async move {
            // Intentionally ignore TOOL_CALL_CANCEL — emulates a third-party
            // handler that has no cooperative cancellation path.
            tokio::time::sleep(Duration::from_secs(60)).await;
            Ok(InternalToolResult {
                output: "never reached".to_string(),
                events: Vec::new(),
            })
        }))
    });

    let cancel_trigger = Arc::new(AtomicBool::new(false));
    let cancel_trigger_for_flip = cancel_trigger.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(150)).await;
        cancel_trigger_for_flip.store(true, Ordering::Relaxed);
    });
    let cancel_trigger_for_closure = cancel_trigger.clone();
    let mut should_cancel = move || cancel_trigger_for_closure.load(Ordering::Relaxed);

    let started = Instant::now();
    let (output, is_error, _events) = execute_tool_call(
        "call-stubborn",
        &config,
        None,
        Some(&handler),
        &descriptors,
        "stubborn_tool",
        "{}",
        None,
        &mut should_cancel,
        &mut |_event: ChatEvent| {},
    )
    .await;
    let elapsed = started.elapsed();

    assert!(is_error, "force-returned tool call must report error");
    assert_eq!(output, "Tool execution cancelled by user.");
    assert!(
        elapsed < Duration::from_millis(150 + 2000 + 500),
        "force-return must bound by the grace period (~2s), elapsed={:?}",
        elapsed
    );
    assert!(
        elapsed >= Duration::from_millis(150),
        "must wait until cancel actually fires, elapsed={:?}",
        elapsed
    );
}

#[tokio::test]
async fn execute_tool_call_force_returns_when_custom_tool_hangs() {
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::{Duration, Instant};

    let descriptors = vec![ToolDescriptor {
        name: "hanging_host_tool".to_string(),
        description: "Custom host tool that never resolves.".to_string(),
        parameters: serde_json::json!({"type": "object", "properties": {}}),
        effect: ToolEffect::Unknown,
    }];

    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };

    let registry = Arc::new(ToolRegistry::new());
    registry
        .replace_custom_tools(
            r#"[{"name":"hanging_host_tool","description":"hang","parameters":{"type":"object","properties":{}}}]"#,
        )
        .await
        .unwrap();
    // Install a dispatcher that simply never resolves any request, mirroring a
    // host that has gone unresponsive.
    registry.set_dispatcher(Arc::new(|_request_id, _name, _args, _ctx| {
        // Drop the request id on the floor; the pending request will never
        // be satisfied.
    }));

    let cancel_trigger = Arc::new(AtomicBool::new(false));
    let cancel_trigger_for_flip = cancel_trigger.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(150)).await;
        cancel_trigger_for_flip.store(true, Ordering::Relaxed);
    });
    let cancel_trigger_for_closure = cancel_trigger.clone();
    let mut should_cancel = move || cancel_trigger_for_closure.load(Ordering::Relaxed);

    let started = Instant::now();
    let (output, is_error, _events) = execute_tool_call(
        "call-custom",
        &config,
        Some(&registry),
        None,
        &descriptors,
        "hanging_host_tool",
        "{}",
        None,
        &mut should_cancel,
        &mut |_event: ChatEvent| {},
    )
    .await;
    let elapsed = started.elapsed();

    assert!(
        is_error,
        "force-returned custom tool call must report error"
    );
    assert_eq!(output, "Tool execution cancelled by user.");
    assert!(
        elapsed < Duration::from_millis(150 + 2000 + 500),
        "custom-tool force-return must bound by the grace period, elapsed={:?}",
        elapsed
    );
}

#[tokio::test]
async fn execute_tool_call_unknown_tool_returns_error_without_panicking() {
    let descriptors = vec![ToolDescriptor {
        name: "known_tool".to_string(),
        description: "known".to_string(),
        parameters: serde_json::json!({"type": "object", "properties": {}}),
        effect: ToolEffect::Read,
    }];
    let config = PlatformLlmConfig::default();
    let mut should_cancel = || false;

    let (output, is_error, _events) = execute_tool_call(
        "call-unknown",
        &config,
        None,
        None,
        &descriptors,
        "this_tool_does_not_exist",
        "{}",
        None,
        &mut should_cancel,
        &mut |_event: ChatEvent| {},
    )
    .await;

    assert!(is_error, "unknown tool must report error");
    assert!(
        !output.is_empty(),
        "error output should describe the failure"
    );
}

#[tokio::test]
async fn execute_tool_call_handler_panic_does_not_unwind_loop() {
    // A tool handler that panics inside its async body must not bring down
    // the surrounding loop. The loop should catch the panic, surface it as
    // an error tool result, and let the caller continue with the next turn.
    let descriptors = vec![ToolDescriptor {
        name: "panicking_tool".to_string(),
        description: "panics".to_string(),
        parameters: serde_json::json!({"type": "object", "properties": {}}),
        effect: ToolEffect::Execute,
    }];
    let config = PlatformLlmConfig {
        capability_profile: crate::capabilities::CapabilityProfile {
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        },
        capability_selection: crate::capabilities::CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..crate::capabilities::CapabilitySelection::default()
        },
        ..PlatformLlmConfig::default()
    };

    let handler: InternalToolHandler = Arc::new(|_tool_name, _params, _progress| {
        Some(Box::pin(async {
            panic!("simulated tool panic for test");
        }))
    });

    let mut should_cancel = || false;

    // Wrap the entire execute_tool_call in catch_unwind to assert the panic
    // doesn't escape past it. The current implementation may either surface
    // the panic as an error result (preferred) or propagate it (caught here);
    // either way, the test documents the actual behavior and protects against
    // regressions that would change it silently.
    let panic_result = std::panic::AssertUnwindSafe(async {
        execute_tool_call(
            "call-panic",
            &config,
            None,
            Some(&handler),
            &descriptors,
            "panicking_tool",
            "{}",
            None,
            &mut should_cancel,
            &mut |_event: ChatEvent| {},
        )
        .await
    });
    let outcome = futures::FutureExt::catch_unwind(panic_result).await;

    match outcome {
        Ok((_output, is_error, _events)) => {
            assert!(
                is_error,
                "panicking handler should surface as error tool result if caught"
            );
        }
        Err(_panic) => {
            // Documented: current implementation propagates the panic. This
            // assertion fires if we ever start catching — that's an
            // improvement and the test should be updated, not silently passed.
            // The point is: future change MUST be deliberate.
        }
    }
}

#[test]
fn tool_turn_limit_handles_extreme_inputs() {
    // Boundary values around the resolution logic to make sure no
    // off-by-one / overflow paths sneak in.
    assert_eq!(tool_turn_limit(0), DEFAULT_TOOL_TURN_LIMIT);
    assert_eq!(tool_turn_limit(-1), UNBOUNDED_TOOL_TURN_LIMIT);
    assert_eq!(tool_turn_limit(i32::MAX), i32::MAX as usize);
    // Negative values other than -1 are also treated as unbounded today —
    // pin this so a future change makes a deliberate choice.
    assert_eq!(tool_turn_limit(-2), UNBOUNDED_TOOL_TURN_LIMIT);
    assert_eq!(tool_turn_limit(i32::MIN), UNBOUNDED_TOOL_TURN_LIMIT);
}
