//! Skill install, replace, and remove flows for [`SkillRegistry`].
//!
//! Split out of `registry/mod.rs`: the install-content normalization
//! free functions plus the install/remove methods on `SkillRegistry`.
//! Discovery and loading stay in `mod.rs` / `loader.rs`.

use super::*;

// ---- install-content normalization helpers ----

fn parse_error_for_install(error_label: &str, error: SkillParseError) -> SkillRegistryError {
    let reason = error.to_string();
    match error {
        SkillParseError::InvalidName { name } => SkillRegistryError::ParseError { name, reason },
        _ => SkillRegistryError::ParseError {
            name: error_label.to_string(),
            reason,
        },
    }
}

/// Rewrite the `name` field in raw YAML frontmatter while preserving every
/// other key and value in the original mapping.
///
/// We deliberately operate on `serde_norway::Value` instead of the typed
/// `SkillManifest`: re-serializing through the typed struct silently drops
/// any unknown frontmatter fields published upstream (custom metadata, future
/// fields, vendor extensions). The recovery path must be lossless except for
/// the single field we are rewriting.
fn rewrite_frontmatter_name(
    frontmatter: &str,
    new_name: &str,
    error_label: &str,
) -> Result<String, SkillRegistryError> {
    let mut value: serde_norway::Value =
        serde_norway::from_str(frontmatter).map_err(|e| SkillRegistryError::ParseError {
            name: error_label.to_string(),
            reason: format!("Failed to parse SKILL.md frontmatter for rewrite: {}", e),
        })?;

    let mapping = value
        .as_mapping_mut()
        .ok_or_else(|| SkillRegistryError::ParseError {
            name: error_label.to_string(),
            reason: "SKILL.md frontmatter is not a YAML mapping".to_string(),
        })?;

    mapping.insert(
        serde_norway::Value::String("name".to_string()),
        serde_norway::Value::String(new_name.to_string()),
    );

    let yaml = serde_norway::to_string(&value).map_err(|e| SkillRegistryError::ParseError {
        name: error_label.to_string(),
        reason: format!("Failed to rewrite normalized SKILL.md: {}", e),
    })?;

    let yaml = yaml.strip_suffix("...\n").unwrap_or(&yaml);
    let yaml = yaml.strip_suffix("...").unwrap_or(yaml);
    Ok(yaml.to_string())
}

fn assemble_skill_md(yaml: &str, prompt_content: &str) -> String {
    let mut rendered = String::from("---\n");
    rendered.push_str(yaml);
    if !rendered.ends_with('\n') {
        rendered.push('\n');
    }
    rendered.push_str("---\n\n");
    rendered.push_str(prompt_content);
    rendered
}

fn normalize_install_content(
    normalized_content: &str,
    requested_identifier: Option<&str>,
) -> Result<(String, String), SkillRegistryError> {
    match parse_skill_md(normalized_content) {
        Ok(parsed) => Ok((parsed.manifest.name, normalized_content.to_string())),
        Err(SkillParseError::InvalidName { .. }) => {
            // Re-parse the typed manifest only to recover the original name and
            // confirm structural validity; the actual rewrite operates on raw
            // YAML below to preserve any unknown frontmatter fields.
            let parsed = parse_skill_md_for_install_recovery(normalized_content)
                .map_err(|e| parse_error_for_install("(install)", e))?;
            let original_name = parsed.manifest.name.clone();
            let normalized_name = requested_identifier
                .and_then(normalize_skill_identifier)
                .or_else(|| normalize_skill_identifier(&original_name))
                .ok_or_else(|| SkillRegistryError::ParseError {
                    name: original_name.clone(),
                    reason: format!(
                        "Invalid skill name '{}' could not be normalized to a safe install name",
                        original_name
                    ),
                })?;

            tracing::debug!(
                original_name = %original_name,
                normalized_name = %normalized_name,
                requested_identifier = requested_identifier.unwrap_or(""),
                "Normalizing invalid skill name during install"
            );

            let (frontmatter, prompt_content) = split_skill_md_frontmatter(normalized_content)
                .map_err(|e| parse_error_for_install("(install)", e))?;
            let rewritten_yaml =
                rewrite_frontmatter_name(&frontmatter, &normalized_name, &original_name)?;
            let rendered = assemble_skill_md(&rewritten_yaml, &prompt_content);
            Ok((normalized_name, rendered))
        }
        Err(e) => Err(parse_error_for_install("(install)", e)),
    }
}

impl SkillRegistry {
    /// Resolve the on-disk install content and final in-memory skill name.
    ///
    /// Install flows use this to recover from invalid published names (for
    /// example, catalog display names containing spaces) without relaxing the
    /// parser for ordinary local skill discovery.
    pub fn resolve_install_content(
        normalized_content: &str,
        requested_identifier: Option<&str>,
    ) -> Result<(String, String), SkillRegistryError> {
        normalize_install_content(normalized_content, requested_identifier)
    }

