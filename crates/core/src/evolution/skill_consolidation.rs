use std::collections::HashSet;

use chrono::Utc;
use napaxi_evolution::{PendingActionType, PendingConfirmation, ReviewSource, ReviewType};
use serde::{Deserialize, Serialize};

use crate::tool_registry::ToolDescriptor;
use crate::types::PlatformLlmConfig;

use super::{invalid_handle_json, store::persist_pending_confirmations};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillConsolidationReviewResult {
    pub reviewed: bool,
    pub dry_run: bool,
    pub suggestions_count: usize,
    pub pending_count: usize,
    pub pending_id: Option<String>,
    #[serde(default)]
    pub actions: Vec<PendingActionType>,
    #[serde(default)]
    pub warnings: Vec<String>,
    pub error: Option<String>,
}

fn consolidation_tool_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: "review_skill".to_string(),
        description: "Propose a pending skill consolidation action. Use only patch, write_file, or delete. For delete, absorbed_into is required.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["patch", "write_file", "delete"]
                },
                "name": {"type": "string"},
                "old_string": {"type": "string"},
                "new_string": {"type": "string"},
                "file_path": {"type": "string"},
                "content": {"type": "string"},
                "absorbed_into": {"type": "string"},
                "confidence": {
                    "type": "string",
                    "enum": ["high", "medium", "low"]
                },
                "reasoning": {"type": "string"}
            },
            "required": ["action", "name", "confidence", "reasoning"]
        }),
        effect: crate::tool_registry::ToolEffect::Write,
    }
}

fn parse_consolidation_tool_calls(
    tool_calls: &[crate::llm::LlmToolCall],
) -> (Vec<PendingActionType>, Vec<String>) {
    let mut actions = Vec::new();
    let mut warnings = Vec::new();
    for call in tool_calls {
        if call.name != "review_skill" {
            warnings.push(format!("ignored unsupported tool call '{}'", call.name));
            continue;
        }
        let value = match serde_json::from_str::<serde_json::Value>(&call.arguments) {
            Ok(value) => value,
            Err(error) => {
                warnings.push(format!("invalid review_skill arguments: {error}"));
                continue;
            }
        };
        let input = match serde_json::from_value::<napaxi_evolution::ReviewSkillInput>(value) {
            Ok(input) => input,
            Err(error) => {
                warnings.push(format!("invalid review_skill input: {error}"));
                continue;
            }
        };
        match input.action.as_str() {
            "patch" => {
                let old_string = input.old_string.unwrap_or_default();
                let Some(new_string) = input.new_string else {
                    warnings.push(format!(
                        "patch for '{}' ignored because new_string is missing",
                        input.name
                    ));
                    continue;
                };
                if old_string.trim().is_empty() {
                    warnings.push(format!(
                        "patch for '{}' ignored because old_string is empty",
                        input.name
                    ));
                    continue;
                }
                actions.push(PendingActionType::Patch {
                    skill_name: input.name,
                    old_string,
                    new_string,
                    file_path: input.file_path,
                    replace_all: input.replace_all,
                });
            }
            "write_file" => {
                let Some(file_content) = input.content else {
                    warnings.push(format!(
                        "write_file for '{}' ignored because content is missing",
                        input.name
                    ));
                    continue;
                };
                actions.push(PendingActionType::WriteFile {
                    skill_name: input.name,
                    file_path: input
                        .file_path
                        .unwrap_or_else(|| "references/consolidation.md".to_string()),
                    file_content,
                });
            }
            "delete" => {
                let absorbed_into = input.absorbed_into.filter(|value| !value.trim().is_empty());
                if absorbed_into.is_none() {
                    warnings.push(format!(
                        "delete for '{}' ignored because absorbed_into is missing",
                        input.name
                    ));
                    continue;
                }
                actions.push(PendingActionType::Delete {
                    skill_name: input.name,
                    absorbed_into,
                });
            }
            other => warnings.push(format!(
                "ignored unsupported consolidation action '{other}'"
            )),
        }
    }
    (actions, warnings)
}

fn protected_skill_names_from_usage_json(usage_json: &str) -> HashSet<String> {
    serde_json::from_str::<Vec<crate::skills::SkillUsageRecord>>(usage_json)
        .unwrap_or_default()
        .into_iter()
        .filter(|record| {
            record.pinned || record.protected || record.created_by.as_deref() == Some("system")
        })
        .map(|record| record.skill_name)
        .collect()
}

