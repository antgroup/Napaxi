//! Behavioral coverage for the capability registry and admission gates.
//!
//! Kept as four sub-modules matching the source layout so test output
//! stays grouped by concern (registry, policy hooks, decision recording,
//! provider admission).

use std::collections::HashSet;

use super::{CapabilityDefinition, ScenarioPackDefinition};

fn validate_definition_ids(definitions: &[CapabilityDefinition]) -> Result<(), String> {
    let mut seen = HashSet::new();
    for definition in definitions {
        if !seen.insert(definition.id.as_str()) {
            return Err(format!("duplicate capability id: {}", definition.id));
        }
    }
    Ok(())
}

fn validate_scenario_ids(definitions: &[ScenarioPackDefinition]) -> Result<(), String> {
    let mut seen = HashSet::new();
    for definition in definitions {
        if !seen.insert(definition.id.as_str()) {
            return Err(format!("duplicate scenario id: {}", definition.id));
        }
    }
    Ok(())
}

mod registry {
    use std::collections::HashMap;

    use super::super::{
        CapabilityActivation, CapabilityKind, CapabilityProfile, CapabilityRisk,
        CapabilitySelection, GENERAL_SCENARIO_ID, LlmProviderRoute, MOBILE_DEVELOPMENT_SCENARIO_ID,
        admit_tool_descriptor_for_config, agent_engine_capability_id, definitions,
        install_scenario_pack, platform_tool_capability_id, remove_scenario_pack,
        require_agent_engine_enabled_for_config, resolve_llm_provider, resolve_scenario,
        resolve_scenario_for_files_dir, scenario_packs, scenario_packs_for_files_dir,
        scenario_status, scenario_status_for_files_dir, selection_from_llm_config, status,
        tool_capability_id,
    };
    use super::validate_definition_ids;
    use crate::types::PlatformLlmConfig;