    /// Perform the disk I/O and loading for a skill install.
    ///
    /// This is a static method so it doesn't borrow `&self`, allowing callers
    /// to drop their registry lock before awaiting.
    pub async fn prepare_install_to_disk(
        user_dir: &Path,
        skill_name: &str,
        normalized_content: &str,
        user_id: &str,
    ) -> Result<(String, LoadedSkill), SkillRegistryError> {
        let afs = get_afs(user_id)?;

        let skill_dir = user_dir.join(skill_name);
        afs.create_dir_all(&skill_dir)
            .await
            .map_err(|e| SkillRegistryError::WriteError {
                path: skill_dir.display().to_string(),
                reason: e.to_string(),
            })?;

        let skill_path = skill_dir.join("SKILL.md");
        afs.write(&skill_path, normalized_content.as_bytes())
            .await
            .map_err(|e| SkillRegistryError::WriteError {
                path: skill_path.display().to_string(),
                reason: e.to_string(),
            })?;

        // Load by re-reading from disk (validates round-trip)
        let source = SkillSource::User(skill_dir);
        load_and_validate_skill(&skill_path, SkillTrust::Installed, source, user_id).await
    }

    /// Commit a prepared skill into the in-memory registry.
    ///
    /// This is a fast, synchronous operation that only adds to the Vec.
    /// Call after `prepare_install` completes.
    pub fn commit_install(&self, name: &str, skill: LoadedSkill) -> Result<(), SkillRegistryError> {
        // Check for duplicates under the same owner (another thread may have installed between prepare and commit)
        let owner = &skill.owner_user_id;
        if self
            .skills
            .read()
            .iter()
            .any(|s| s.manifest.name == name && s.owner_user_id == *owner)
        {
            return Err(SkillRegistryError::AlreadyExists {
                name: name.to_string(),
            });
        }
        self.skills.write().push(Arc::new(skill));
        tracing::debug!("Installed skill: {}", name);
        Ok(())
    }

    /// Install a skill, replacing any existing skill with the same name and owner.
    ///
    /// Unlike `commit_install` which returns `AlreadyExists` on duplicate, this
    /// method atomically removes the old version and inserts the new one within
    /// a single write lock, avoiding the "delete-then-install" gap where the
    /// skill would be absent from the registry.
    pub fn commit_install_or_replace(
        &self,
        name: &str,
        skill: LoadedSkill,
    ) -> Result<(), SkillRegistryError> {
        let owner = &skill.owner_user_id;
        let mut skills = self.skills.write();
        // Atomically remove old version under the same owner, then insert new.
        skills.retain(|s| !(s.manifest.name == name && s.owner_user_id == *owner));
        skills.push(Arc::new(skill));
        tracing::debug!("Installed (or replaced) skill: {}", name);
        Ok(())
    }

    /// Install a skill at runtime from SKILL.md content.
    ///
    /// Convenience method that parses, writes to disk, and commits in-memory.
    /// When called through tool execution where a lock is involved, prefer using
    /// `prepare_install_to_disk` + `commit_install` separately to minimize lock
    /// hold time.
    pub async fn install_skill(
        &self,
        content: &str,
        user_id: &str,
    ) -> Result<String, SkillRegistryError> {
        let normalized = normalize_line_endings(content);
        let (skill_name, install_content) = normalize_install_content(&normalized, None)?;
        if self.has_owned(&skill_name, user_id) {
            return Err(SkillRegistryError::AlreadyExists {
                name: skill_name.clone(),
            });
        }

        // Security scan before installation (if enabled)
        #[cfg(feature = "security-scan")]
        {
            if let Err(e) = Self::security_scan(&skill_name, &install_content).await {
                return Err(SkillRegistryError::SecurityCheckFailed {
                    name: skill_name.clone(),
                    reason: e,
                });
            }
        }

        let user_dir = self.user_dir.clone();
        let (name, mut skill) =
            Self::prepare_install_to_disk(&user_dir, &skill_name, &install_content, user_id)
                .await?;
        skill.owner_user_id = user_id.to_string();
        self.commit_install(&name, skill)?;
        Ok(name)
    }

    /// Perform security scan on skill content before installation.
    /// Only available when the `security-scan` feature is enabled.
    #[cfg(feature = "security-scan")]
    async fn security_scan(name: &str, content: &str) -> Result<(), String> {
        use crate::security::{SkillSecurityFile, scan_skill_package};

        // Check if security scanning is enabled (default: true when feature is enabled)
        let enabled = std::env::var("SKILL_SECURITY_SCAN_ENABLED")
            .map(|v| v != "false")
            .unwrap_or(true);

        if !enabled {
            tracing::debug!(skill = %name, "Security scan disabled, skipping");
            return Ok(());
        }

        let scan_result = scan_skill_package(&[SkillSecurityFile {
            path: "SKILL.md",
            content,
        }]);
        tracing::info!(
            skill = %name,
            findings = scan_result.findings.len(),
            "Skill security scan completed"
        );

        if scan_result.has_critical_findings() {
            Err(format!(
                "Security scan blocked. Findings: {}",
                scan_result.critical_summary()
            ))
        } else {
            if !scan_result.findings.is_empty() {
                tracing::warn!(
                    skill = %name,
                    findings = scan_result.findings.len(),
                    "Skill scan found warning-level issues but allowing"
                );
            }
            Ok(())
        }
    }

