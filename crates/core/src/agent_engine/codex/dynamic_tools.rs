use crate::agent_engine::AgentEngineTurnRequest;
use crate::types::ChatEvent;

use super::protocol::{dynamic_tool_call_params, dynamic_tool_call_response};

pub(super) async fn handle_server_tool_call<F, C>(
    request_id: serde_json::Value,
    message: &serde_json::Value,
    request: &AgentEngineTurnRequest,
    tools: Option<&std::sync::Arc<crate::tool_registry::ToolRegistry>>,
    internal_tool_handler: Option<&crate::tool_loop::InternalToolHandler>,
    tool_descriptors: &[crate::tool_registry::ToolDescriptor],
    is_cancelled: &mut C,
    emit: &mut F,
    events: &mut Vec<ChatEvent>,
) -> Option<String>
where
    F: FnMut(ChatEvent),
    C: FnMut() -> bool,
{
    let params = match dynamic_tool_call_params(message) {
        Ok(Some(params)) => params,
        Ok(None) => return None,
        Err(error) => {
            return Some(dynamic_tool_call_response(request_id, false, &error));
        }
    };
    if params
        .namespace
        .as_deref()
        .is_some_and(|namespace| namespace != "napaxi")
    {
        return Some(dynamic_tool_call_response(
            request_id,
            false,
            &format!(
                "unsupported dynamic tool namespace: {}",
                params.namespace.unwrap_or_default()
            ),
        ));
    }
    if crate::skills::is_hidden_skill_tool(&params.tool)
        || !tool_descriptors
            .iter()
            .any(|descriptor| descriptor.name == params.tool)
    {
        return Some(dynamic_tool_call_response(
            request_id,
            false,
            &format!(
                "dynamic tool is not available in this turn: {}",
                params.tool
            ),
        ));
    }
    let config = match serde_json::from_str::<crate::types::PlatformLlmConfig>(&request.config_json)
    {
        Ok(config) => config,
        Err(error) => {
            return Some(dynamic_tool_call_response(
                request_id,
                false,
                &format!("Napaxi tool configuration parse failed: {error}"),
            ));
        }
    };
    let arguments = match serde_json::to_string(&params.arguments) {
        Ok(arguments) => arguments,
        Err(error) => {
            return Some(dynamic_tool_call_response(
                request_id,
                false,
                &format!("Napaxi tool arguments serialization failed: {error}"),
            ));
        }
    };
    let context = crate::tool_registry::ToolExecutionContext {
        files_dir: request.files_dir.clone(),
        workspace_files_dir: request.workspace_files_dir.clone(),
        agent_id: request.agent_id.clone(),
        session_key_json: Some(request.session_key_json.clone()),
    };
    let redacted_arguments = crate::tool_registry::redact_tool_arguments_json(&arguments);
    let call_event = ChatEvent::ToolCall {
        call_id: params.call_id.clone(),
        name: params.tool.clone(),
        arguments: redacted_arguments,
    };
    emit(call_event.clone());
    events.push(call_event);

    let mut tool_events = Vec::new();
    let (output, is_error, emitted_events, _effect) =
        crate::tool_loop::execute_single_tool_call_for_broker(
            &params.call_id,
            &config,
            tools,
            internal_tool_handler,
            tool_descriptors,
            &params.tool,
            &arguments,
            Some(&context),
            is_cancelled,
            &mut |event| tool_events.push(event),
        )
        .await;
    tool_events.extend(emitted_events);
    for event in tool_events {
        emit(event.clone());
        events.push(event);
    }
    let output = crate::tool_registry::sanitize_tool_output(&output);
    let result_event = ChatEvent::ToolResult {
        call_id: params.call_id,
        name: params.tool,
        output: output.clone(),
        is_error,
    };
    emit(result_event.clone());
    events.push(result_event);
    Some(dynamic_tool_call_response(request_id, !is_error, &output))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn request() -> AgentEngineTurnRequest {
        request_with_config(crate::types::PlatformLlmConfig::default())
    }

    fn request_with_config(config: crate::types::PlatformLlmConfig) -> AgentEngineTurnRequest {
        AgentEngineTurnRequest {
            engine_id: crate::agent_engine::CODEX_ENGINE_ID.to_string(),
            engine_profile_id: String::new(),
            engine_config: json!({}),
            run_id: "run-1".to_string(),
            files_dir: "/files".to_string(),
            workspace_files_dir: "/workspace".to_string(),
            account_id: "acct".to_string(),
            agent_id: "agent".to_string(),
            session_key_json: r#"{"thread_id":"thread"}"#.to_string(),
            message: "hello".to_string(),
            attachments_json: "[]".to_string(),
            config_json: serde_json::to_string(&config).unwrap(),
        }
    }

    #[tokio::test]
    async fn rejects_unavailable_dynamic_tool_without_emitting_events() {
        let message = json!({
            "jsonrpc": "2.0",
            "id": "rpc-1",
            "method": "item/tool/call",
            "params": {
                "arguments": {"url": "https://example.com"},
                "callId": "call-1",
                "namespace": "napaxi",
                "tool": "open_url",
                "threadId": "thread-1",
                "turnId": "turn-1"
            }
        });
        let mut emitted = Vec::new();
        let mut events = Vec::new();
        let mut cancelled = || false;

        let response = handle_server_tool_call(
            json!("rpc-1"),
            &message,
            &request(),
            None,
            None,
            &[],
            &mut cancelled,
            &mut |event| emitted.push(event),
            &mut events,
        )
        .await
        .unwrap();
        let response: serde_json::Value = serde_json::from_str(&response).unwrap();

        assert_eq!(response["id"], "rpc-1");
        assert_eq!(response["result"]["success"], false);
        assert!(
            response["result"]["contentItems"][0]["text"]
                .as_str()
                .unwrap()
                .contains("dynamic tool is not available")
        );
        assert!(emitted.is_empty());
        assert!(events.is_empty());
    }

    #[tokio::test]
    async fn executes_available_custom_tool_through_napaxi_registry() {
        let message = json!({
            "jsonrpc": "2.0",
            "id": "rpc-2",
            "method": "item/tool/call",
            "params": {
                "arguments": {"value": "hello from codex"},
                "callId": "call-2",
                "namespace": "napaxi",
                "tool": "custom_echo",
                "threadId": "thread-1",
                "turnId": "turn-1"
            }
        });
        let descriptor = crate::tool_registry::ToolDescriptor {
            name: "custom_echo".to_string(),
            description: "Echo a custom host tool value".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {"value": {"type": "string"}},
                "required": ["value"]
            }),
            effect: crate::tool_registry::ToolEffect::External,
        };
        let registry = std::sync::Arc::new(crate::tool_registry::ToolRegistry::new());
        registry
            .replace_custom_tools(&serde_json::to_string(&vec![descriptor.clone()]).unwrap())
            .await
            .unwrap();
        registry.set_dispatcher(std::sync::Arc::new(|request_id, name, params, context| {
            assert_eq!(name, "custom_echo");
            assert!(params.contains("hello from codex"));
            assert_eq!(
                context.map(|context| context.workspace_files_dir.as_str()),
                Some("/workspace")
            );
            crate::tool_registry::resolve_tool_execution(
                request_id,
                r#"{"opened":true}"#.to_string(),
                false,
            );
        }));
        let mut emitted = Vec::new();
        let mut events = Vec::new();
        let mut cancelled = || false;

        let response = handle_server_tool_call(
            json!("rpc-2"),
            &message,
            &{
                let mut config = crate::types::PlatformLlmConfig::default();
                config.capability_profile = crate::capabilities::CapabilityProfile {
                    platform: Some("android".to_string()),
                    supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
                    ..crate::capabilities::CapabilityProfile::default()
                };
                config.capability_selection = crate::capabilities::CapabilitySelection {
                    enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
                    ..crate::capabilities::CapabilitySelection::default()
                };
                request_with_config(config)
            },
            Some(&registry),
            None,
            &[descriptor],
            &mut cancelled,
            &mut |event| emitted.push(event),
            &mut events,
        )
        .await
        .unwrap();
        let response: serde_json::Value = serde_json::from_str(&response).unwrap();

        assert_eq!(response["id"], "rpc-2");
        if response["result"]["success"] != true {
            panic!("unexpected response: {response}");
        }
        assert!(
            response["result"]["contentItems"][0]["text"]
                .as_str()
                .unwrap()
                .contains("opened")
        );
        assert!(matches!(
            emitted.first(),
            Some(ChatEvent::ToolCall { name, .. }) if name == "custom_echo"
        ));
        assert!(matches!(
            emitted.last(),
            Some(ChatEvent::ToolResult { name, is_error, .. }) if name == "custom_echo" && !is_error
        ));
        assert_eq!(events.len(), emitted.len());
    }

    #[tokio::test]
    async fn executes_available_platform_tool_through_napaxi_internal_handler() {
        let message = json!({
            "jsonrpc": "2.0",
            "id": "rpc-platform",
            "method": "item/tool/call",
            "params": {
                "arguments": {"url": "https://example.com"},
                "callId": "call-platform",
                "namespace": "napaxi",
                "tool": "open_url",
                "threadId": "thread-1",
                "turnId": "turn-1"
            }
        });
        let registry = std::sync::Arc::new(crate::tool_registry::ToolRegistry::new());
        registry.set_dispatcher(std::sync::Arc::new(|request_id, name, params, context| {
            assert_eq!(name, "open_url");
            assert!(params.contains("https://example.com"));
            assert_eq!(
                context.map(|context| context.workspace_files_dir.as_str()),
                Some("/workspace")
            );
            crate::tool_registry::resolve_tool_execution(
                request_id,
                r#"{"success":true,"opened":true}"#.to_string(),
                false,
            );
        }));
        let mut config = crate::types::PlatformLlmConfig::default();
        config.capability_profile = crate::capabilities::CapabilityProfile {
            platform: Some("android".to_string()),
            supported_capabilities: vec!["napaxi.platform_tool.*".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        };
        config.capability_selection = crate::capabilities::CapabilitySelection::default();
        let builtin_context = crate::builtin_tools::BuiltinToolContext {
            files_dir: "/files".to_string(),
            workspace_files_dir: "/workspace".to_string(),
            agent_id: "agent".to_string(),
            platform: "android".to_string(),
            native_library_dir: None,
            account_id: "acct".to_string(),
            approval_bridge: registry.request_bridge(),
            llm_config: config.clone(),
            current_thread_id: Some("thread".to_string()),
        };
        let (descriptors, internal_handler) =
            crate::builtin_tools::builtin_tools_and_handler(builtin_context, Vec::new(), None);
        assert!(
            descriptors
                .iter()
                .any(|descriptor| descriptor.name == "open_url")
        );
        let mut emitted = Vec::new();
        let mut events = Vec::new();
        let mut cancelled = || false;

        let response = handle_server_tool_call(
            json!("rpc-platform"),
            &message,
            &request_with_config(config),
            None,
            internal_handler.as_ref(),
            &descriptors,
            &mut cancelled,
            &mut |event| emitted.push(event),
            &mut events,
        )
        .await
        .unwrap();
        let response: serde_json::Value = serde_json::from_str(&response).unwrap();

        assert_eq!(response["id"], "rpc-platform");
        assert_eq!(response["result"]["success"], true);
        assert!(matches!(
            emitted.first(),
            Some(ChatEvent::ToolCall { name, .. }) if name == "open_url"
        ));
        assert!(matches!(
            emitted.last(),
            Some(ChatEvent::ToolResult { name, is_error, .. }) if name == "open_url" && !is_error
        ));
    }

    #[tokio::test]
    async fn executes_available_device_info_platform_tool_by_descriptor_name() {
        let message = json!({
            "id": "rpc-device-info",
            "method": "item/tool/call",
            "params": {
                "arguments": {},
                "callId": "call-device-info",
                "namespace": "napaxi",
                "tool": "get_device_info",
                "threadId": "thread-1",
                "turnId": "turn-1"
            }
        });
        let registry = std::sync::Arc::new(crate::tool_registry::ToolRegistry::new());
        registry.set_dispatcher(std::sync::Arc::new(|request_id, name, params, context| {
            assert_eq!(name, "get_device_info");
            assert_eq!(params, "{}");
            assert_eq!(
                context.map(|context| context.workspace_files_dir.as_str()),
                Some("/workspace")
            );
            crate::tool_registry::resolve_tool_execution(
                request_id,
                r#"{"success":true,"model":"test-device"}"#.to_string(),
                false,
            );
        }));
        let mut config = crate::types::PlatformLlmConfig::default();
        config.capability_profile = crate::capabilities::CapabilityProfile {
            platform: Some("android".to_string()),
            supported_capabilities: vec!["napaxi.platform_tool.*".to_string()],
            ..crate::capabilities::CapabilityProfile::default()
        };
        let builtin_context = crate::builtin_tools::BuiltinToolContext {
            files_dir: "/files".to_string(),
            workspace_files_dir: "/workspace".to_string(),
            agent_id: "agent".to_string(),
            platform: "android".to_string(),
            native_library_dir: None,
            account_id: "acct".to_string(),
            approval_bridge: registry.request_bridge(),
            llm_config: config.clone(),
            current_thread_id: Some("thread".to_string()),
        };
        let (descriptors, internal_handler) =
            crate::builtin_tools::builtin_tools_and_handler(builtin_context, Vec::new(), None);
        assert!(
            descriptors
                .iter()
                .any(|descriptor| descriptor.name == "get_device_info")
        );
        let mut emitted = Vec::new();
        let mut events = Vec::new();
        let mut cancelled = || false;

        let response = handle_server_tool_call(
            json!("rpc-device-info"),
            &message,
            &request_with_config(config),
            None,
            internal_handler.as_ref(),
            &descriptors,
            &mut cancelled,
            &mut |event| emitted.push(event),
            &mut events,
        )
        .await
        .unwrap();
        let response: serde_json::Value = serde_json::from_str(&response).unwrap();

        assert_eq!(response["id"], "rpc-device-info");
        assert_eq!(response["result"]["success"], true);
        assert!(matches!(
            emitted.first(),
            Some(ChatEvent::ToolCall { name, .. }) if name == "get_device_info"
        ));
        assert!(matches!(
            emitted.last(),
            Some(ChatEvent::ToolResult { name, is_error, .. }) if name == "get_device_info" && !is_error
        ));
    }

    #[tokio::test]
    async fn rejects_non_napaxi_dynamic_tool_namespace() {
        let message = json!({
            "jsonrpc": "2.0",
            "id": 7,
            "method": "item/tool/call",
            "params": {
                "arguments": {},
                "callId": "call-1",
                "namespace": "browser",
                "tool": "open",
                "threadId": "thread-1",
                "turnId": "turn-1"
            }
        });
        let mut emitted = Vec::new();
        let mut events = Vec::new();
        let mut cancelled = || false;

        let response = handle_server_tool_call(
            json!(7),
            &message,
            &request(),
            None,
            None,
            &[],
            &mut cancelled,
            &mut |event| emitted.push(event),
            &mut events,
        )
        .await
        .unwrap();
        let response: serde_json::Value = serde_json::from_str(&response).unwrap();

        assert_eq!(response["id"], 7);
        assert_eq!(response["result"]["success"], false);
        assert!(
            response["result"]["contentItems"][0]["text"]
                .as_str()
                .unwrap()
                .contains("unsupported dynamic tool namespace")
        );
        assert!(emitted.is_empty());
        assert!(events.is_empty());
    }
}
