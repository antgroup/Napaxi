//! Agent-facing tools for the evolution subsystem.
//!
//! Exposes the review/skill/memory tools the agent calls to inspect and queue
//! self-improvement actions (skill and memory reviews) into the pending queue.

#[cfg(feature = "registry")]
use crate::error::{EvolutionError, EvolutionResult};
use crate::queue::{PendingConfirmation, PendingQueue};
use crate::traits::{Tool, ToolError};
use crate::types::{MemoryEntryType, PendingActionType, ReviewSource, ReviewType};
use async_trait::async_trait;
use chrono::Utc;
use schemars::JsonSchema;
use serde::{Deserialize, Deserializer, Serialize};
use std::sync::Arc;

/// Deserialize boolean, treating null as false
fn deserialize_bool_or_null<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    let opt: Option<bool> = Option::deserialize(deserializer)?;
    Ok(opt.unwrap_or(false))
}

// ==================== review_skill tool ====================

/// review_skill tool input
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ReviewSkillInput {
    /// Action type: create, edit, patch, delete, write_file, remove_file
    pub action: String,
    /// Skill name
    pub name: String,
    /// Full content (for create/edit)
    pub content: Option<String>,
    /// Patch parameters
    pub old_string: Option<String>,
    pub new_string: Option<String>,
    /// File path (for write_file/remove_file/patch)
    pub file_path: Option<String>,
    /// Whether patch replaces all matches
    #[serde(default, deserialize_with = "deserialize_bool_or_null")]
    pub replace_all: bool,
    /// Absorbed into umbrella skill (for consolidation delete/archive)
    pub absorbed_into: Option<String>,
    /// Category (for create)
    pub category: Option<String>,
    /// Review reasoning
    pub reasoning: Option<String>,
    /// Confidence: high, medium, low
    #[serde(default)]
    pub confidence: Option<String>,
}

/// ReviewSkill tool
pub struct ReviewSkillTool {
    pending_queue: Arc<PendingQueue>,
    thread_id: String,
}

impl ReviewSkillTool {
    pub fn new(pending_queue: Arc<PendingQueue>, thread_id: String) -> Self {
        Self {
            pending_queue,
            thread_id,
        }
    }
}

#[async_trait]
impl Tool for ReviewSkillTool {
    type Input = ReviewSkillInput;
    type Output = serde_json::Value;

    async fn execute(&self, input: Self::Input) -> Result<Self::Output, ToolError> {
        // Parse action
        let action = self.parse_action(&input)?;

        // Create confirmation item
        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "evolution".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Skill,
            },
            input
                .reasoning
                .unwrap_or_else(|| "Review agent suggestion".to_string()),
            self.thread_id.clone(),
        );

        let id = self.pending_queue.push(confirmation).await;

        Ok(serde_json::json!({
            "success": true,
            "queued": true,
            "confirmation_id": id.to_string(),
        }))
    }

    fn name() -> &'static str {
        "review_skill"
    }

    fn description() -> &'static str {
        r#"Review and propose skill creation or modification.
Actions: create, edit, patch, delete, write_file, remove_file.
All operations require user confirmation."#
    }
}