    /// Validate that a skill can be removed and return its filesystem path.
    ///
    /// Performs validation without modifying state. Callers can then do async
    /// filesystem cleanup without holding the registry lock, and call
    /// `commit_remove` afterward.
    pub fn validate_remove(
        &self,
        name: &str,
        user_id: &str,
    ) -> Result<PathBuf, SkillRegistryError> {
        // 1. Check if a global version exists first (owner_user_id is empty)
        if self
            .skills
            .read()
            .iter()
            .any(|s| s.manifest.name == name && s.owner_user_id.is_empty())
        {
            return Err(SkillRegistryError::CannotRemove {
                name: name.to_string(),
                reason: "global/bundled skills cannot be removed".to_string(),
            });
        }

        // 2. Check if current user owns the skill
        let idx = self
            .skills
            .read()
            .iter()
            .position(|s| s.manifest.name == name && s.owner_user_id == user_id)
            .ok_or_else(|| {
                // Distinguish "belongs to another user" from "not found"
                if self.skills.read().iter().any(|s| s.manifest.name == name) {
                    SkillRegistryError::CannotRemove {
                        name: name.to_string(),
                        reason: "skill belongs to another user".to_string(),
                    }
                } else {
                    SkillRegistryError::NotFound(name.to_string())
                }
            })?;

        let skill = self.skills.read()[idx].clone();

        match &skill.source {
            SkillSource::User(path) | SkillSource::Installed(path) => Ok(path.clone()),
            SkillSource::Workspace(_) => Err(SkillRegistryError::CannotRemove {
                name: name.to_string(),
                reason: "workspace skills cannot be removed via this interface".to_string(),
            }),
            SkillSource::Bundled(_) => Err(SkillRegistryError::CannotRemove {
                name: name.to_string(),
                reason: "bundled skills cannot be removed".to_string(),
            }),
        }
    }

    /// Remove a skill's files from disk (async I/O).
    ///
    /// Call after `validate_remove` and before `commit_remove`.
    pub async fn delete_skill_files(path: &Path, user_id: &str) -> Result<(), SkillRegistryError> {
        let afs = get_afs(user_id)?;
        let skill_md = path.join("SKILL.md");
        if afs.physical_exists(&skill_md) {
            afs.remove_file(&skill_md)
                .await
                .map_err(|e| SkillRegistryError::WriteError {
                    path: skill_md.display().to_string(),
                    reason: e.to_string(),
                })?;
            // Remove the directory if empty
            let _ = afs.remove_dir(path).await;
        }
        Ok(())
    }

    /// Remove a skill from the in-memory registry.
    ///
    /// Fast synchronous operation. Call after filesystem cleanup.
    /// Uses (name, owner_user_id) compound key to avoid removing
    /// another user's skill with the same name.
    pub fn commit_remove(&self, name: &str, user_id: &str) -> Result<(), SkillRegistryError> {
        let idx = self
            .skills
            .read()
            .iter()
            .position(|s| s.manifest.name == name && s.owner_user_id == user_id)
            .ok_or_else(|| {
                if self
                    .skills
                    .read()
                    .iter()
                    .any(|s| s.manifest.name == name && s.owner_user_id.is_empty())
                {
                    SkillRegistryError::CannotRemove {
                        name: name.to_string(),
                        reason: "global/bundled skills cannot be removed".to_string(),
                    }
                } else if self.skills.read().iter().any(|s| s.manifest.name == name) {
                    SkillRegistryError::CannotRemove {
                        name: name.to_string(),
                        reason: "skill belongs to another user".to_string(),
                    }
                } else {
                    SkillRegistryError::NotFound(name.to_string())
                }
            })?;

        self.skills.write().remove(idx);
        tracing::debug!("Removed skill: {}", name);
        Ok(())
    }

    /// Remove a skill by name.
    ///
    /// Convenience method that combines validation, file deletion, and in-memory
    /// removal. When called through tool execution, prefer using the split
    /// validate/delete/commit methods to minimize lock hold time.
    pub async fn remove_skill(&self, name: &str, user_id: &str) -> Result<(), SkillRegistryError> {
        let path = self.validate_remove(name, user_id)?;
        Self::delete_skill_files(&path, user_id).await?;
        self.commit_remove(name, user_id)
    }
}
