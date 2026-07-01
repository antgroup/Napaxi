//! Filesystem paths, agent-id normalization, and ZIP/skill safe-path helpers.

use std::path::{Component, Path, PathBuf};

use super::limits::DEFAULT_AGENT_ID;

pub(super) fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

pub(super) fn skills_root(files_dir: &str) -> PathBuf {
    crate::agent_runtime::domain_dir(files_dir, "skills")
}

pub(super) fn legacy_skills_root(files_dir: &str) -> PathBuf {
    crate::agent_runtime::legacy_brand_domain_dir(files_dir, "skills")
}

pub(super) fn agent_skills_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    let agent_id = normalize_agent_id(agent_id);
    skills_root(files_dir).join("agents").join(&agent_id)
}

pub(super) fn installed_skills_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    let agent_id = normalize_agent_id(agent_id);
    skills_root(files_dir).join("installed").join(&agent_id)
}

pub(super) fn app_bundled_skills_dir(files_dir: &str) -> PathBuf {
    skills_root(files_dir).join("app_bundled")
}

pub(super) fn host_installed_skills_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    let agent_id = normalize_agent_id(agent_id);
    skills_root(files_dir)
        .join("host_installed")
        .join(&agent_id)
}

pub(super) fn legacy_agent_skills_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    legacy_skills_root(files_dir)
        .join("agents")
        .join(normalize_agent_id(agent_id))
}

pub(super) fn legacy_installed_skills_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    legacy_skills_root(files_dir)
        .join("installed")
        .join(normalize_agent_id(agent_id))
}

pub(super) fn usage_dir(files_dir: &str) -> PathBuf {
    skills_root(files_dir).join("usage")
}

pub(super) fn legacy_usage_dir(files_dir: &str) -> PathBuf {
    legacy_skills_root(files_dir).join("usage")
}

pub(super) fn usage_path(files_dir: &str, agent_id: &str) -> PathBuf {
    usage_dir(files_dir).join(format!("{}.json", normalize_agent_id(agent_id)))
}

pub(super) fn legacy_usage_path(files_dir: &str, agent_id: &str) -> PathBuf {
    legacy_usage_dir(files_dir).join(format!("{}.json", normalize_agent_id(agent_id)))
}

pub(super) fn archive_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("archive")
        .join(normalize_agent_id(agent_id))
}

pub(super) fn backups_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("backups")
        .join(normalize_agent_id(agent_id))
}

pub(super) fn source_state_path(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("sources")
        .join(format!("{}.json", normalize_agent_id(agent_id)))
}

pub(super) fn snapshot_dir(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("snapshots")
        .join(normalize_agent_id(agent_id))
}

pub(super) fn snapshot_index_path(files_dir: &str, agent_id: &str) -> PathBuf {
    snapshot_dir(files_dir, agent_id).join("index.jsonl")
}

pub(super) fn remediation_runs_path(files_dir: &str, agent_id: &str) -> PathBuf {
    skills_root(files_dir)
        .join("remediation")
        .join(format!("{}.jsonl", normalize_agent_id(agent_id)))
}

/// Reject skill names that are empty or contain anything other than a single
/// normal path segment (no `..`, no separators, no absolute/root markers).
///
/// A skill name flows straight into `Path::join` for directories that are
/// later passed to `remove_dir_all`; a traversal segment such as `../../foo`
/// would let a delete escape the skills tree entirely.
pub(super) fn safe_skill_name(skill_name: &str) -> Result<&str, String> {
    let trimmed = skill_name.trim();
    if trimmed.is_empty() {
        return Err("skill name cannot be empty".to_string());
    }
    let mut components = Path::new(trimmed).components();
    match (components.next(), components.next()) {
        (Some(Component::Normal(part)), None) if part == trimmed => Ok(trimmed),
        _ => Err(format!("unsafe skill name: {skill_name}")),
    }
}

pub(super) fn skill_dir_path(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
) -> Result<PathBuf, String> {
    let skill_name = safe_skill_name(skill_name)?;
    let user_skill_dir = agent_skills_dir(files_dir, agent_id).join(skill_name);
    let installed_skill_dir = installed_skills_dir(files_dir, agent_id).join(skill_name);
    let host_skill_dir = host_installed_skills_dir(files_dir, agent_id).join(skill_name);
    let app_skill_dir = app_bundled_skills_dir(files_dir).join(skill_name);
    let agent_id = normalize_agent_id(agent_id);
    let legacy_user_skill_dir = legacy_agent_skills_dir(files_dir, &agent_id).join(skill_name);
    let legacy_installed_skill_dir =
        legacy_installed_skills_dir(files_dir, &agent_id).join(skill_name);
    if user_skill_dir.exists() {
        Ok(user_skill_dir)
    } else if installed_skill_dir.exists() {
        Ok(installed_skill_dir)
    } else if host_skill_dir.exists() {
        Ok(host_skill_dir)
    } else if app_skill_dir.exists() {
        Ok(app_skill_dir)
    } else if legacy_user_skill_dir.exists() {
        Ok(legacy_user_skill_dir)
    } else if legacy_installed_skill_dir.exists() {
        Ok(legacy_installed_skill_dir)
    } else {
        Err(format!("Skill '{}' was not found", skill_name))
    }
}

