use super::*;
use crate::tool_registry::ToolEffect;

fn config() -> PlatformLlmConfig {
    let mut config = PlatformLlmConfig::default();
    config.capability_profile.supported_capabilities = vec!["napaxi.tool.custom_host".to_string()];
    config.capability_selection.enabled_capabilities = vec!["napaxi.tool.custom_host".to_string()];
    config
}

fn descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "demo_tool".to_string(),
        description: "Demo".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "value": {"type": "string"}
            },
            "required": ["value"]
        }),
        effect: ToolEffect::Read,
    }
}

fn shell_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "shell".to_string(),
        description: "Run a shell command".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "command": {"type": "string"}
            },
            "required": ["command"]
        }),
        effect: ToolEffect::Write,
    }
}

fn git_clone_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_clone".to_string(),
        description: "Clone a Git repository".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "url": {"type": "string"}
            },
            "required": ["url"]
        }),
        effect: ToolEffect::Write,
    }
}

fn git_status_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_status".to_string(),
        description: "Read Git status".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"}
            },
            "required": ["directory"]
        }),
        effect: ToolEffect::Read,
    }
}

fn git_diff_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_diff".to_string(),
        description: "Read Git diff".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"},
                "stat": {"type": "boolean"}
            },
            "required": ["directory"]
        }),
        effect: ToolEffect::Read,
    }
}

fn git_list_branches_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_list_branches".to_string(),
        description: "List Git branches".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"}
            },
            "required": ["directory"]
        }),
        effect: ToolEffect::Read,
    }
}

fn git_switch_branch_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_switch_branch".to_string(),
        description: "Switch Git branch".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"},
                "branch": {"type": "string"},
                "remote": {"type": "boolean"}
            },
            "required": ["directory", "branch"]
        }),
        effect: ToolEffect::Write,
    }
}

fn git_list_remotes_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_list_remotes".to_string(),
        description: "List Git remotes".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"}
            },
            "required": ["directory"]
        }),
        effect: ToolEffect::Read,
    }
}

fn git_set_remote_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_set_remote".to_string(),
        description: "Set Git remote".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"},
                "name": {"type": "string"},
                "url": {"type": "string"},
                "action": {"type": "string"}
            },
            "required": ["directory", "name"]
        }),
        effect: ToolEffect::Write,
    }
}

fn git_fetch_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "git_fetch".to_string(),
        description: "Fetch Git remotes".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "directory": {"type": "string"},
                "remote": {"type": "string"},
                "prune": {"type": "boolean"}
            },
            "required": ["directory"]
        }),
        effect: ToolEffect::Write,
    }
}

fn mobile_development_config(git_ready: bool) -> PlatformLlmConfig {
    let mut config = PlatformLlmConfig::default();
    config.capability_profile.platform = Some("android".to_string());
    config.capability_profile.supported_capabilities = vec!["napaxi.tool.git".to_string()];
    config.capability_selection.enabled_capabilities = vec![
        "napaxi.tool.git".to_string(),
        "napaxi.tool.shell".to_string(),
    ];
    config.capability_selection.config = std::collections::HashMap::from([
        (
            "scenario_id".to_string(),
            serde_json::json!(crate::capabilities::MOBILE_DEVELOPMENT_SCENARIO_ID),
        ),
        (
            "git_provider_configured".to_string(),
            serde_json::json!(git_ready),
        ),
        (
            "git_provider_healthy".to_string(),
            serde_json::json!(git_ready),
        ),
    ]);
    config
}

/// Same as [`mobile_development_config`] but with native (paseo-style) git mode:
/// shell `git` runs directly against the sandbox rootfs binary instead of being
/// redirected to the host's dedicated structured git tools.
fn native_git_config() -> PlatformLlmConfig {
    let mut config = mobile_development_config(false);
    config.git = Some(crate::types::GitConfig {
        mode: GitMode::Native,
        identity: None,
    });
    config
}