impl ReviewSkillTool {
    fn parse_action(&self, input: &ReviewSkillInput) -> Result<PendingActionType, ToolError> {
        match input.action.as_str() {
            "create" => Ok(PendingActionType::Create {
                skill_name: input.name.clone(),
                content: input.content.clone().ok_or_else(|| {
                    ToolError::InvalidInput("content required for create".to_string())
                })?,
                category: input.category.clone(),
            }),

            "edit" => Ok(PendingActionType::Edit {
                skill_name: input.name.clone(),
                new_content: input.content.clone().ok_or_else(|| {
                    ToolError::InvalidInput("content required for edit".to_string())
                })?,
            }),

            "patch" => Ok(PendingActionType::Patch {
                skill_name: input.name.clone(),
                old_string: input.old_string.clone().ok_or_else(|| {
                    ToolError::InvalidInput("old_string required for patch".to_string())
                })?,
                new_string: input.new_string.clone().ok_or_else(|| {
                    ToolError::InvalidInput("new_string required for patch".to_string())
                })?,
                file_path: input.file_path.clone(),
                replace_all: input.replace_all,
            }),

            "delete" => Ok(PendingActionType::Delete {
                skill_name: input.name.clone(),
                absorbed_into: input.absorbed_into.clone(),
            }),

            "write_file" => Ok(PendingActionType::WriteFile {
                skill_name: input.name.clone(),
                file_path: input.file_path.clone().ok_or_else(|| {
                    ToolError::InvalidInput("file_path required for write_file".to_string())
                })?,
                file_content: input.content.clone().ok_or_else(|| {
                    ToolError::InvalidInput("content required for write_file".to_string())
                })?,
            }),

            "remove_file" => Ok(PendingActionType::RemoveFile {
                skill_name: input.name.clone(),
                file_path: input.file_path.clone().ok_or_else(|| {
                    ToolError::InvalidInput("file_path required for remove_file".to_string())
                })?,
            }),

            _ => Err(ToolError::InvalidInput(format!(
                "Unknown action: {}",
                input.action
            ))),
        }
    }
}

// ==================== review_memory tool ====================

/// review_memory tool input
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ReviewMemoryInput {
    /// Memory type: environment, user_profile, project
    pub entry_type: MemoryEntryType,
    /// Memory content
    pub content: String,
    /// Review reasoning
    pub reasoning: Option<String>,
    /// Confidence: high, medium, low
    #[serde(default)]
    pub confidence: Option<String>,
}

/// ReviewMemory tool
pub struct ReviewMemoryTool {
    pending_queue: Arc<PendingQueue>,
    thread_id: String,
}

impl ReviewMemoryTool {
    pub fn new(pending_queue: Arc<PendingQueue>, thread_id: String) -> Self {
        Self {
            pending_queue,
            thread_id,
        }
    }
}

#[async_trait]
impl Tool for ReviewMemoryTool {
    type Input = ReviewMemoryInput;
    type Output = serde_json::Value;

    async fn execute(&self, input: Self::Input) -> Result<Self::Output, ToolError> {
        let action = PendingActionType::MemoryWrite {
            entry_type: input.entry_type,
            content: input.content,
        };

        let confirmation = PendingConfirmation::new(
            action,
            ReviewSource {
                job_id: "evolution".to_string(),
                triggered_at: Utc::now(),
                review_type: ReviewType::Memory,
            },
            input
                .reasoning
                .unwrap_or_else(|| "Review agent suggestion".to_string()),
            self.thread_id.clone(),
        );

        let id = self.pending_queue.push(confirmation).await;

        Ok(serde_json::json!({
            "success": true,
            "queued": true,
            "confirmation_id": id.to_string(),
        }))
    }

    fn name() -> &'static str {
        "review_memory"
    }

    fn description() -> &'static str {
        "Review and propose memory write. Requires user confirmation."
    }
}

// ==================== skill_list tool (read-only) ====================

/// skill_list tool input
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SkillListInput {
    /// Optional filter
    pub filter: Option<String>,
}

/// SkillList tool (read-only)
pub struct SkillListTool {
    user_id: String,
}

impl SkillListTool {
    pub fn new(user_id: impl Into<String>) -> Self {
        Self {
            user_id: user_id.into(),
        }
    }

    pub fn new_read_only(user_id: impl Into<String>) -> Self {
        Self::new(user_id)
    }
}

#[async_trait]
impl Tool for SkillListTool {
    type Input = SkillListInput;
    type Output = serde_json::Value;