/// Last-line guard before any `remove_dir_all` inside the skills tree.
///
/// Refuses a target that (1) is a symlink (rmtree would follow it out of the
/// tree), (2) is one of the skills roots itself (would wipe every skill), or
/// (3) resolves to a location that is not strictly inside a known skills root.
/// This is defense-in-depth on top of [`safe_skill_name`]: even if a caller
/// constructs a path by other means, a recursive delete cannot escape.
pub(super) fn validate_delete_target(files_dir: &str, target: &Path) -> Result<(), String> {
    let symlink_meta = std::fs::symlink_metadata(target)
        .map_err(|e| format!("cannot stat delete target {}: {e}", target.display()))?;
    if symlink_meta.file_type().is_symlink() {
        return Err(format!(
            "refusing to delete via symlink: {}",
            target.display()
        ));
    }

    let roots = [skills_root(files_dir), legacy_skills_root(files_dir)];
    // Compare against the canonical form when available so `..` and symlinked
    // ancestors cannot disguise an out-of-tree path.
    let resolved = target
        .canonicalize()
        .unwrap_or_else(|_| target.to_path_buf());

    for root in &roots {
        let resolved_root = root.canonicalize().unwrap_or_else(|_| root.clone());
        if resolved == resolved_root {
            return Err(format!(
                "refusing to delete the skills root itself: {}",
                target.display()
            ));
        }
        if resolved.starts_with(&resolved_root) {
            return Ok(());
        }
    }

    Err(format!(
        "refusing to delete path outside the skills tree: {}",
        target.display()
    ))
}

pub(super) fn skill_target_path(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    relative_path: Option<&str>,
) -> Result<PathBuf, String> {
    let skill_dir = skill_dir_path(files_dir, agent_id, skill_name)?;
    let safe_path = safe_skill_relative_path(relative_path)?;
    Ok(skill_dir.join(safe_path))
}

pub(super) fn safe_skill_relative_path(relative_path: Option<&str>) -> Result<PathBuf, String> {
    let Some(path) = relative_path else {
        return Ok(PathBuf::from("SKILL.md"));
    };
    let safe_path = safe_zip_path(path).ok_or_else(|| format!("unsafe skill path: {path}"))?;
    if safe_path == Path::new("SKILL.md") {
        return Ok(safe_path);
    }
    if safe_path == Path::new("_meta.json") {
        return Err("skill package metadata cannot be read as a support file".to_string());
    }
    Ok(safe_path)
}

pub(super) fn safe_zip_path(name: &str) -> Option<PathBuf> {
    let path = Path::new(name);
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => out.push(part),
            _ => return None,
        }
    }
    if out.as_os_str().is_empty() {
        None
    } else {
        Some(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_skill_name_accepts_plain_names() {
        assert_eq!(safe_skill_name("my-skill").unwrap(), "my-skill");
        assert_eq!(safe_skill_name("  trimmed  ").unwrap(), "trimmed");
    }

    #[test]
    fn safe_skill_name_rejects_traversal_and_separators() {
        for bad in [
            "",
            "   ",
            "..",
            "../escape",
            "../../etc",
            "nested/skill",
            "/absolute",
            "a/../b",
        ] {
            assert!(safe_skill_name(bad).is_err(), "should reject {bad:?}");
        }
    }

    #[test]
    fn skill_dir_path_rejects_traversal_name() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        let err = skill_dir_path(&files_dir, "agent", "../../escape").unwrap_err();
        assert!(err.contains("unsafe skill name"), "{err}");
    }

    #[test]
    fn validate_delete_target_allows_in_tree_skill() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        let target = agent_skills_dir(&files_dir, "agent").join("good-skill");
        std::fs::create_dir_all(&target).unwrap();
        assert!(validate_delete_target(&files_dir, &target).is_ok());
    }

    #[test]
    fn validate_delete_target_refuses_skills_root() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        let root = skills_root(&files_dir);
        std::fs::create_dir_all(&root).unwrap();
        let err = validate_delete_target(&files_dir, &root).unwrap_err();
        assert!(err.contains("skills root"), "{err}");
    }

    #[test]
    fn validate_delete_target_refuses_out_of_tree() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        std::fs::create_dir_all(skills_root(&files_dir)).unwrap();
        let outside = dir.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        let err = validate_delete_target(&files_dir, &outside).unwrap_err();
        assert!(err.contains("outside the skills tree"), "{err}");
    }

    #[cfg(unix)]
    #[test]
    fn validate_delete_target_refuses_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let files_dir = dir.path().to_string_lossy().to_string();
        let victim = dir.path().join("precious");
        std::fs::create_dir_all(&victim).unwrap();
        std::fs::write(victim.join("important.txt"), "DO NOT DELETE").unwrap();
        let skills = agent_skills_dir(&files_dir, "agent");
        std::fs::create_dir_all(&skills).unwrap();
        let link = skills.join("evil-skill");
        std::os::unix::fs::symlink(&victim, &link).unwrap();
        let err = validate_delete_target(&files_dir, &link).unwrap_err();
        assert!(err.contains("symlink"), "{err}");
        assert!(victim.join("important.txt").exists());
    }
}