#[test]
fn native_git_mode_does_not_redirect_shell_git_clone() {
    // Even with the git_clone tool available, native mode must NOT rewrite the
    // shell call into a structured git_clone invocation.
    let descriptors = [shell_descriptor(), git_clone_descriptor()];
    let prepared = prepare_tool_invocation(
        &native_git_config(),
        &descriptors,
        "shell",
        r#"{"command":"git clone --depth 1 https://example.com/repo.git /workspace/repo"}"#,
    )
    .unwrap();

    assert_eq!(prepared.name, "shell");
    assert!(
        prepared.route.is_none(),
        "native git mode must not route shell git to a structured tool"
    );
}

#[test]
fn native_git_mode_passes_shell_git_status_and_commit_through_unchanged() {
    let descriptors = [shell_descriptor(), git_status_descriptor()];

    // Read-only status is left as a plain shell call (approval happens later).
    let status = prepare_tool_invocation(
        &native_git_config(),
        &descriptors,
        "shell",
        r#"{"command":"git -C /workspace/repo status"}"#,
    )
    .unwrap();
    assert_eq!(status.name, "shell");
    assert!(status.route.is_none());

    // A write (commit) is not redirected either; it prepares as a shell call and
    // the shell approval posture decides whether to run it.
    let commit = prepare_tool_invocation(
        &native_git_config(),
        &descriptors,
        "shell",
        r#"{"command":"git -C /workspace/repo commit -am wip"}"#,
    )
    .unwrap();
    assert_eq!(commit.name, "shell");
    assert!(commit.route.is_none());
}

#[test]
fn native_git_mode_does_not_block_shell_git_install() {
    // In native mode the whole intent mediator is skipped, so installing git
    // (e.g. as a fallback on a rootfs that did not bake it in) is no longer
    // hard-rejected at prepare time; it is left to the normal shell policy.
    let descriptors = [shell_descriptor()];
    prepare_tool_invocation(
        &native_git_config(),
        &descriptors,
        "shell",
        r#"{"command":"apk add git"}"#,
    )
    .expect("native git mode must not block shell git install at prepare time");
}

#[test]
fn preparation_rejects_invalid_json_with_model_visible_guidance() {
    let error =
        prepare_tool_invocation(&config(), &[descriptor()], "demo_tool", "{invalid").unwrap_err();

    assert!(error.into_model_output().contains("must be valid JSON"));
}

#[test]
fn preparation_rejects_schema_mismatch_before_execution() {
    let error = prepare_tool_invocation(&config(), &[descriptor()], "demo_tool", "{}").unwrap_err();

    assert!(error.into_model_output().contains("Invalid arguments"));
}

#[test]
fn preparation_returns_schema_prepared_params() {
    let descriptors = [descriptor()];
    let prepared = prepare_tool_invocation(
        &config(),
        &descriptors,
        "demo_tool",
        r#"{"value":"ok","extra":true}"#,
    )
    .unwrap();

    assert_eq!(prepared.params["value"].as_str(), Some("ok"));
    assert_eq!(prepared.descriptor.name, "demo_tool");
}

#[test]
fn shell_git_clone_routes_to_repo_clone_intent_when_available() {
    let descriptors = [shell_descriptor(), git_clone_descriptor()];
    let prepared = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git clone --depth 2 -b main https://example.com/repo.git /workspace/repo"}"#,
    )
    .unwrap();

    assert_eq!(prepared.name, "git_clone");
    assert_eq!(prepared.params["url"], "https://example.com/repo.git");
    assert_eq!(prepared.params["directory"], "repo");
    assert_eq!(prepared.params["branch"], "main");
    assert_eq!(prepared.params["depth"], 2);
    let route = prepared.route.expect("shell git clone should be routed");
    assert_eq!(route.intent_id, "repo.clone");
    assert_eq!(route.source_tool, "shell");
    assert_eq!(route.target_tool, "git_clone");
}

#[test]
fn shell_git_clone_requires_repo_clone_tool_descriptor() {
    let descriptors = [shell_descriptor()];
    let error = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git clone https://example.com/repo.git"}"#,
    )
    .unwrap_err();

    let output = error.into_model_output();
    assert!(output.contains("repo"));
    assert!(output.contains("git_clone"));
}