    async fn execute(&self, input: Self::Input) -> Result<Self::Output, ToolError> {
        // List skills from user-isolated skills directory
        let skills_base = crate::get_user_skills_dir(&self.user_id);

        let mut skills = Vec::new();

        if let Ok(mut entries) = tokio::fs::read_dir(&skills_base).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                if let Ok(metadata) = entry.metadata().await {
                    if metadata.is_dir() {
                        let skill_file = entry.path().join(crate::types::SKILL_FILE_NAME);
                        if skill_file.exists() {
                            // Read skill name (from directory name or SKILL.md frontmatter)
                            let name = entry.file_name().to_string_lossy().to_string();

                            // Optionally read SKILL.md to get description
                            let description =
                                if let Ok(content) = tokio::fs::read_to_string(&skill_file).await {
                                    // Simple frontmatter parsing to get description
                                    content
                                        .lines()
                                        .find(|l| l.trim().starts_with("description:"))
                                        .map(|l| {
                                            l.split_once(':')
                                                .map(|x| x.1)
                                                .unwrap_or("")
                                                .trim()
                                                .to_string()
                                        })
                                        .unwrap_or_else(|| "No description".to_string())
                                } else {
                                    "No description".to_string()
                                };

                            // Apply filter
                            if let Some(ref filter) = input.filter {
                                if name.contains(filter) || description.contains(filter) {
                                    skills.push(serde_json::json!({
                                        "name": name,
                                        "description": description,
                                    }));
                                }
                            } else {
                                skills.push(serde_json::json!({
                                    "name": name,
                                    "description": description,
                                }));
                            }
                        }
                    }
                }
            }
        }

        Ok(serde_json::json!({
            "skills": skills,
            "count": skills.len(),
        }))
    }

    fn name() -> &'static str {
        "skill_list"
    }

    fn description() -> &'static str {
        "List all user-defined skills. Read-only."
    }
}

// ==================== Action executor ====================

/// Action executor for executing confirmed actions
#[cfg(feature = "registry")]
pub struct ActionExecutor {
    user_id: String,
}

#[cfg(feature = "registry")]
impl ActionExecutor {
    pub fn new(user_id: impl Into<String>) -> Self {
        Self {
            user_id: user_id.into(),
        }
    }

    /// Execute pending action
    pub async fn execute(
        &self,
        action: &PendingActionType,
        registry: &std::sync::Arc<napaxi_skills::registry::SkillRegistry>,
    ) -> EvolutionResult<crate::types::ActionResult> {
        use crate::types::PendingActionType::*;

        match action {
            Create {
                skill_name,
                content,
                category: _,
            } => self.create_skill(skill_name, content, registry).await,

            Edit {
                skill_name,
                new_content,
            } => self.edit_skill(skill_name, new_content).await,

            Patch {
                skill_name,
                old_string,
                new_string,
                file_path,
                replace_all,
            } => {
                self.patch_skill(
                    skill_name,
                    old_string,
                    new_string,
                    file_path.as_deref(),
                    *replace_all,
                )
                .await
            }

            Delete { skill_name, .. } => self.delete_skill(skill_name).await,

            WriteFile {
                skill_name,
                file_path,
                file_content,
            } => {
                self.write_skill_file(skill_name, file_path, file_content)
                    .await
            }

            RemoveFile {
                skill_name,
                file_path,
            } => self.remove_skill_file(skill_name, file_path).await,

            MemoryWrite {
                entry_type,
                content,
            } => self.write_memory(*entry_type, content).await,
        }
    }

