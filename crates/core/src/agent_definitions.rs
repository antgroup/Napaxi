//! Agent Definition Store — user-defined agent persistence and AGENT.md parsing.
//!
//! Follows the satellite store pattern (like `LibSqlSecretsStore`): manages its
//! own `agent_definitions` table independently of napaxi's migration system.

use serde::{Deserialize, Deserializer, Serialize};
use uuid::Uuid;

// ============================================================================
// Data model
// ============================================================================

/// How to filter the tools available to an agent.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", content = "tools")]
#[derive(Default)]
pub enum ToolFilter {
    /// No filtering — agent can use all registered tools.
    #[default]
    AllTools,
    /// Agent can *only* use the listed tools.
    Allowlist(Vec<String>),
    /// Agent can use all tools *except* the listed ones.
    Denylist(Vec<String>),
}

/// Where the agent definition originated.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum AgentSource {
    /// Hardcoded in the app.
    Predefined,
    /// Created via the UI form.
    #[default]
    UserCreated,
    /// Imported from an AGENT.md file.
    AgentMd,
}

impl std::fmt::Display for AgentSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Predefined => write!(f, "predefined"),
            Self::UserCreated => write!(f, "user_created"),
            Self::AgentMd => write!(f, "agent_md"),
        }
    }
}

impl std::str::FromStr for AgentSource {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "predefined" => Ok(Self::Predefined),
            "user_created" => Ok(Self::UserCreated),
            "agent_md" => Ok(Self::AgentMd),
            other => Err(format!("unknown agent source: {other}")),
        }
    }
}

/// A user-defined (or predefined) agent definition persisted to the database.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDefinition {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub icon: Option<String>,
    #[serde(default, deserialize_with = "deserialize_null_string")]
    pub provider: String,
    #[serde(default, deserialize_with = "deserialize_null_string")]
    pub model: String,
    #[serde(default, deserialize_with = "deserialize_null_string")]
    pub model_profile_id: String,
    #[serde(
        default = "default_agent_engine_id",
        deserialize_with = "deserialize_null_string"
    )]
    pub engine_id: String,
    #[serde(default, deserialize_with = "deserialize_null_string")]
    pub engine_profile_id: String,
    #[serde(default)]
    pub engine_config: serde_json::Value,
    #[serde(default)]
    pub system_prompt: String,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: i32,
    #[serde(default)]
    pub tool_filter: ToolFilter,
    #[serde(default)]
    pub source: AgentSource,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub updated_at: String,
}

fn deserialize_null_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(Option::<String>::deserialize(deserializer)?.unwrap_or_default())
}

fn default_provider() -> String {
    "anthropic".to_string()
}
pub(crate) fn default_agent_engine_id() -> String {
    "napaxi_core".to_string()
}
fn default_max_tokens() -> i32 {
    40960
}

impl AgentDefinition {
    /// Create a new definition with a generated UUID and timestamps.
    pub fn new(name: String, model: String) -> Self {
        let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
        Self {
            id: Uuid::new_v4().to_string(),
            name,
            description: String::new(),
            icon: None,
            provider: default_provider(),
            model,
            model_profile_id: String::new(),
            engine_id: default_agent_engine_id(),
            engine_profile_id: String::new(),
            engine_config: serde_json::json!({}),
            system_prompt: String::new(),
            max_tokens: default_max_tokens(),
            tool_filter: ToolFilter::default(),
            source: AgentSource::UserCreated,
            created_at: now.clone(),
            updated_at: now,
        }
    }
}

// ============================================================================
// AGENT.md parser
// ============================================================================

/// Error type for AGENT.md parsing failures.
#[derive(Debug, thiserror::Error)]
#[allow(dead_code)] // Public error surface; variants used by SDK consumers.
pub enum AgentMdParseError {
    #[error("Missing YAML frontmatter delimiters (expected `---` at start of file)")]
    MissingFrontmatter,

    #[error("Invalid YAML frontmatter: {0}")]
    InvalidYaml(String),

    #[error("Prompt body is empty (no content after frontmatter)")]
    EmptyPrompt,

    #[error("Missing required field: {0}")]
    MissingField(String),
}

/// YAML frontmatter schema for AGENT.md files.
#[derive(Debug, Deserialize)]
struct AgentMdFrontmatter {
    name: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    icon: Option<String>,
    #[serde(default = "default_provider")]
    provider: String,
    #[serde(default)]
    model: Option<String>,
    #[serde(default = "default_max_tokens")]
    max_tokens: i32,
    #[serde(default = "default_agent_engine_id")]
    engine_id: String,
    #[serde(default)]
    engine_profile_id: String,
    #[serde(default)]
    engine_config: serde_json::Value,
    #[serde(default)]
    tool_filter: Option<ToolFilter>,
}