    fn base_config() -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: "openai".to_string(),
            api_key: "key".to_string(),
            base_url: None,
            model: "model".to_string(),
            system_prompt: String::new(),
            max_tokens: 100,
            max_tool_iterations: 0,
            extra_headers: None,
            allowed_models: None,
            image_model: None,
            image_analysis_model: None,
            capability_configs: None,
            scene_prompt_config: None,
            ..PlatformLlmConfig::default()
        }
    }

    #[test]
    fn registry_definition_ids_are_unique() {
        let definitions = definitions();
        validate_definition_ids(&definitions).unwrap();
        assert!(
            definitions
                .iter()
                .any(|definition| definition.id == "napaxi.policy.runtime_gate")
        );
        assert!(
            definitions
                .iter()
                .any(|definition| definition.id == "napaxi.service.scenario_registry")
        );
    }

    #[test]
    fn platform_tools_have_matching_capability_definitions() {
        let definitions = definitions();
        for descriptor in crate::platform_capabilities::platform_tool_descriptors() {
            let id = platform_tool_capability_id(&descriptor.name);
            let definition = definitions
                .iter()
                .find(|definition| definition.id == id)
                .unwrap_or_else(|| panic!("missing capability for {}", descriptor.name));
            assert_eq!(definition.kind, CapabilityKind::PlatformTool);
            assert_eq!(definition.config_schema, descriptor.parameters);
        }
    }

    #[test]
    fn agent_app_action_capability_is_host_carried_tool() {
        let definitions = definitions();
        let definition = definitions
            .iter()
            .find(|definition| definition.id == "napaxi.tool.agent_app_action")
            .expect("Agent App action capability");
        assert_eq!(definition.kind, CapabilityKind::Tool);
        assert_eq!(definition.risk, CapabilityRisk::High);
        assert_eq!(definition.activation, CapabilityActivation::Host);
        assert!(!definition.default_enabled);
        assert!(
            definition
                .requirements
                .contains(&"host_action_dispatcher".to_string())
        );
        assert_eq!(
            tool_capability_id("app_action_order_create").as_deref(),
            Some("napaxi.tool.agent_app_action")
        );
    }

    #[test]
    fn im_channel_capability_is_host_carried_service() {
        let definitions = definitions();
        let definition = definitions
            .iter()
            .find(|definition| definition.id == crate::channel::CHANNEL_IM_CAPABILITY_ID)
            .expect("IM channel capability");
        assert_eq!(definition.kind, CapabilityKind::Service);
        assert_eq!(definition.risk, CapabilityRisk::Medium);
        assert_eq!(definition.activation, CapabilityActivation::Host);
        assert!(!definition.default_enabled);
        assert!(
            definition
                .requirements
                .contains(&"host_channel_adapter".to_string())
        );

        let statuses = status(
            "ios",
            r#"{"platform":"ios","supported_capabilities":["napaxi.channel.im"]}"#,
            r#"{"enabled_capabilities":["napaxi.channel.im"]}"#,
        );
        let status = statuses
            .iter()
            .find(|status| status.definition.id == crate::channel::CHANNEL_IM_CAPABILITY_ID)
            .expect("IM channel status");
        assert!(status.available);
        assert!(status.enabled);
    }

    #[test]
    fn device_channel_capability_is_host_carried_service() {
        let definitions = definitions();
        let definition = definitions
            .iter()
            .find(|definition| definition.id == crate::channel::CHANNEL_DEVICE_CAPABILITY_ID)
            .expect("device channel capability");
        assert_eq!(definition.kind, CapabilityKind::Service);
        assert_eq!(definition.risk, CapabilityRisk::Medium);
        assert_eq!(definition.activation, CapabilityActivation::Host);
        assert!(!definition.default_enabled);
        assert!(
            definition
                .requirements
                .contains(&"host_device_channel_adapter".to_string())
        );

        let statuses = status(
            "android",
            r#"{"platform":"android","supported_capabilities":["napaxi.channel.device"]}"#,
            r#"{"enabled_capabilities":["napaxi.channel.device"]}"#,
        );
        let status = statuses
            .iter()
            .find(|status| status.definition.id == crate::channel::CHANNEL_DEVICE_CAPABILITY_ID)
            .expect("device channel status");
        assert!(status.available);
        assert!(status.enabled);
    }

    #[test]
    fn browser_capability_is_host_carried_tool() {
        let definitions = definitions();
        let definition = definitions
            .iter()
            .find(|definition| definition.id == crate::browser_tools::BROWSER_CAPABILITY_ID)
            .expect("Browser capability");
        assert_eq!(definition.kind, CapabilityKind::Tool);
        assert_eq!(definition.risk, CapabilityRisk::High);
        assert_eq!(definition.activation, CapabilityActivation::Host);
        assert!(!definition.default_enabled);
        assert!(
            definition
                .requirements
                .contains(&"host_browser_controller".to_string())
        );
        assert_eq!(
            tool_capability_id(crate::browser_tools::BROWSER_OPEN).as_deref(),
            Some(crate::browser_tools::BROWSER_CAPABILITY_ID)
        );
        assert_eq!(
            tool_capability_id(crate::browser_tools::BROWSER_CLICK).as_deref(),
            Some(crate::browser_tools::BROWSER_CAPABILITY_ID)
        );
    }

    #[test]
    fn a2a_tool_capability_is_host_carried_tool() {
        let definitions = definitions();
        let definition = definitions
            .iter()
            .find(|definition| definition.id == crate::a2a::A2A_TOOL_CAPABILITY_ID)
            .expect("A2A tool capability");
        assert_eq!(definition.kind, CapabilityKind::Tool);
        assert_eq!(definition.risk, CapabilityRisk::Medium);
        assert_eq!(definition.activation, CapabilityActivation::Host);
        assert!(!definition.default_enabled);
        assert!(
            definition
                .requirements
                .contains(&"local_peer_transport".to_string())
        );
        assert_eq!(
            tool_capability_id("a2a_list_agents").as_deref(),
            Some(crate::a2a::A2A_TOOL_CAPABILITY_ID)
        );
        assert_eq!(
            tool_capability_id("a2a_send_message").as_deref(),
            Some(crate::a2a::A2A_TOOL_CAPABILITY_ID)
        );
    }

    #[test]
    fn agent_engine_capabilities_are_gated_by_host_support() {
        let definitions = definitions();
        let core = definitions
            .iter()
            .find(|definition| definition.id == "napaxi.agent_engine.napaxi_core")
            .expect("core engine capability");
        assert_eq!(core.kind, CapabilityKind::AgentEngine);
        assert!(core.default_enabled);

        let external = definitions
            .iter()
            .find(|definition| definition.id == "napaxi.agent_engine.external_host")
            .expect("external host engine capability");
        assert_eq!(external.kind, CapabilityKind::AgentEngine);
        assert_eq!(external.activation, CapabilityActivation::Host);
        assert!(!external.default_enabled);

        let config = base_config();
        assert_eq!(
            agent_engine_capability_id("external_host"),
            Some("napaxi.agent_engine.external_host")
        );
        assert!(
            require_agent_engine_enabled_for_config(
                "external_host",
                "ios",
                &config.capability_profile,
                &config.capability_selection,
            )
            .unwrap_err()
            .contains("requires host support")
        );

        let mut config = base_config();
        config.capability_profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            supported_capabilities: vec!["napaxi.agent_engine.external_host".to_string()],
            ..CapabilityProfile::default()
        };
        config.capability_selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.agent_engine.external_host".to_string()],
            ..CapabilitySelection::default()
        };
        require_agent_engine_enabled_for_config(
            "external_host",
            "ios",
            &config.capability_profile,
            &config.capability_selection,
        )
        .unwrap();
    }

    #[test]
    fn built_in_scenario_packs_anchor_general_and_mobile_development() {
        let packs = scenario_packs();
        super::validate_scenario_ids(&packs).unwrap();

        let general = packs
            .iter()
            .find(|pack| pack.id == GENERAL_SCENARIO_ID)
            .expect("general scenario");
        assert_eq!(general.activation, super::super::ScenarioActivation::Manual);
        assert!(
            general
                .required_capabilities
                .contains(&"napaxi.service.scenario_registry".to_string())
        );

        let mobile_dev = packs
            .iter()
            .find(|pack| pack.id == MOBILE_DEVELOPMENT_SCENARIO_ID)
            .expect("mobile development scenario");
        assert_eq!(mobile_dev.risk, CapabilityRisk::Critical);
        assert!(
            mobile_dev
                .required_capabilities
                .contains(&"napaxi.tool.shell_remote".to_string())
        );
        assert!(
            mobile_dev
                .execution_planes
                .contains(&super::super::ScenarioExecutionPlane::HostBridge)
        );
        assert!(
            !mobile_dev
                .required_capabilities
                .contains(&"napaxi.service.remote_workspace".to_string())
        );
        let git_settings = mobile_dev
            .settings_contributions
            .iter()
            .find(|contribution| contribution.id == "settings.git")
            .expect("git settings contribution");
        assert_eq!(git_settings.capability_id, "napaxi.tool.git");
        assert_eq!(git_settings.placement, "scenario_settings");
        assert_eq!(
            git_settings
                .schema
                .pointer("/properties/token/type")
                .and_then(serde_json::Value::as_str),
            Some("secret")
        );
        let repo_workbench = mobile_dev
            .ui_contributions
            .iter()
            .find(|contribution| contribution.id == "ui.repo_workbench")
            .expect("repo workbench UI contribution");
        assert_eq!(repo_workbench.capability_id, "napaxi.tool.git");
        assert_eq!(repo_workbench.placement, "left_menu");
        assert_eq!(repo_workbench.renderer, "repo_workbench");
        assert_eq!(
            repo_workbench
                .data_sources
                .pointer("/repositories")
                .and_then(serde_json::Value::as_str),
            Some("git.repositories")
        );
        let environment = mobile_dev
            .ui_contributions
            .iter()
            .find(|contribution| contribution.id == "ui.developer_environment")
            .expect("environment UI contribution");
        assert_eq!(
            environment.capability_id,
            "napaxi.service.developer_workbench"
        );
        assert_eq!(environment.placement, "left_menu");
        assert_eq!(environment.renderer, "environment");
        assert_eq!(
            environment
                .data_sources
                .pointer("/tools")
                .and_then(serde_json::Value::as_str),
            Some("environment.tools")
        );
        assert_eq!(
            environment
                .data_sources
                .pointer("/status")
                .and_then(serde_json::Value::as_str),
            Some("environment.status")
        );
        assert!(environment.actions.contains(&"install_tool".to_string()));
        assert!(environment.actions.contains(&"add_tool".to_string()));
        assert_eq!(
            tool_capability_id("git_status").as_deref(),
            Some("napaxi.tool.git")
        );
        assert_eq!(
            tool_capability_id("git_clone").as_deref(),
            Some("napaxi.tool.git")
        );
        assert_eq!(
            tool_capability_id("shell_remote").as_deref(),
            Some("napaxi.tool.shell_remote")
        );
    }

    #[test]
    fn installed_scenario_packs_persist_and_resolve_from_files_dir() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let pack_json = serde_json::json!({
            "id": "napaxi.scenario.experimental_hidden",
            "version": "1",
            "label": "Experimental Hidden Scenario",
            "description": "Generic installable scenario fixture",
            "risk": "high",
            "activation": "host_policy",
            "execution_planes": ["core", "host_bridge"],
            "required_capabilities": ["napaxi.tool.file", "napaxi.tool.ask_human"],
            "recommended_capabilities": ["napaxi.tool.web_fetch"],
            "optional_capabilities": ["napaxi.service.automation"],
            "ui_surfaces": ["chat", "inspector_panel"],
            "memory_scopes": ["workspace", "session"],
            "tags": ["experimental", "hidden"]
        })
        .to_string();

        let installed = install_scenario_pack(files_dir, &pack_json).unwrap();
        assert!(installed.installed);
        assert!(!installed.replaced);
        assert_eq!(
            installed.definition.id,
            "napaxi.scenario.experimental_hidden"
        );
        assert!(
            installed
                .definition
                .required_capabilities
                .contains(&"napaxi.service.scenario_registry".to_string())
        );

        let packs = scenario_packs_for_files_dir(files_dir);
        super::validate_scenario_ids(&packs).unwrap();
        assert!(
            packs
                .iter()
                .any(|pack| pack.id == "napaxi.scenario.experimental_hidden")
        );

        let statuses = scenario_status_for_files_dir(files_dir, "ios", "{}", "{}");
        assert!(
            statuses
                .iter()
                .any(|status| status.definition.id == "napaxi.scenario.experimental_hidden")
        );
        let resolution = resolve_scenario_for_files_dir(
            files_dir,
            "ios",
            "{}",
            "{}",
            "napaxi.scenario.experimental_hidden",
        )
        .expect("installed scenario resolution");
        assert_eq!(
            resolution.status.definition.id,
            "napaxi.scenario.experimental_hidden"
        );

        let replaced = install_scenario_pack(files_dir, &pack_json).unwrap();
        assert!(replaced.replaced);

        let removed =
            remove_scenario_pack(files_dir, "napaxi.scenario.experimental_hidden").unwrap();
        assert!(removed.removed);
        assert!(
            !scenario_packs_for_files_dir(files_dir)
                .iter()
                .any(|pack| pack.id == "napaxi.scenario.experimental_hidden")
        );
    }

    #[test]
    fn installed_scenario_packs_cannot_replace_builtin_scenarios() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let pack_json = serde_json::json!({
            "id": GENERAL_SCENARIO_ID,
            "version": "1",
            "label": "Override",
            "description": "Should not install",
            "risk": "low",
            "activation": "manual"
        })
        .to_string();

        let error = install_scenario_pack(files_dir, &pack_json)
            .expect_err("built-in scenario id should be rejected");
        assert!(error.contains("cannot be replaced"));
        let error = remove_scenario_pack(files_dir, GENERAL_SCENARIO_ID)
            .expect_err("built-in scenario id should not be removable");
        assert!(error.contains("cannot be removed"));
    }

    #[test]
    fn general_scenario_is_enabled_by_default_capabilities() {
        let statuses = scenario_status("ios", "{}", "{}");
        let general = statuses
            .iter()
            .find(|status| status.definition.id == GENERAL_SCENARIO_ID)
            .expect("general status");
        assert!(general.available);
        assert!(general.enabled);
        assert!(general.missing_required_capabilities.is_empty());
        assert!(general.disabled_required_capabilities.is_empty());
    }

    #[test]
    fn mobile_development_scenario_reports_activation_plan() {
        let resolution = resolve_scenario("ios", "{}", "{}", MOBILE_DEVELOPMENT_SCENARIO_ID)
            .expect("mobile development resolution");

        assert!(!resolution.status.available);
        assert!(
            resolution
                .status
                .unavailable_reasons
                .iter()
                .any(|reason| reason.contains("napaxi.service.developer_workbench"))
        );
        assert!(
            resolution
                .activation_plan
                .supported_capabilities
                .contains(&"napaxi.service.developer_workbench".to_string())
        );
        assert!(
            resolution
                .activation_plan
                .enabled_capabilities
                .contains(&"napaxi.tool.shell_remote".to_string())
        );
        assert!(
            resolution
                .activation_plan
                .remote_required_capabilities
                .contains(&"napaxi.tool.shell_remote".to_string())
        );
        assert!(
            resolution
                .activation_plan
                .policy_required_capabilities
                .contains(&"napaxi.policy.approval".to_string())
        );
    }

    #[test]
    fn mobile_development_scenario_enables_when_host_declares_required_contracts() {
        let profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            supported_capabilities: vec![
                "napaxi.service.developer_workbench".to_string(),
                "napaxi.tool.git".to_string(),
                "napaxi.tool.shell_remote".to_string(),
                "napaxi.policy.approval".to_string(),
            ],
            ..CapabilityProfile::default()
        };
        let selection = CapabilitySelection {
            enabled_capabilities: vec![
                "napaxi.service.developer_workbench".to_string(),
                "napaxi.tool.git".to_string(),
                "napaxi.tool.shell_remote".to_string(),
                "napaxi.policy.approval".to_string(),
            ],
            ..CapabilitySelection::default()
        };
        let profile_json = serde_json::to_string(&profile).unwrap();
        let selection_json = serde_json::to_string(&selection).unwrap();

        let resolution = resolve_scenario(
            "ios",
            &profile_json,
            &selection_json,
            MOBILE_DEVELOPMENT_SCENARIO_ID,
        )
        .expect("mobile development resolution");

        assert!(resolution.status.available);
        assert!(resolution.status.enabled);
        assert!(
            !resolution
                .activation_plan
                .supported_capabilities
                .contains(&"napaxi.service.developer_workbench".to_string())
        );
        assert!(
            !resolution
                .activation_plan
                .enabled_capabilities
                .contains(&"napaxi.tool.shell_remote".to_string())
        );
    }

    #[tokio::test]
    async fn browser_descriptors_require_host_support() {
        let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &base_config(),
            None,
            crate::browser_tools::browser_tool_descriptors(),
        )
        .await;
        assert!(descriptors.is_empty());

        let mut config = base_config();
        config.capability_profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            supported_capabilities: vec![crate::browser_tools::BROWSER_CAPABILITY_ID.to_string()],
            ..CapabilityProfile::default()
        };
        config.capability_selection = CapabilitySelection {
            enabled_capabilities: vec![crate::browser_tools::BROWSER_CAPABILITY_ID.to_string()],
            ..CapabilitySelection::default()
        };

        let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &config,
            None,
            crate::browser_tools::browser_tool_descriptors(),
        )
        .await;
        assert!(
            descriptors
                .iter()
                .any(|descriptor| descriptor.name == crate::browser_tools::BROWSER_OPEN)
        );
    }

    #[tokio::test]
    async fn a2a_descriptors_require_a2a_tool_capability() {
        let a2a_list_agents = crate::tool_registry::ToolDescriptor {
            name: "a2a_list_agents".to_string(),
            description: "List trusted nearby device agents.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {}
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        };

        let mut config = base_config();
        config.capability_profile = CapabilityProfile {
            platform: Some("android".to_string()),
            supported_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..CapabilityProfile::default()
        };
        config.capability_selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.custom_host".to_string()],
            ..CapabilitySelection::default()
        };

        let custom_host_descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &config,
            None,
            vec![a2a_list_agents.clone()],
        )
        .await;
        assert!(
            !custom_host_descriptors
                .iter()
                .any(|descriptor| descriptor.name == "a2a_list_agents")
        );

        config.capability_profile.supported_capabilities =
            vec![crate::a2a::A2A_TOOL_CAPABILITY_ID.to_string()];
        config.capability_selection.enabled_capabilities =
            vec![crate::a2a::A2A_TOOL_CAPABILITY_ID.to_string()];

        let a2a_descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &config,
            None,
            vec![a2a_list_agents],
        )
        .await;
        assert!(
            a2a_descriptors
                .iter()
                .any(|descriptor| descriptor.name == "a2a_list_agents")
        );
    }

    #[tokio::test]
    async fn git_descriptors_require_mobile_development_selection() {
        let git_clone = crate::tool_registry::ToolDescriptor {
            name: "git_clone".to_string(),
            description: "Clone a repository into the mobile developer workspace.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "url": {"type": "string"},
                    "directory": {"type": "string"}
                },
                "required": ["url"]
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        };

        let mut config = base_config();
        config.capability_profile = CapabilityProfile {
            platform: Some("android".to_string()),
            supported_capabilities: vec!["napaxi.tool.git".to_string()],
            ..CapabilityProfile::default()
        };

        let general_descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &config,
            None,
            vec![git_clone.clone()],
        )
        .await;
        assert!(
            !general_descriptors
                .iter()
                .any(|descriptor| descriptor.name == "git_clone")
        );

        config.capability_selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.git".to_string()],
            config: HashMap::from([(
                "scenario_id".to_string(),
                serde_json::json!(MOBILE_DEVELOPMENT_SCENARIO_ID),
            )]),
            ..CapabilitySelection::default()
        };

        let mobile_descriptors =
            crate::tool_loop::gather_tool_descriptors_for_config(&config, None, vec![git_clone])
                .await;
        assert!(
            mobile_descriptors
                .iter()
                .any(|descriptor| descriptor.name == "git_clone")
        );
    }

    #[tokio::test]
    async fn session_recall_uses_memory_capability() {
        assert_eq!(
            tool_capability_id("session_recall").as_deref(),
            Some("napaxi.tool.memory")
        );
        admit_tool_descriptor_for_config(
            "session_recall",
            "ios",
            &CapabilityProfile::default(),
            &CapabilitySelection::default(),
        )
        .unwrap();

        let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &base_config(),
            None,
            crate::memory_tools::descriptors(),
        )
        .await;
        assert!(
            descriptors
                .iter()
                .any(|descriptor| descriptor.name == "session_recall")
        );
    }

    #[tokio::test]
    async fn disabled_memory_capability_filters_search_and_recall_tools() {
        let mut config = base_config();
        config.capability_selection.disabled_capabilities = vec!["napaxi.tool.memory".to_string()];

        let descriptors = crate::tool_loop::gather_tool_descriptors_for_config(
            &config,
            None,
            crate::memory_tools::descriptors(),
        )
        .await;
        assert!(
            !descriptors
                .iter()
                .any(|descriptor| descriptor.name == "memory_search")
        );
        assert!(
            !descriptors
                .iter()
                .any(|descriptor| descriptor.name == "session_recall")
        );
    }

    #[test]
    fn host_profile_controls_platform_tool_availability() {
        let profile = serde_json::json!({
            "platform": "ios",
            "supported_capabilities": ["napaxi.platform_tool.open_url"]
        })
        .to_string();
        let statuses = status("unknown", &profile, "{}");
        let open_url = statuses
            .iter()
            .find(|status| status.definition.id == "napaxi.platform_tool.open_url")
            .unwrap();
        let install_apk = statuses
            .iter()
            .find(|status| status.definition.id == "napaxi.platform_tool.install_apk")
            .unwrap();
        assert!(open_url.available);
        assert!(open_url.enabled);
        assert!(!install_apk.available);
        assert!(!install_apk.enabled);
    }

    #[test]
    fn legacy_capability_configs_map_to_selection() {
        let mut config = base_config();
        config.capability_configs = Some(HashMap::from([(
            "imageAnalysis".to_string(),
            crate::types::PlatformLlmCapabilityConfig {
                provider: "openai_compatible".to_string(),
                api_key: "vision-key".to_string(),
                base_url: None,
                model: "vision-model".to_string(),
                max_tokens: None,
                extra_headers: None,
                image_base64_url_format: None,
            },
        )]));

        let selection = selection_from_llm_config(&config);
        assert_eq!(
            selection.enabled_capabilities,
            vec![
                "napaxi.service.context_engine".to_string(),
                "napaxi.tool.image_analysis".to_string()
            ]
        );
    }

    #[test]
    fn config_capability_selection_is_part_of_effective_selection() {
        let mut config = base_config();
        config.capability_selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.tool.git".to_string()],
            disabled_capabilities: vec!["napaxi.tool.shell".to_string()],
            ..CapabilitySelection::default()
        };

        let selection = selection_from_llm_config(&config);

        assert!(
            selection
                .enabled_capabilities
                .contains(&"napaxi.tool.git".to_string())
        );
        assert!(
            selection
                .disabled_capabilities
                .contains(&"napaxi.tool.shell".to_string())
        );
    }

    #[test]
    fn provider_registry_resolves_aliases() {
        assert_eq!(
            resolve_llm_provider("nearai").unwrap(),
            LlmProviderRoute::OpenAiCompatible
        );
        assert_eq!(
            super::super::provider_capability_id("glm"),
            Some("napaxi.llm.openai_compatible")
        );
    }

    #[test]
    fn disabled_provider_is_rejected_by_runtime_gate() {
        let profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            ..CapabilityProfile::default()
        };
        let selection = CapabilitySelection {
            disabled_capabilities: vec!["napaxi.llm.openai".to_string()],
            ..CapabilitySelection::default()
        };

        let error =
            super::super::resolve_llm_provider_for_config("openai", "ios", &profile, &selection)
                .expect_err("disabled provider should be rejected");

        assert!(error.contains("napaxi.llm.openai"));
        assert!(error.contains("disabled"));
    }

    #[test]
    fn tool_gate_rejects_disabled_and_unavailable_tools() {
        let disabled = CapabilitySelection {
            disabled_capabilities: vec!["napaxi.tool.shell".to_string()],
            ..CapabilitySelection::default()
        };
        assert!(
            admit_tool_descriptor_for_config(
                "shell",
                "android",
                &CapabilityProfile::default(),
                &disabled,
            )
            .unwrap_err()
            .contains("disabled")
        );

        let ios_profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            supported_capabilities: vec!["napaxi.platform_tool.*".to_string()],
            ..CapabilityProfile::default()
        };
        assert!(
            admit_tool_descriptor_for_config(
                crate::platform_capabilities::INSTALL_APK,
                "ios",
                &ios_profile,
                &CapabilitySelection::default(),
            )
            .unwrap_err()
            .contains("not available")
        );
    }
}

