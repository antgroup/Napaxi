//! Napaxi-owned skill management tools for the mobile runtime.

use tokio::fs;

use serde_json::json;

use crate::tool_registry::ToolDescriptor;

const SKILL_LIST: &str = "skill_list";
const SKILL_SEARCH: &str = "skill_search";
const SKILL_INSTALL: &str = "skill_install";
const SKILL_REMOVE: &str = "skill_remove";
const SKILL_INFO: &str = "skill_info";

pub fn descriptors() -> Vec<ToolDescriptor> {
    vec![
        ToolDescriptor {
            name: SKILL_LIST.to_string(),
            description: "List loaded skills with trust level, source, activation keywords, and optional verbose metadata.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "verbose": {
                        "type": "boolean",
                        "description": "Include full prompt content and content hash when true.",
                        "default": false
                    }
                }
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
        ToolDescriptor {
            name: SKILL_SEARCH.to_string(),
            description: "Search available skills in the catalog and locally installed skills.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query, skill name, keyword, tag, or description fragment."
                    }
                },
                "required": ["query"]
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
        ToolDescriptor {
            name: SKILL_INSTALL.to_string(),
            description: "Install a skill from raw SKILL.md content, a local ZIP package path, an HTTPS URL, or a catalog slug/name returned by skill_search. Local ZIP packages preserve bundled support files such as scripts, assets, templates, and references.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Catalog slug/name to install when content and url are omitted."
                    },
                    "url": {
                        "type": "string",
                        "description": "HTTPS URL to a SKILL.md or ZIP package."
                    },
                    "zip_path": {
                        "type": "string",
                        "description": "Local ZIP package path to install. Prefer sandbox paths such as /workspace/my-skill.zip; absolute local paths are also accepted."
                    },
                    "content": {
                        "type": "string",
                        "description": "Raw SKILL.md content to install directly."
                    }
                }
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        },
        ToolDescriptor {
            name: SKILL_REMOVE.to_string(),
            description: "Remove an installed skill by name.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Installed skill name to remove."
                    }
                },
                "required": ["name"]
            }),
            effect: crate::tool_registry::ToolEffect::Write,
        },
        ToolDescriptor {
            name: SKILL_INFO.to_string(),
            description: "Read detailed metadata and prompt content for a loaded skill by name.".to_string(),
            parameters: json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Loaded skill name."
                    }
                },
                "required": ["name"]
            }),
            effect: crate::tool_registry::ToolEffect::Read,
        },
    ]
}

pub fn is_skill_tool(name: &str) -> bool {
    matches!(
        name,
        SKILL_LIST | SKILL_SEARCH | SKILL_INSTALL | SKILL_REMOVE | SKILL_INFO
    )
}

pub async fn execute(
    files_dir: &str,
    agent_id: &str,
    tool_name: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    match tool_name {
        SKILL_LIST => skill_list(files_dir, agent_id, params).await,
        SKILL_SEARCH => skill_search(files_dir, agent_id, params).await,
        SKILL_INSTALL => skill_install(files_dir, agent_id, params).await,
        SKILL_REMOVE => skill_remove(files_dir, agent_id, params).await,
        SKILL_INFO => skill_info(files_dir, agent_id, params).await,
        _ => Err(format!("Tool not found: {tool_name}")),
    }
}

async fn skill_list(
    files_dir: &str,
    agent_id: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let verbose = params
        .get("verbose")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    let raw = crate::skills::list_skills(files_dir, agent_id).await;
    let skills: serde_json::Value = parse_tool_json(&raw)?;
    if !verbose {
        return Ok(json!({
            "skills": skills,
            "count": skills.as_array().map(Vec::len).unwrap_or(0),
        })
        .to_string());
    }

    let mut detailed = Vec::new();
    if let Some(items) = skills.as_array() {
        for item in items {
            let Some(name) = item.get("name").and_then(serde_json::Value::as_str) else {
                continue;
            };
            let raw = crate::skills::get_skill(files_dir, agent_id, name).await;
            if let Ok(skill) = serde_json::from_str::<serde_json::Value>(&raw) {
                detailed.push(skill);
            }
        }
    }

    Ok(json!({
        "skills": detailed,
        "count": detailed.len(),
    })
    .to_string())
}

async fn skill_search(
    files_dir: &str,
    agent_id: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let query = require_str(&params, "query")?;
    let catalog = crate::skills::search_catalog(query).await;
    let catalog_json = serde_json::from_str::<serde_json::Value>(&catalog)
        .unwrap_or_else(|_| json!({ "raw": catalog }));

    let local_raw = crate::skills::list_skills(files_dir, agent_id).await;
    let query_lower = query.to_ascii_lowercase();
    let local_matches = serde_json::from_str::<serde_json::Value>(&local_raw)
        .ok()
        .and_then(|value| value.as_array().cloned())
        .unwrap_or_default()
        .into_iter()
        .filter(|skill| {
            ["name", "description", "trust", "source"]
                .iter()
                .any(|key| value_contains(skill.get(*key), &query_lower))
                || skill
                    .get("keywords")
                    .and_then(serde_json::Value::as_array)
                    .map(|items| {
                        items
                            .iter()
                            .any(|item| value_contains(Some(item), &query_lower))
                    })
                    .unwrap_or(false)
                || skill
                    .get("tags")
                    .and_then(serde_json::Value::as_array)
                    .map(|items| {
                        items
                            .iter()
                            .any(|item| value_contains(Some(item), &query_lower))
                    })
                    .unwrap_or(false)
        })
        .collect::<Vec<_>>();

    Ok(json!({
        "catalog": catalog_json,
        "installed": local_matches,
        "installed_count": local_matches.len(),
    })
    .to_string())
}