/// Parse an AGENT.md file into an `AgentDefinition`.
///
/// Format:
/// ```text
/// ---
/// name: my-agent
/// description: An example agent
/// provider: anthropic
/// model: claude-sonnet-4-6
/// tool_filter:
///   type: Allowlist
///   tools: [read_file, http]
/// ---
///
/// You are an expert assistant that...
/// ```
pub fn parse_agent_md(content: &str) -> Result<AgentDefinition, AgentMdParseError> {
    // Strip optional UTF-8 BOM
    let content = content.strip_prefix('\u{feff}').unwrap_or(content);

    // Find first `---`
    let trimmed = content.trim_start_matches(['\n', '\r']);
    if !trimmed.starts_with("---") {
        return Err(AgentMdParseError::MissingFrontmatter);
    }

    let after_first = &trimmed[3..];
    let after_first_line = match after_first.find('\n') {
        Some(pos) => &after_first[pos + 1..],
        None => return Err(AgentMdParseError::MissingFrontmatter),
    };

    // Find closing `---`
    let yaml_end =
        find_closing_delimiter(after_first_line).ok_or(AgentMdParseError::MissingFrontmatter)?;

    let yaml_str = &after_first_line[..yaml_end];

    let fm: AgentMdFrontmatter =
        yaml_serde::from_str(yaml_str).map_err(|e| AgentMdParseError::InvalidYaml(e.to_string()))?;

    // Extract prompt content (markdown body after frontmatter)
    let after_yaml = &after_first_line[yaml_end..];
    let prompt_start = after_yaml
        .find('\n')
        .map(|p| p + 1)
        .unwrap_or(after_yaml.len());
    let system_prompt = after_yaml[prompt_start..]
        .trim_start_matches('\n')
        .to_string();

    if system_prompt.trim().is_empty() {
        return Err(AgentMdParseError::EmptyPrompt);
    }

    let model = fm.model.unwrap_or_else(|| "claude-sonnet-4-6".to_string());

    let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);

    Ok(AgentDefinition {
        id: Uuid::new_v4().to_string(),
        name: fm.name,
        description: fm.description.unwrap_or_default(),
        icon: fm.icon,
        provider: fm.provider,
        model,
        model_profile_id: String::new(),
        engine_id: fm.engine_id,
        engine_profile_id: fm.engine_profile_id,
        engine_config: fm.engine_config,
        system_prompt,
        max_tokens: fm.max_tokens,
        tool_filter: fm.tool_filter.unwrap_or_default(),
        source: AgentSource::AgentMd,
        created_at: now.clone(),
        updated_at: now,
    })
}

fn find_closing_delimiter(content: &str) -> Option<usize> {
    let mut pos = 0;
    for line in content.lines() {
        if line.trim() == "---" {
            return Some(pos);
        }
        pos += line.len() + 1;
    }
    None
}

// ============================================================================
// Database store (libSQL satellite store)
// ============================================================================

#[cfg(feature = "libsql")]
#[allow(dead_code)] // Public satellite store surface; reserved for future adapter routing.
pub mod store {
    use super::*;
    use anyhow::{Context, Result};
    use std::sync::Arc;

    /// Satellite store for agent definitions, using the shared libsql database.
    pub struct AgentDefinitionStore {
        db: Arc<libsql::Database>,
    }

    impl AgentDefinitionStore {
        pub fn new(db: Arc<libsql::Database>) -> Self {
            Self { db }
        }

        async fn connect(&self) -> Result<libsql::Connection> {
            let conn = self
                .db
                .connect()
                .context("AgentDefinitionStore: connection failed")?;
            conn.query("PRAGMA busy_timeout = 5000", ())
                .await
                .context("AgentDefinitionStore: failed to set busy_timeout")?;
            Ok(conn)
        }