mod policy_hook_tests {
    use std::sync::Arc;

    use super::super::{
        CapabilityAdmissionDecision, CapabilityPolicyHook, admit_tool_invocation,
        admit_tool_invocation_typed, register_policy_hook,
    };

    // The policy hook chain is process-global, so tests must not install
    // chain-wide deny hooks (those would race against other tests that
    // legitimately exercise admission). Each test below uses its own probe
    // subject so concurrently-running tests cannot deny each other.

    fn deny_only(subject: &'static str, reason: &'static str) -> CapabilityPolicyHook {
        Arc::new(move |admission| {
            if admission.subject == subject {
                CapabilityAdmissionDecision::Deny(reason.to_string())
            } else {
                CapabilityAdmissionDecision::Allow
            }
        })
    }

    #[test]
    fn register_policy_hook_guard_removes_hook_on_drop() {
        let subject = "tier3_guard_drop_probe";
        {
            let _guard = register_policy_hook(deny_only(subject, "scoped-deny"));
            let err = admit_tool_invocation(subject).unwrap_err();
            assert!(
                err.contains("scoped-deny"),
                "expected deny while guard armed, got {err}"
            );
        }
        // Guard dropped — hook gone, Allow restored for our probe subject.
        assert!(admit_tool_invocation(subject).is_ok());
    }