#[test]
fn shell_git_status_and_diff_route_to_repo_intents() {
    let descriptors = [
        shell_descriptor(),
        git_status_descriptor(),
        git_diff_descriptor(),
    ];

    let status = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C /workspace/repo status --short --branch"}"#,
    )
    .unwrap();
    assert_eq!(status.name, "git_status");
    assert_eq!(status.params["directory"], "repo");
    assert_eq!(status.route.expect("status route").intent_id, "repo.status");

    let diff = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C repo diff --stat"}"#,
    )
    .unwrap();
    assert_eq!(diff.name, "git_diff");
    assert_eq!(diff.params["directory"], "repo");
    assert_eq!(diff.params["stat"], true);
    assert_eq!(diff.route.expect("diff route").intent_id, "repo.diff");
}

#[test]
fn shell_git_branch_remote_and_fetch_route_to_repo_intents() {
    let descriptors = [
        shell_descriptor(),
        git_list_branches_descriptor(),
        git_switch_branch_descriptor(),
        git_list_remotes_descriptor(),
        git_set_remote_descriptor(),
        git_fetch_descriptor(),
    ];

    let branches = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C /workspace/repo branch --all"}"#,
    )
    .unwrap();
    assert_eq!(branches.name, "git_list_branches");
    assert_eq!(branches.params["directory"], "repo");
    assert_eq!(
        branches.route.expect("branch route").intent_id,
        "repo.branch.list"
    );

    let switch = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C /workspace/repo switch --track origin/feature"}"#,
    )
    .unwrap();
    assert_eq!(switch.name, "git_switch_branch");
    assert_eq!(switch.params["branch"], "origin/feature");
    assert_eq!(switch.params["remote"], true);
    assert_eq!(
        switch.route.expect("switch route").intent_id,
        "repo.branch.switch"
    );

    let remote_list = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C repo remote -v"}"#,
    )
    .unwrap();
    assert_eq!(remote_list.name, "git_list_remotes");
    assert_eq!(remote_list.params["directory"], "repo");

    let remote_set = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C repo remote set-url origin https://example.com/repo.git"}"#,
    )
    .unwrap();
    assert_eq!(remote_set.name, "git_set_remote");
    assert_eq!(remote_set.params["name"], "origin");
    assert_eq!(remote_set.params["action"], "upsert");

    let fetch = prepare_tool_invocation(
        &mobile_development_config(false),
        &descriptors,
        "shell",
        r#"{"command":"git -C repo fetch --prune origin"}"#,
    )
    .unwrap();
    assert_eq!(fetch.name, "git_fetch");
    assert_eq!(fetch.params["remote"], "origin");
    assert_eq!(fetch.params["prune"], true);
}

#[test]
fn shell_git_clone_is_plain_shell_outside_mobile_development_intent_policy() {
    let mut config = PlatformLlmConfig::default();
    config.capability_profile.platform = Some("android".to_string());
    config.capability_selection.enabled_capabilities = vec!["napaxi.tool.shell".to_string()];
    config.capability_selection.config.insert(
        "scenario_id".to_string(),
        serde_json::json!(crate::capabilities::GENERAL_SCENARIO_ID),
    );
    let descriptors = [shell_descriptor(), git_clone_descriptor()];
    let prepared = prepare_tool_invocation(
        &config,
        &descriptors,
        "shell",
        r#"{"command":"git clone https://example.com/repo.git"}"#,
    )
    .unwrap();

    assert_eq!(prepared.name, "shell");
    assert_eq!(
        prepared.params["command"],
        "git clone https://example.com/repo.git"
    );
    assert!(prepared.route.is_none());
}

#[test]
fn shell_git_config_can_run_when_git_ready_and_no_direct_tool_covers_it() {
    let descriptors = [shell_descriptor()];
    let prepared = prepare_tool_invocation(
        &mobile_development_config(true),
        &descriptors,
        "shell",
        r#"{"command":"git config --get user.name"}"#,
    )
    .unwrap();

    assert_eq!(
        prepared.params["command"].as_str(),
        Some("git config --get user.name")
    );
}

#[test]
fn shell_installing_git_is_rejected_in_mobile_development_scenario() {
    let descriptors = [shell_descriptor()];
    let error = prepare_tool_invocation(
        &mobile_development_config(true),
        &descriptors,
        "shell",
        r#"{"command":"apt-get install git"}"#,
    )
    .unwrap_err();

    assert!(
        error
            .into_model_output()
            .contains("Installing Git through shell")
    );
}