        /// Create the `agent_definitions` table if it doesn't exist.
        pub async fn ensure_table(&self) -> Result<()> {
            let conn = self.connect().await?;
            conn.execute(
                r#"
                CREATE TABLE IF NOT EXISTS agent_definitions (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    icon TEXT,
                    provider TEXT NOT NULL DEFAULT 'anthropic',
                    model TEXT NOT NULL,
                    model_profile_id TEXT NOT NULL DEFAULT '',
                    engine_id TEXT NOT NULL DEFAULT 'napaxi_core',
                    engine_profile_id TEXT NOT NULL DEFAULT '',
                    engine_config TEXT NOT NULL DEFAULT '{}',
                    system_prompt TEXT NOT NULL DEFAULT '',
                    max_tokens INTEGER NOT NULL DEFAULT 40960,
                    tool_filter TEXT NOT NULL DEFAULT '"AllTools"',
                    source TEXT NOT NULL DEFAULT 'user_created',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                "#,
                (),
            )
            .await
            .context("AgentDefinitionStore: failed to create table")?;
            if let Err(e) = conn
                .execute(
                    "ALTER TABLE agent_definitions ADD COLUMN model_profile_id TEXT NOT NULL DEFAULT ''",
                    (),
                )
                .await
            {
                let message = e.to_string().to_lowercase();
                if !message.contains("duplicate column") && !message.contains("already exists") {
                    return Err(e).context("AgentDefinitionStore: failed to add model_profile_id");
                }
            }
            add_text_column(&conn, "engine_id", "'napaxi_core'").await?;
            add_text_column(&conn, "engine_profile_id", "''").await?;
            add_text_column(&conn, "engine_config", "'{}'").await?;
            Ok(())
        }

        /// Insert a new agent definition.
        pub async fn create(&self, def: &AgentDefinition) -> Result<()> {
            let conn = self.connect().await?;
            let tool_filter_json = serde_json::to_string(&def.tool_filter)?;
            let engine_config_json = serde_json::to_string(&def.engine_config)?;
            let icon = def.icon.as_deref().unwrap_or("");
            let source = def.source.to_string();
            conn.execute(
                r#"
                INSERT INTO agent_definitions
                    (id, name, description, icon, provider, model, model_profile_id,
                     engine_id, engine_profile_id, engine_config, system_prompt, max_tokens,
                     tool_filter, source, created_at, updated_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
                "#,
                libsql::params![
                    def.id.as_str(),
                    def.name.as_str(),
                    def.description.as_str(),
                    icon,
                    def.provider.as_str(),
                    def.model.as_str(),
                    def.model_profile_id.as_str(),
                    def.engine_id.as_str(),
                    def.engine_profile_id.as_str(),
                    engine_config_json.as_str(),
                    def.system_prompt.as_str(),
                    def.max_tokens as i64,
                    tool_filter_json.as_str(),
                    source.as_str(),
                    def.created_at.as_str(),
                    def.updated_at.as_str(),
                ],
            )
            .await
            .context("AgentDefinitionStore: insert failed")?;
            Ok(())
        }

        /// Get a single agent definition by ID.
        pub async fn get(&self, id: &str) -> Result<Option<AgentDefinition>> {
            let conn = self.connect().await?;
            let mut rows = conn
                .query(
                    "SELECT id, name, description, icon, provider, model, model_profile_id, \
                     engine_id, engine_profile_id, engine_config, system_prompt, max_tokens, \
                     tool_filter, source, created_at, updated_at \
                     FROM agent_definitions WHERE id = ?1",
                    libsql::params![id.to_string()],
                )
                .await
                .context("AgentDefinitionStore: query failed")?;

            match rows.next().await? {
                Some(row) => Ok(Some(row_to_definition(&row)?)),
                None => Ok(None),
            }
        }

        /// List all agent definitions, ordered by creation time.
        pub async fn list(&self) -> Result<Vec<AgentDefinition>> {
            let conn = self.connect().await?;
            let mut rows = conn
                .query(
                    "SELECT id, name, description, icon, provider, model, model_profile_id, \
                     engine_id, engine_profile_id, engine_config, system_prompt, max_tokens, \
                     tool_filter, source, created_at, updated_at \
                     FROM agent_definitions ORDER BY created_at ASC",
                    (),
                )
                .await
                .context("AgentDefinitionStore: list query failed")?;

            let mut defs = Vec::new();
            while let Some(row) = rows.next().await? {
                defs.push(row_to_definition(&row)?);
            }
            Ok(defs)
        }

        /// Update an existing agent definition (matched by `id`).
        pub async fn update(&self, def: &AgentDefinition) -> Result<()> {
            let conn = self.connect().await?;
            let tool_filter_json = serde_json::to_string(&def.tool_filter)?;
            let engine_config_json = serde_json::to_string(&def.engine_config)?;
            let icon = def.icon.as_deref().unwrap_or("");
            let source = def.source.to_string();
            let now = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
            conn.execute(
                r#"
                UPDATE agent_definitions SET
                    name = ?2,
                    description = ?3,
                    icon = ?4,
                    provider = ?5,
                    model = ?6,
                    model_profile_id = ?7,
                    engine_id = ?8,
                    engine_profile_id = ?9,
                    engine_config = ?10,
                    system_prompt = ?11,
                    max_tokens = ?12,
                    tool_filter = ?13,
                    source = ?14,
                    updated_at = ?15
                WHERE id = ?1
                "#,
                libsql::params![
                    def.id.as_str(),
                    def.name.as_str(),
                    def.description.as_str(),
                    icon,
                    def.provider.as_str(),
                    def.model.as_str(),
                    def.model_profile_id.as_str(),
                    def.engine_id.as_str(),
                    def.engine_profile_id.as_str(),
                    engine_config_json.as_str(),
                    def.system_prompt.as_str(),
                    def.max_tokens as i64,
                    tool_filter_json.as_str(),
                    source.as_str(),
                    now.as_str(),
                ],
            )
            .await
            .context("AgentDefinitionStore: update failed")?;
            Ok(())
        }

        /// Delete an agent definition by ID. Returns `true` if a row was deleted.
        pub async fn delete(&self, id: &str) -> Result<bool> {
            let conn = self.connect().await?;
            let affected = conn
                .execute(
                    "DELETE FROM agent_definitions WHERE id = ?1",
                    libsql::params![id.to_string()],
                )
                .await
                .context("AgentDefinitionStore: delete failed")?;
            Ok(affected > 0)
        }
    }

    fn row_to_definition(row: &libsql::Row) -> Result<AgentDefinition> {
        let icon_str: String = row.get::<String>(3).unwrap_or_default();
        let icon = if icon_str.is_empty() {
            None
        } else {
            Some(icon_str)
        };

        let tool_filter_str: String = row.get(12)?;
        let tool_filter: ToolFilter = serde_json::from_str(&tool_filter_str).unwrap_or_default();

        let source_str: String = row.get(13)?;
        let source: AgentSource = source_str.parse().unwrap_or(AgentSource::UserCreated);
        let engine_config_str: String = row.get(9)?;
        let engine_config =
            serde_json::from_str(&engine_config_str).unwrap_or_else(|_| serde_json::json!({}));

        Ok(AgentDefinition {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            icon,
            provider: row.get(4)?,
            model: row.get(5)?,
            model_profile_id: row.get(6)?,
            engine_id: row.get(7)?,
            engine_profile_id: row.get(8)?,
            engine_config,
            system_prompt: row.get(10)?,
            max_tokens: row.get::<i64>(11)? as i32,
            tool_filter,
            source,
            created_at: row.get(14)?,
            updated_at: row.get(15)?,
        })
    }

    async fn add_text_column(
        conn: &libsql::Connection,
        column: &str,
        default_sql: &str,
    ) -> Result<()> {
        let sql = format!(
            "ALTER TABLE agent_definitions ADD COLUMN {column} TEXT NOT NULL DEFAULT {default_sql}"
        );
        if let Err(e) = conn.execute(&sql, ()).await {
            let message = e.to_string().to_lowercase();
            if !message.contains("duplicate column") && !message.contains("already exists") {
                return Err(e).context(format!("AgentDefinitionStore: failed to add {column}"));
            }
        }
        Ok(())
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_agent_md_full() {
        let content = r#"---
name: code-reviewer
description: Code review assistant
provider: anthropic
model: claude-sonnet-4-6
max_tokens: 8192
tool_filter:
  type: Allowlist
  tools: [read_file, http]
---

You are a professional code review assistant.

## Guidelines
- Focus on code quality and security.
"#;
        let def = parse_agent_md(content).expect("should parse");
        assert_eq!(def.name, "code-reviewer");
        assert_eq!(def.description, "Code review assistant");
        assert_eq!(def.provider, "anthropic");
        assert_eq!(def.model, "claude-sonnet-4-6");
        assert_eq!(def.max_tokens, 8192);
        assert_eq!(
            def.tool_filter,
            ToolFilter::Allowlist(vec!["read_file".into(), "http".into()])
        );
        assert_eq!(def.source, AgentSource::AgentMd);
        assert!(def.system_prompt.starts_with("You are a professional"));
    }

    #[test]
    fn test_parse_agent_md_minimal() {
        let content = "---\nname: minimal\n---\n\nHello world.\n";
        let def = parse_agent_md(content).expect("should parse");
        assert_eq!(def.name, "minimal");
        assert_eq!(def.provider, "anthropic");
        assert_eq!(def.model, "claude-sonnet-4-6");
        assert_eq!(def.tool_filter, ToolFilter::AllTools);
    }

    #[test]
    fn test_parse_agent_md_missing_frontmatter() {
        let err = parse_agent_md("Just text").unwrap_err();
        assert!(matches!(err, AgentMdParseError::MissingFrontmatter));
    }

    #[test]
    fn test_parse_agent_md_empty_body() {
        let err = parse_agent_md("---\nname: empty\n---\n\n   \n").unwrap_err();
        assert!(matches!(err, AgentMdParseError::EmptyPrompt));
    }

    #[test]
    fn test_parse_agent_md_denylist() {
        let content = r#"---
name: safe-agent
tool_filter:
  type: Denylist
  tools: [shell, write_file]
---

A safe agent without dangerous tools.
"#;
        let def = parse_agent_md(content).expect("should parse");
        assert_eq!(
            def.tool_filter,
            ToolFilter::Denylist(vec!["shell".into(), "write_file".into()])
        );
    }

    #[test]
    fn test_tool_filter_serde_roundtrip() {
        let cases = vec![
            ToolFilter::AllTools,
            ToolFilter::Allowlist(vec!["a".into(), "b".into()]),
            ToolFilter::Denylist(vec!["c".into()]),
        ];
        for filter in cases {
            let json = serde_json::to_string(&filter).expect("serialize");
            let back: ToolFilter = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(filter, back);
        }
    }

    #[test]
    fn test_agent_definition_new() {
        let def = AgentDefinition::new("test".into(), "gpt-4".into());
        assert!(!def.id.is_empty());
        assert_eq!(def.name, "test");
        assert_eq!(def.model, "gpt-4");
        assert_eq!(def.source, AgentSource::UserCreated);
    }

    #[test]
    fn test_parse_agent_md_bom() {
        let content = "\u{feff}---\nname: bom\n---\n\nPrompt.\n";
        let def = parse_agent_md(content).expect("should handle BOM");
        assert_eq!(def.name, "bom");
    }
}

#[cfg(all(test, feature = "libsql"))]
mod store_tests {
    use std::sync::Arc;

    use super::store::AgentDefinitionStore;
    use super::*;

    async fn create_test_store() -> (AgentDefinitionStore, tempfile::TempDir) {
        let tmp = tempfile::tempdir().expect("tempdir");
        let path = tmp.path().join("test.db");
        let db = Arc::new(
            libsql::Builder::new_local(path)
                .build()
                .await
                .expect("local db"),
        );
        let store = AgentDefinitionStore::new(db);
        store.ensure_table().await.expect("ensure_table");
        (store, tmp)
    }

    #[tokio::test]
    async fn test_crud() {
        let (store, _tmp) = create_test_store().await;

        // Create
        let mut def = AgentDefinition::new("test-agent".into(), "gpt-4".into());
        def.description = "A test agent".into();
        def.tool_filter = ToolFilter::Allowlist(vec!["echo".into()]);
        store.create(&def).await.expect("create");

        // Get
        let fetched = store.get(&def.id).await.expect("get").expect("found");
        assert_eq!(fetched.name, "test-agent");
        assert_eq!(fetched.description, "A test agent");
        assert_eq!(
            fetched.tool_filter,
            ToolFilter::Allowlist(vec!["echo".into()])
        );

        // List
        let all = store.list().await.expect("list");
        assert_eq!(all.len(), 1);

        // Update
        let mut updated = fetched;
        updated.name = "updated-agent".into();
        updated.tool_filter = ToolFilter::Denylist(vec!["shell".into()]);
        store.update(&updated).await.expect("update");

        let fetched2 = store.get(&def.id).await.expect("get").expect("found");
        assert_eq!(fetched2.name, "updated-agent");
        assert_eq!(
            fetched2.tool_filter,
            ToolFilter::Denylist(vec!["shell".into()])
        );

        // Delete
        let deleted = store.delete(&def.id).await.expect("delete");
        assert!(deleted);
        assert!(store.get(&def.id).await.expect("get").is_none());
    }

    #[tokio::test]
    async fn test_list_ordering() {
        let (store, _tmp) = create_test_store().await;

        let mut a = AgentDefinition::new("agent-a".into(), "m1".into());
        a.created_at = "2024-01-01T00:00:00.000Z".into();
        store.create(&a).await.expect("create a");

        let mut b = AgentDefinition::new("agent-b".into(), "m2".into());
        b.created_at = "2024-01-02T00:00:00.000Z".into();
        store.create(&b).await.expect("create b");

        let all = store.list().await.expect("list");
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].name, "agent-a");
        assert_eq!(all[1].name, "agent-b");
    }

    #[tokio::test]
    async fn test_delete_nonexistent() {
        let (store, _tmp) = create_test_store().await;
        let deleted = store.delete("nonexistent-id").await.expect("delete");
        assert!(!deleted);
    }
}