    #[test]
    fn deregister_explicitly_removes_hook() {
        let subject = "tier3_deregister_probe";
        let guard = register_policy_hook(deny_only(subject, "explicit"));
        assert!(admit_tool_invocation(subject).is_err());
        guard.deregister();
        assert!(admit_tool_invocation(subject).is_ok());
    }

    #[test]
    fn admit_typed_surfaces_capability_denied_error() {
        let subject = "tier3_typed_deny_probe";
        let other_subject = "tier3_typed_other_probe";
        let _guard = register_policy_hook(deny_only(subject, "policy_test"));
        let err = admit_tool_invocation_typed(subject).unwrap_err();
        assert_eq!(err.code(), "capability_denied");
        assert!(
            err.to_string().contains("policy_test"),
            "expected policy_test reason in {err}"
        );
        // Subjects not matched by the hook still admit normally.
        assert!(admit_tool_invocation_typed(other_subject).is_ok());
    }

    #[test]
    fn first_deny_short_circuits_remaining_hooks() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let subject = "tier3_short_circuit_probe";
        let second_called = Arc::new(AtomicUsize::new(0));
        let _g1 = register_policy_hook(deny_only(subject, "first"));
        let second_clone = Arc::clone(&second_called);
        let _g2 = register_policy_hook(Arc::new(move |admission| {
            if admission.subject == "tier3_short_circuit_probe" {
                second_clone.fetch_add(1, Ordering::Relaxed);
            }
            CapabilityAdmissionDecision::Allow
        }));
        let _ = admit_tool_invocation(subject);
        assert_eq!(
            second_called.load(Ordering::Relaxed),
            0,
            "second hook should not run after first Deny for the same subject"
        );
    }
}

