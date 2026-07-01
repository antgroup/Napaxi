//! The hidden `skill_load` tool descriptor and runtime handler.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use tokio::sync::Mutex;

use crate::tool_loop::{InternalToolHandler, InternalToolResult};
use crate::tool_registry::ToolDescriptor;

use super::afs::registry;
use super::limits::{MAX_ACTIVE_SKILLS_PER_TURN, SKILL_LOAD_TOOL_NAME};
use super::paths::normalize_agent_id;
use super::prompt::{activated_skill_info, loaded_skill_prompt};
use super::session::record_session_skill_load;
use super::usage::record_skill_use;

pub(crate) fn skill_load_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: SKILL_LOAD_TOOL_NAME.to_string(),
        description: "Load the full instructions for one skill listed in the current available_skills catalog.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Exact skill name from the available_skills catalog."
                }
            },
            "required": ["name"]
        }),
        effect: crate::tool_registry::ToolEffect::Read,
    }
}

pub(crate) fn is_hidden_skill_tool(name: &str) -> bool {
    name == SKILL_LOAD_TOOL_NAME
}

pub(crate) fn skill_load_handler(
    files_dir: String,
    agent_id: String,
    thread_id: String,
    catalog_skill_names: Vec<String>,
    catalog_skill_hashes: HashMap<String, String>,
    response_language: String,
    fallback: Option<InternalToolHandler>,
) -> InternalToolHandler {
    let allowed_skill_names = Arc::new(
        catalog_skill_names
            .into_iter()
            .map(|name| (name.to_lowercase(), name))
            .collect::<HashMap<_, _>>(),
    );
    let loaded_skill_names = Arc::new(Mutex::new(HashSet::<String>::new()));
    let catalog_skill_hashes = Arc::new(catalog_skill_hashes);
    Arc::new(move |tool_name, params, progress| {
        if !is_hidden_skill_tool(tool_name) {
            return fallback
                .as_ref()
                .and_then(|handler| handler(tool_name, params, progress));
        }
        let files_dir = files_dir.clone();
        let agent_id = agent_id.clone();
        let thread_id = thread_id.clone();
        let allowed_skill_names = Arc::clone(&allowed_skill_names);
        let loaded_skill_names = Arc::clone(&loaded_skill_names);
        let catalog_skill_hashes = Arc::clone(&catalog_skill_hashes);
        let response_language = response_language.clone();
        Some(Box::pin(async move {
            execute_skill_load(
                &files_dir,
                &agent_id,
                &thread_id,
                &allowed_skill_names,
                &catalog_skill_hashes,
                &loaded_skill_names,
                &response_language,
                params,
            )
            .await
        }))
    })
}

pub(super) async fn execute_skill_load(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    allowed_skill_names: &HashMap<String, String>,
    catalog_skill_hashes: &HashMap<String, String>,
    loaded_skill_names: &Mutex<HashSet<String>>,
    response_language: &str,
    params: serde_json::Value,
) -> Result<InternalToolResult, String> {
    let Some(raw_name) = params.get("name").and_then(|value| value.as_str()) else {
        return Err("skill_load requires a name".to_string());
    };
    let lookup = raw_name.trim().to_lowercase();
    let Some(skill_name) = allowed_skill_names.get(&lookup).cloned() else {
        return Err(format!(
            "skill_load can only load skills listed in the current available_skills catalog; '{raw_name}' is not available"
        ));
    };

    {
        let mut loaded = loaded_skill_names.lock().await;
        if loaded.contains(&skill_name) {
            return Ok(InternalToolResult {
                output: serde_json::json!({
                    "ok": true,
                    "already_loaded": true,
                    "name": skill_name,
                })
                .to_string(),
                events: Vec::new(),
            });
        }
        if loaded.len() >= MAX_ACTIVE_SKILLS_PER_TURN {
            return Err(format!(
                "skill_load reached the per-turn limit of {MAX_ACTIVE_SKILLS_PER_TURN} loaded skills"
            ));
        }
        loaded.insert(skill_name.clone());
    }

    let agent_id = normalize_agent_id(agent_id);
    let registry = registry(files_dir, &agent_id).await;
    let available = registry.skills_for_user(&agent_id);
    let Some(skill) = available
        .iter()
        .find(|skill| skill.name().eq_ignore_ascii_case(&skill_name))
    else {
        return Err(format!(
            "skill_load could not find installed skill '{skill_name}'"
        ));
    };
    if let Some(expected_hash) = catalog_skill_hashes.get(&skill_name.to_lowercase())
        && expected_hash != &skill.content_hash
    {
        return Err(format!(
            "skill_load refused to load '{skill_name}' because the skill changed after the current catalog snapshot"
        ));
    }
    record_skill_use(files_dir, &agent_id, skill.name()).await;
    record_session_skill_load(files_dir, thread_id, &agent_id, skill).await;
    let info = activated_skill_info(skill, "loaded");
    Ok(InternalToolResult {
        output: format!(
            "<skills>\n{}</skills>",
            loaded_skill_prompt(skill, response_language)
        ),
        events: vec![crate::types::ChatEvent::SkillActivated {
            agent_id,
            skills: vec![info],
        }],
    })
}