fn protected_skill_names_from_skills_json(skills_json: &str) -> HashSet<String> {
    serde_json::from_str::<serde_json::Value>(skills_json)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter(|skill| {
            skill
                .get("lifecycle")
                .and_then(|lifecycle| lifecycle.get("protected"))
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
        })
        .filter_map(|skill| {
            skill
                .get("name")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .collect()
}

fn filter_consolidation_actions(
    actions: Vec<PendingActionType>,
    protected_skills: &HashSet<String>,
    warnings: &mut Vec<String>,
) -> Vec<PendingActionType> {
    let mut filtered = Vec::with_capacity(actions.len());
    for action in actions {
        match &action {
            PendingActionType::Delete { skill_name, .. }
                if protected_skills.contains(skill_name) =>
            {
                warnings.push(format!("delete for protected skill '{skill_name}' ignored"));
            }
            PendingActionType::Delete {
                skill_name,
                absorbed_into: Some(absorbed_into),
            } if skill_name == absorbed_into => {
                warnings.push(format!(
                    "delete for '{}' ignored because absorbed_into points to itself",
                    skill_name
                ));
            }
            _ => filtered.push(action),
        }
    }
    filtered
}

fn skill_consolidation_prompt(skills_json: &str, usage_json: &str) -> String {
    format!(
        r#"Review the skill library for consolidation opportunities.

You are producing pending suggestions only. Do not claim anything was applied.

Allowed actions:
- patch: update an umbrella skill so it absorbs a narrower skill's durable guidance.
- write_file: write supporting consolidation detail under references/, templates/, scripts/, or assets/.
- delete: archive a narrower skill that has been absorbed. Every delete MUST include absorbed_into with the umbrella skill name.

Rules:
- pinned or protected skills must not be archived or absorbed.
- Prefer one concise consolidation group.
- Do not consolidate merely because a skill is unused; that is handled by the rule curator.
- Do not create new skills.
- Do not remove temporary troubleshooting notes unless they were already durable skill content.
- Return no tool calls if there is no clear consolidation.

Current skills:
{skills_json}

Usage/lifecycle:
{usage_json}
"#
    )
}

pub async fn run_skill_consolidation_review(
    files_dir: &str,
    agent_id: &str,
    config: &PlatformLlmConfig,
    dry_run: bool,
) -> String {
    if config.api_key.trim().is_empty() || config.model.trim().is_empty() {
        return serde_json::json!({
            "reviewed": false,
            "dry_run": dry_run,
            "suggestions_count": 0,
            "pending_count": 0,
            "pending_id": null,
            "actions": [],
            "warnings": [],
            "error": "LLM API key and model are required",
        })
        .to_string();
    }
    let skills_json = crate::skills::list_skills(files_dir, agent_id).await;
    let usage_json = crate::skills::list_skill_usage(files_dir, agent_id).await;
    let messages = vec![
        serde_json::json!({
            "role": "system",
            "content": "You are Napaxi Skill Curator v2. Use tool calls only for pending consolidation suggestions."
        }),
        serde_json::json!({
            "role": "user",
            "content": skill_consolidation_prompt(&skills_json, &usage_json)
        }),
    ];
    let turn = match crate::llm::complete_turn_with_raw_messages(
        config,
        &messages,
        &[consolidation_tool_descriptor()],
    )
    .await
    {
        Ok(turn) => turn,
        Err(error) => {
            return serde_json::json!({
                "reviewed": true,
                "dry_run": dry_run,
                "suggestions_count": 0,
                "pending_count": 0,
                "pending_id": null,
                "actions": [],
                "warnings": [],
                "error": error.to_string(),
            })
            .to_string();
        }
    };
    let (actions, mut warnings) = parse_consolidation_tool_calls(&turn.tool_calls);
    let mut protected_skills = protected_skill_names_from_usage_json(&usage_json);
    protected_skills.extend(protected_skill_names_from_skills_json(&skills_json));
    let actions = filter_consolidation_actions(actions, &protected_skills, &mut warnings);
    let mut pending_id = None;
    let mut pending_count = 0usize;
    let mut error = None;
    if !dry_run && !actions.is_empty() {
        let mut confirmation = PendingConfirmation::new(
            actions[0].clone(),
            ReviewSource {
                job_id: uuid::Uuid::new_v4().to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            "Skill consolidation review".to_string(),
            "skill-curator".to_string(),
        );
        confirmation.aggregated_actions = actions.clone();
        pending_id = Some(confirmation.id.to_string());
        match persist_pending_confirmations(files_dir, agent_id, &[confirmation]) {
            Ok(count) => pending_count = count,
            Err(persist_error) => error = Some(persist_error),
        }
    }
    serde_json::to_string(&SkillConsolidationReviewResult {
        reviewed: true,
        dry_run,
        suggestions_count: actions.len(),
        pending_count,
        pending_id,
        actions,
        warnings,
        error,
    })
    .unwrap_or_else(|_| "{}".to_string())
}

pub async fn run_skill_consolidation_review_handle(
    handle: i64,
    agent_id: &str,
    config_json: &str,
    dry_run: bool,
) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    let scoped =
        crate::workspace::default_scoped_files_dir(&files_dir, crate::runtime::DEFAULT_AGENT_ID);
    let config = match serde_json::from_str::<PlatformLlmConfig>(config_json) {
        Ok(config) => config,
        Err(error) => {
            return serde_json::json!({"error": format!("invalid config_json: {error}")})
                .to_string();
        }
    };
    run_skill_consolidation_review(&scoped, agent_id, &config, dry_run).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn consolidation_tool_calls_require_absorbed_into_for_delete() {
        let missing_absorbed_into = vec![crate::llm::LlmToolCall {
            id: "call-1".to_string(),
            name: "review_skill".to_string(),
            arguments: serde_json::json!({
                "action": "delete",
                "name": "narrow-skill",
                "confidence": "medium",
                "reasoning": "covered by umbrella"
            })
            .to_string(),
        }];
        let (actions, warnings) = parse_consolidation_tool_calls(&missing_absorbed_into);
        assert!(actions.is_empty());
        assert!(
            warnings
                .iter()
                .any(|warning| warning.contains("absorbed_into"))
        );

        let with_absorbed_into = vec![crate::llm::LlmToolCall {
            id: "call-2".to_string(),
            name: "review_skill".to_string(),
            arguments: serde_json::json!({
                "action": "delete",
                "name": "narrow-skill",
                "absorbed_into": "umbrella-skill",
                "confidence": "medium",
                "reasoning": "covered by umbrella"
            })
            .to_string(),
        }];
        let (actions, warnings) = parse_consolidation_tool_calls(&with_absorbed_into);
        assert!(warnings.is_empty());
        assert!(matches!(
            &actions[0],
            PendingActionType::Delete {
                skill_name,
                absorbed_into: Some(absorbed_into),
            } if skill_name == "narrow-skill" && absorbed_into == "umbrella-skill"
        ));
    }

    #[test]
    fn consolidation_filter_blocks_protected_and_self_absorbed_deletes() {
        let usage_json = serde_json::json!([
            {"skill_name": "pinned-skill", "pinned": true},
            {"skill_name": "system-skill", "protected": true},
            {"skill_name": "regular-skill", "pinned": false}
        ])
        .to_string();
        let protected = protected_skill_names_from_usage_json(&usage_json);
        let mut warnings = Vec::new();
        let actions = filter_consolidation_actions(
            vec![
                PendingActionType::Delete {
                    skill_name: "pinned-skill".to_string(),
                    absorbed_into: Some("umbrella-skill".to_string()),
                },
                PendingActionType::Delete {
                    skill_name: "system-skill".to_string(),
                    absorbed_into: Some("umbrella-skill".to_string()),
                },
                PendingActionType::Delete {
                    skill_name: "self-skill".to_string(),
                    absorbed_into: Some("self-skill".to_string()),
                },
                PendingActionType::Delete {
                    skill_name: "regular-skill".to_string(),
                    absorbed_into: Some("umbrella-skill".to_string()),
                },
            ],
            &protected,
            &mut warnings,
        );

        assert_eq!(actions.len(), 1);
        assert!(warnings.iter().any(|warning| warning.contains("protected")));
        assert!(warnings.iter().any(|warning| warning.contains("itself")));
    }
}