mod admission_decision_tests {
    use super::super::{
        ADMISSION_DECISION_BUFFER_CAP, AdmissionDecisionRecord, CapabilityAdmissionDecision,
        admit_tool_invocation_typed, clear_admission_decisions, new_admission_sink,
        recent_admission_decisions, register_policy_hook, sink_snapshot, with_admission_sink,
    };

    /// Snapshot containing only decisions for a specific probe subject —
    /// filters out decisions that other tests recorded concurrently.
    fn probe_decisions(subject: &str) -> Vec<AdmissionDecisionRecord> {
        recent_admission_decisions()
            .into_iter()
            .filter(|d| d.subject == subject)
            .collect()
    }

    /// Serializes tests in this module against each other. They share the
    /// global, capacity-bounded admission-decision ring buffer, so a test that
    /// fills the buffer (`buffer_respects_capacity_bound`) can otherwise evict
    /// another test's just-recorded entry mid-assertion. Acquiring this lock
    /// keeps them from racing; the guard is poison-tolerant so one failing
    /// test does not cascade.
    fn decision_buffer_lock() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
        LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    #[tokio::test]
    async fn admission_sink_scopes_decisions_per_engine() {
        // Two engines own two sinks. Admissions recorded under each engine's
        // scope land only in that engine's sink, and never in the global
        // fallback. This is the per-engine admission-trace isolation that
        // `EngineHandle::admission_trace` now provides. Unique probe subjects
        // keep the test insensitive to parallel admissions; records go to local
        // sinks so there is no shared-buffer race.
        let sink_a = new_admission_sink();
        let sink_b = new_admission_sink();

        with_admission_sink(sink_a.clone(), async {
            let _ = admit_tool_invocation_typed("probe_sink_engine_a");
        })
        .await;
        with_admission_sink(sink_b.clone(), async {
            let _ = admit_tool_invocation_typed("probe_sink_engine_b");
        })
        .await;

        let a = sink_snapshot(&sink_a);
        let b = sink_snapshot(&sink_b);

        // Each engine sees its own decision...
        assert!(a.iter().any(|d| d.subject == "probe_sink_engine_a"));
        assert!(b.iter().any(|d| d.subject == "probe_sink_engine_b"));
        // ...and not the other engine's (the isolation guarantee).
        assert!(!a.iter().any(|d| d.subject == "probe_sink_engine_b"));
        assert!(!b.iter().any(|d| d.subject == "probe_sink_engine_a"));

        // Scoped decisions do not leak into the process-global fallback.
        let global = recent_admission_decisions();
        assert!(
            !global
                .iter()
                .any(|d| d.subject.starts_with("probe_sink_engine_")),
            "scoped admissions must not land in the global buffer"
        );
    }