async fn skill_install(
    files_dir: &str,
    agent_id: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let output = if let Some(content) = params
        .get("content")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        crate::skills::install_skill(files_dir, agent_id, content).await
    } else if let Some(zip_path) = params
        .get("zip_path")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let real_path = resolve_local_skill_package_path(files_dir, zip_path)?;
        let bytes = fs::read(&real_path)
            .await
            .map_err(|e| format!("read {}: {e}", real_path.display()))?;
        crate::skills::install_from_zip_bytes(files_dir, agent_id, &bytes).await
    } else if let Some(url) = params
        .get("url")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        crate::skills::install_from_url(files_dir, agent_id, url).await
    } else {
        let name = require_str(&params, "name")?;
        crate::skills::install_from_catalog(files_dir, agent_id, name).await
    };
    parse_error_or_ok(output)
}

fn resolve_local_skill_package_path(
    files_dir: &str,
    zip_path: &str,
) -> Result<std::path::PathBuf, String> {
    if zip_path.starts_with('/') {
        if let Some(real) = crate::storage::sandbox_to_real(files_dir, zip_path) {
            return Ok(std::path::PathBuf::from(real));
        }
        return Ok(std::path::PathBuf::from(zip_path));
    }

    Err(
        "zip_path must be an absolute local path or sandbox path like /workspace/my-skill.zip"
            .to_string(),
    )
}

async fn skill_remove(
    files_dir: &str,
    agent_id: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let name = require_str(&params, "name")?;
    if crate::skills::remove_skill(files_dir, agent_id, name).await {
        Ok(json!({
            "name": name,
            "status": "removed",
        })
        .to_string())
    } else {
        Err(format!("failed to remove skill '{name}'"))
    }
}

async fn skill_info(
    files_dir: &str,
    agent_id: &str,
    params: serde_json::Value,
) -> Result<String, String> {
    let name = require_str(&params, "name")?;
    let output = crate::skills::get_skill(files_dir, agent_id, name).await;
    if output == "null" {
        Err(format!("skill '{name}' not found"))
    } else {
        Ok(output)
    }
}

fn require_str<'a>(params: &'a serde_json::Value, key: &str) -> Result<&'a str, String> {
    params
        .get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{key} is required"))
}

fn value_contains(value: Option<&serde_json::Value>, needle: &str) -> bool {
    value
        .and_then(serde_json::Value::as_str)
        .map(|value| value.to_ascii_lowercase().contains(needle))
        .unwrap_or(false)
}

fn parse_error_or_ok(output: String) -> Result<String, String> {
    let value = parse_tool_json(&output)?;
    if let Some(error) = value.get("error").and_then(serde_json::Value::as_str) {
        Err(error.to_string())
    } else {
        Ok(value.to_string())
    }
}

fn parse_tool_json(output: &str) -> Result<serde_json::Value, String> {
    serde_json::from_str(output).map_err(|e| format!("invalid tool JSON: {e}; raw={output}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    const SKILL: &str = r#"---
name: demo-skill
version: 1.0.0
description: Demo skill
activation:
  keywords: [demo]
---

Use this skill for demos.
"#;

    fn zip_skill_fixture(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut cursor = std::io::Cursor::new(Vec::new());
        {
            let mut writer = zip::ZipWriter::new(&mut cursor);
            let options: zip::write::FileOptions<'_, ()> = zip::write::FileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            for (name, bytes) in entries {
                writer.start_file(*name, options).unwrap();
                writer.write_all(bytes).unwrap();
            }
            writer.finish().unwrap();
        }
        cursor.into_inner()
    }

    #[tokio::test]
    async fn skill_tools_install_list_info_remove() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();

        let installed = execute(files_dir, "", SKILL_INSTALL, json!({"content": SKILL}))
            .await
            .unwrap();
        assert!(installed.contains("demo-skill"));

        let list = execute(files_dir, "", SKILL_LIST, json!({})).await.unwrap();
        assert!(list.contains("demo-skill"));

        let info = execute(files_dir, "", SKILL_INFO, json!({"name":"demo-skill"}))
            .await
            .unwrap();
        assert!(info.contains("Use this skill"));

        let removed = execute(files_dir, "", SKILL_REMOVE, json!({"name":"demo-skill"}))
            .await
            .unwrap();
        assert!(removed.contains("removed"));
    }

    #[tokio::test]
    async fn skill_tool_installs_local_zip_with_support_files() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();
        let workspace_dir = tmp.path().join("linux-env").join("workspace");
        std::fs::create_dir_all(&workspace_dir).unwrap();
        let zip_path = workspace_dir.join("demo-skill.zip");
        let bytes = zip_skill_fixture(&[
            ("SKILL.md", SKILL.as_bytes()),
            ("scripts/helper.py", b"print('hi')\n"),
            ("assets/info.txt", b"extra resource"),
        ]);
        std::fs::write(&zip_path, bytes).unwrap();

        let installed = execute(
            files_dir,
            "",
            SKILL_INSTALL,
            json!({"zip_path": "/workspace/demo-skill.zip"}),
        )
        .await
        .unwrap();
        assert!(installed.contains("demo-skill"));

        assert_eq!(
            tokio::fs::read_to_string(
                tmp.path()
                    .join("agent_runtime/skills/agents/napaxi/demo-skill/scripts/helper.py")
            )
            .await
            .unwrap(),
            "print('hi')\n"
        );
        assert_eq!(
            tokio::fs::read_to_string(
                tmp.path()
                    .join("agent_runtime/skills/agents/napaxi/demo-skill/assets/info.txt")
            )
            .await
            .unwrap(),
            "extra resource"
        );
    }
}