    async fn create_skill(
        &self,
        skill_name: &str,
        content: &str,
        registry: &std::sync::Arc<napaxi_skills::registry::SkillRegistry>,
    ) -> EvolutionResult<crate::types::ActionResult> {
        use napaxi_skills::registry::SkillRegistry;

        // 1. Validate name (using napaxi_skills validation rules)
        if !crate::validate_skill_name(skill_name) {
            return Err(EvolutionError::InvalidSkillName(
                "skill name must be 1-64 alphanumeric characters, starting with alphanumeric"
                    .to_string(),
            ));
        }

        // 2. Normalize content
        let normalized = napaxi_skills::normalize_line_endings(content);
        let (name_from_parse, install_content) =
            SkillRegistry::resolve_install_content(&normalized, Some(skill_name))
                .map_err(|e| EvolutionError::InvalidFrontmatter(e.to_string()))?;

        // 3. Check if already exists (under same user)
        if registry.has_owned(&name_from_parse, &self.user_id) {
            return Err(EvolutionError::SkillAlreadyExists(name_from_parse));
        }

        // 4. Use napaxi standard skill_install method to write to disk and load
        let user_dir = registry.install_target_dir().to_path_buf();
        let (name, mut skill) = SkillRegistry::prepare_install_to_disk(
            &user_dir,
            &name_from_parse,
            &install_content,
            &self.user_id,
        )
        .await
        .map_err(|e| EvolutionError::Io(std::io::Error::other(e.to_string())))?;

        // 5. Commit to registry
        skill.owner_user_id = self.user_id.clone();
        registry
            .commit_install(&name, skill)
            .map_err(|e| EvolutionError::Io(std::io::Error::other(e.to_string())))?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("Skill '{}' installed", name),
        })
    }

    async fn edit_skill(
        &self,
        skill_name: &str,
        new_content: &str,
    ) -> EvolutionResult<crate::types::ActionResult> {
        // 1. Validate frontmatter
        Self::validate_frontmatter(new_content)?;

        // 2. Check if exists
        let skill_dir = self.get_skill_dir(skill_name);
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        // 3. Write new content
        let skill_md = skill_dir.join(crate::types::SKILL_FILE_NAME);
        Self::edit_skill_at_path(&skill_md, new_content).await
    }

    /// Edit skill at a specific path
    async fn edit_skill_at_path(
        skill_path: &std::path::Path,
        new_content: &str,
    ) -> EvolutionResult<crate::types::ActionResult> {
        // Validate frontmatter
        Self::validate_frontmatter(new_content)?;

        crate::io::atomic_write_text(skill_path, new_content).await?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: "Skill updated".to_string(),
        })
    }

    async fn patch_skill(
        &self,
        skill_name: &str,
        old_string: &str,
        new_string: &str,
        file_path: Option<&str>,
        replace_all: bool,
    ) -> EvolutionResult<crate::types::ActionResult> {
        let skill_dir = self.get_skill_dir(skill_name);
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        // Determine target file
        let target = if let Some(fp) = file_path {
            skill_dir.join(fp)
        } else {
            skill_dir.join(crate::types::SKILL_FILE_NAME)
        };

        Self::patch_skill_at_path(&target, old_string, new_string, replace_all).await
    }

    /// Patch skill at a specific path
    async fn patch_skill_at_path(
        target: &std::path::Path,
        old_string: &str,
        new_string: &str,
        replace_all: bool,
    ) -> EvolutionResult<crate::types::ActionResult> {
        // Read content
        let content = tokio::fs::read_to_string(target)
            .await
            .map_err(EvolutionError::Io)?;

        // Execute patch
        let (new_content, count, _strategy, _error) =
            crate::fuzzy::fuzzy_find_and_replace(&content, old_string, new_string, replace_all)
                .map_err(|e| EvolutionError::PatchFailed(e.to_string()))?;

        // Write new content
        crate::io::atomic_write_text(target, &new_content).await?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("Patched {} replacements", count),
        })
    }

    async fn delete_skill(&self, skill_name: &str) -> EvolutionResult<crate::types::ActionResult> {
        let skill_dir = self.get_skill_dir(skill_name);
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        tokio::fs::remove_dir_all(&skill_dir)
            .await
            .map_err(EvolutionError::Io)?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("Skill '{}' deleted", skill_name),
        })
    }

    async fn write_skill_file(
        &self,
        skill_name: &str,
        file_path: &str,
        file_content: &str,
    ) -> EvolutionResult<crate::types::ActionResult> {
        let skill_dir = self.get_skill_dir(skill_name);
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        let target = skill_dir.join(file_path);
        crate::io::atomic_write_text(&target, file_content).await?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("File {} written for {}", file_path, skill_name),
        })
    }

    async fn remove_skill_file(
        &self,
        skill_name: &str,
        file_path: &str,
    ) -> EvolutionResult<crate::types::ActionResult> {
        let skill_dir = self.get_skill_dir(skill_name);
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        let target = skill_dir.join(file_path);
        tokio::fs::remove_file(&target)
            .await
            .map_err(EvolutionError::Io)?;

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("File {} removed from {}", file_path, skill_name),
        })
    }

    async fn write_memory(
        &self,
        entry_type: MemoryEntryType,
        content: &str,
    ) -> EvolutionResult<crate::types::ActionResult> {
        // Determine write path based on entry_type and user ID
        let memory_dir = crate::get_user_memory_dir(&self.user_id);

        // Ensure user memory directory exists
        tokio::fs::create_dir_all(&memory_dir)
            .await
            .map_err(EvolutionError::Io)?;

        let memory_path = match entry_type {
            MemoryEntryType::Environment => memory_dir.join("MEMORY.md"),
            MemoryEntryType::UserProfile => memory_dir.join("USER.md"),
            MemoryEntryType::Project => memory_dir.join("PROJECT.md"),
        };

        // Read existing content (if exists)
        let existing_content = tokio::fs::read_to_string(&memory_path)
            .await
            .unwrap_or_default(); // Use empty content if file doesn't exist

        // Append new content (with timestamp and category marker)
        let timestamp = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S");
        let entry_type_str = match entry_type {
            MemoryEntryType::Environment => "Environment",
            MemoryEntryType::UserProfile => "User",
            MemoryEntryType::Project => "Project",
        };

        let new_content = if existing_content.is_empty() {
            format!(
                "# {} Memory\n\n## {}\n\n{}",
                entry_type_str, timestamp, content
            )
        } else {
            format!("{}\n\n## {}\n\n{}", existing_content, timestamp, content)
        };

        // Atomic write
        crate::io::atomic_write_text(&memory_path, &new_content).await?;

        let type_name = match entry_type {
            MemoryEntryType::Environment => "environment",
            MemoryEntryType::UserProfile => "user_profile",
            MemoryEntryType::Project => "project",
        };

        Ok(crate::types::ActionResult {
            success: true,
            executed: true,
            message: format!("Memory written to {}", type_name),
        })
    }

    fn validate_frontmatter(content: &str) -> EvolutionResult<()> {
        // Validate YAML frontmatter format
        let parts: Vec<&str> = content.splitn(3, "---").collect();
        if parts.len() < 3 || !parts[0].trim().is_empty() {
            return Err(EvolutionError::InvalidFrontmatter(
                "Missing or invalid YAML frontmatter".to_string(),
            ));
        }

        // Parse YAML
        let yaml: serde_yaml::Value = serde_yaml::from_str(parts[1])
            .map_err(|e| EvolutionError::InvalidFrontmatter(e.to_string()))?;

        // Validate required fields
        if yaml.get("name").is_none() {
            return Err(EvolutionError::InvalidFrontmatter(
                "Missing 'name' in frontmatter".to_string(),
            ));
        }

        if yaml.get("description").is_none() {
            return Err(EvolutionError::InvalidFrontmatter(
                "Missing 'description' in frontmatter".to_string(),
            ));
        }

        Ok(())
    }

    fn get_skill_dir(&self, skill_name: &str) -> std::path::PathBuf {
        crate::get_user_skills_dir(&self.user_id).join(skill_name)
    }
}

#[cfg(feature = "registry")]
impl Default for ActionExecutor {
    fn default() -> Self {
        Self::new("default")
    }
}

#[cfg(test)]
mod tests;