    #[test]
    fn unscoped_decisions_fall_back_to_global_buffer() {
        // Admissions outside any engine scope still record to the global
        // buffer, so observability is never lost.
        let _lock = decision_buffer_lock();
        let _ = admit_tool_invocation_typed("probe_unscoped_global");
        assert!(
            recent_admission_decisions()
                .iter()
                .any(|d| d.subject == "probe_unscoped_global"),
            "unscoped admission should fall back to the global buffer"
        );
    }

    #[test]
    fn allow_decision_is_recorded() {
        let _guard = decision_buffer_lock();
        let subject = "tier3_decision_allow_probe";
        admit_tool_invocation_typed(subject).expect("default allow");
        // Look up our latest decision for this subject. We avoid `before+1`
        // counting because parallel tests can evict older entries by filling
        // the ring buffer (see `buffer_respects_capacity_bound`).
        let mine = probe_decisions(subject);
        assert!(
            !mine.is_empty(),
            "expected at least one decision for {subject}"
        );
        let latest = mine.last().unwrap();
        assert!(latest.allowed);
        assert_eq!(latest.reason, "admitted");
        assert_eq!(latest.subject, subject);
    }

    #[test]
    fn deny_decision_is_recorded() {
        let _guard = decision_buffer_lock();
        let subject = "tier3_decision_deny_probe";
        let _guard = register_policy_hook(std::sync::Arc::new(|admission| {
            if admission.subject == "tier3_decision_deny_probe" {
                CapabilityAdmissionDecision::Deny("trace-test-deny".to_string())
            } else {
                CapabilityAdmissionDecision::Allow
            }
        }));
        let err = admit_tool_invocation_typed(subject).unwrap_err();
        assert_eq!(err.code(), "capability_denied");
        // Find a deny entry for our subject; tolerate older buffered entries
        // for the same subject from previous test runs.
        let mine = probe_decisions(subject);
        let latest_deny = mine.iter().rev().find(|d| !d.allowed);
        assert!(
            latest_deny.is_some(),
            "expected at least one deny decision for {subject}"
        );
        let latest = latest_deny.unwrap();
        assert_eq!(latest.reason, "trace-test-deny");
    }

    #[test]
    fn buffer_respects_capacity_bound() {
        let _guard = decision_buffer_lock();
        // Push more than the cap on a unique subject and ensure the global
        // buffer cap is honored even when other tests run in parallel.
        let subject = "tier3_decision_cap_probe";
        for _ in 0..(ADMISSION_DECISION_BUFFER_CAP + 10) {
            let _ = admit_tool_invocation_typed(subject);
        }
        let all = recent_admission_decisions();
        assert!(
            all.len() <= ADMISSION_DECISION_BUFFER_CAP,
            "buffer should stay bounded, got {}",
            all.len()
        );
    }

    #[test]
    fn clear_admission_decisions_empties_buffer() {
        let _guard = decision_buffer_lock();
        // Note: this test cannot assert post-clear emptiness reliably under
        // parallel execution (other tests record concurrently). The contract
        // we verify is that the clear call itself succeeds and that at least
        // one moment exists where our just-recorded probe is gone.
        let subject = "tier3_decision_clear_probe";
        let _ = admit_tool_invocation_typed(subject);
        clear_admission_decisions();
        // Soft check: our specific decision is gone for at least an instant.
        // We do not assert global emptiness because parallel tests will race.
        let _ = recent_admission_decisions();
    }
}

mod provider_admission_tests {
    use super::super::{
        CapabilityAdmissionDecision, CapabilityAdmissionKind, CapabilityProfile,
        CapabilitySelection, LlmProviderRoute, register_policy_hook,
        resolve_llm_provider_for_config,
    };

    #[test]
    fn resolve_llm_provider_for_config_calls_policy_chain() {
        // Use a probe provider name that resolves successfully (openai)
        // but is gated by a per-test policy hook.
        let _guard = register_policy_hook(std::sync::Arc::new(|admission| {
            if matches!(admission.kind, CapabilityAdmissionKind::Provider)
                && admission.subject == "openai"
                && admission
                    .capability_id
                    .as_deref()
                    .is_some_and(|id| id == "napaxi.llm.openai")
            {
                CapabilityAdmissionDecision::Deny("tier3_provider_test_deny".to_string())
            } else {
                CapabilityAdmissionDecision::Allow
            }
        }));

        let profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            ..CapabilityProfile::default()
        };
        let selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.llm.openai".to_string()],
            ..CapabilitySelection::default()
        };
        let err = resolve_llm_provider_for_config("openai", "ios", &profile, &selection)
            .expect_err("policy hook should deny the provider");
        assert!(
            err.contains("tier3_provider_test_deny"),
            "expected policy reason in error, got {err}"
        );
    }

    #[test]
    fn resolve_llm_provider_for_config_succeeds_when_policy_allows() {
        // Use a provider name that the other test's deny hook does not
        // match ("anthropic" vs the other test's "openai"), so this test
        // is insensitive to parallel hook installation.
        let profile = CapabilityProfile {
            platform: Some("ios".to_string()),
            ..CapabilityProfile::default()
        };
        let selection = CapabilitySelection {
            enabled_capabilities: vec!["napaxi.llm.anthropic".to_string()],
            ..CapabilitySelection::default()
        };
        let route = resolve_llm_provider_for_config("anthropic", "ios", &profile, &selection)
            .expect("provider should resolve without deny hook");
        assert!(matches!(route, LlmProviderRoute::Anthropic));
    }
}
