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
    // Reject NUL bytes defensively even though `&str` is already UTF-8. This
    // keeps the helper usable if the entry point is later widened to `&[u8]`.
    if name.as_bytes().contains(&0u8) {
        return None;
    }
    // Reject `~`-prefixed and Windows drive-letter inputs (`c:foo`) at the
    // string front. Unix `Path::components` parses `~` and `c:` as `Normal`
    // segments, so without this guard a hostile relative path could escape a
    // pinned `resourceRoot` via shell tilde expansion or a drive-prefixed
    // absolute path. See `safe_companion_relative_path`.
    if has_unsafe_prefix(name) {
        return None;
    }
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

/// Returns true if `input` leads with a prefix that should never flow into a
/// pinned-resource-root relative join: a leading `~`, a leading `/` or `\`
/// (absolute), or a Windows drive letter (`[a-zA-Z]:`). This is the
/// string-level guard shared by [`safe_zip_path`] and
/// [`safe_companion_relative_path`].
fn has_unsafe_prefix(input: &str) -> bool {
    let trimmed = input.trim_start_matches(' ');
    if trimmed.starts_with('~') {
        return true;
    }
    if trimmed.starts_with('/') || trimmed.starts_with('\\') {
        return true;
    }
    // Windows drive-letter prefix: a single ASCII letter followed by `:`.
    let bytes = trimmed.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        return true;
    }
    false
}

/// Pure string-level validation of a relative `relative_path` against a
/// pinned `resource_root`. Re-implemented from OpenClaw (MIT) design notes
/// (workitem #189165): bounded local skill companion reads. No OpenClaw
/// source code is ported; the Napaxi implementation rewrites the boundary
/// rules from scratch under GPL-3.0-or-later. See `THIRD-PARTY-LICENSES.md`.
///
/// Rejected inputs:
/// - any NUL byte (defensive, even though `&str` is already UTF-8);
/// - a leading `~` (shell tilde expansion)
/// - a leading `/` or `\` (absolute path on Unix or Windows);
/// - a leading `[a-zA-Z]:` (Windows drive-letter prefix);
/// - any `..` / `.` / root / prefix `Path::components` segment — only
///   `Component::Normal` is accepted.
///
/// Returns the joined `resource_root` + validated relative path on success.
#[allow(dead_code)] // Foundational helper for upcoming companion reads; covered by tests.
pub(super) fn safe_companion_relative_path(
    resource_root: &Path,
    relative_path: &str,
) -> Result<PathBuf, String> {
    if relative_path.as_bytes().contains(&0u8) {
        return Err(format!(
            "companion path contains NUL byte: {relative_path:?}"
        ));
    }
    if has_unsafe_prefix(relative_path) {
        return Err(format!(
            "companion path has unsafe prefix (~, absolute, or drive-letter): {relative_path:?}"
        ));
    }
    let safe = safe_zip_path(relative_path)
        .ok_or_else(|| format!("unsafe companion path: {relative_path:?}"))?;
    Ok(resource_root.join(safe))
}

/// Filesystem-level validation that `target` reads as a regular file inside
/// the pinned `resource_root`. Defends against symlink escape and cross-tree
/// hardlinks. Re-implemented from OpenClaw (MIT) design notes
/// (workitem #189165); see `safe_companion_relative_path` for the license
/// note.
///
/// Rejected targets:
/// - any stat failure (the caller is expected to translate `NotFound` /
///   "companion root missing" into a graceful `tracing::debug` empty result
///   rather than surfacing an unhandled rejection);
/// - symlinks (would let a companion read escape the resource root);
/// - hardlinks (link count > 1) — same skill-root support file is normally
///   singly-linked, so `nlink > 1` is treated conservatively as a cross-tree
///   hardlink;
/// - any canonicalized target that does not lie strictly inside the
///   canonicalized `resource_root`.
#[allow(dead_code)] // Foundational helper for upcoming companion reads; covered by tests.
pub(super) fn validate_companion_target(resource_root: &Path, target: &Path) -> Result<(), String> {
    let symlink_meta = std::fs::symlink_metadata(target)
        .map_err(|e| format!("cannot stat companion target {}: {e}", target.display()))?;
    if symlink_meta.file_type().is_symlink() {
        return Err(format!(
            "refusing companion via symlink: {}",
            target.display()
        ));
    }
    // Hardlink guard: same skill-root support files are normally singly
    // linked, so `nlink > 1` is treated conservatively as a cross-tree
    // hardlink. The cross-platform `Metadata::nlink` accessor is not yet
    // stabilised on this toolchain, so we use platform-specific helpers
    // (`os::unix::fs::MetadataExt` on Unix, `1` elsewhere).
    if nlink_of(&symlink_meta) > 1 {
        return Err(format!(
            "refusing companion via hardlink (nlink > 1): {}",
            target.display()
        ));
    }
    let resolved_root = resource_root.canonicalize().map_err(|e| {
        format!(
            "canonicalize resource_root {}: {e}",
            resource_root.display()
        )
    })?;
    let resolved_target = target
        .canonicalize()
        .map_err(|e| format!("canonicalize companion target {}: {e}", target.display()))?;
    if !resolved_target.starts_with(&resolved_root) {
        return Err(format!(
            "companion target escapes resource root: {}",
            target.display()
        ));
    }
    Ok(())
}

/// Cross-platform hardlink count helper. The cross-platform
/// `std::fs::Metadata::nlink` accessor is not yet stabilized on this
/// toolchain, so we use the Unix `MetadataExt::nlink` and fall back to `1`
/// elsewhere. The companion guard treats `nlink > 1` conservatively.
#[cfg(unix)]
#[allow(dead_code)]
fn nlink_of(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt;
    metadata.nlink() as u32
}

#[cfg(not(unix))]
#[allow(dead_code)]
fn nlink_of(_metadata: &std::fs::Metadata) -> u32 {
    1
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

#[cfg(test)]
mod companion_path_tests {
    //! AC2 — bounded relative-path API for skill companion reads
    //! (`safe_companion_relative_path` + `validate_companion_target`).
    use super::{safe_companion_relative_path, validate_companion_target};
    use std::path::{Path, PathBuf};

    fn root() -> PathBuf {
        tempfile::tempdir().unwrap().keep()
    }

    fn write_file(root: &Path, relative: &str, body: &str) -> PathBuf {
        let path = root.join(relative);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(&path, body).unwrap();
        path
    }

    #[test]
    fn accepts_normal_relative_path() {
        let root = root();
        let resolved = safe_companion_relative_path(&root, "sub/file.txt").unwrap();
        assert_eq!(resolved, root.join("sub").join("file.txt"));
        // A nested-safe relative path also validates against the filesystem.
        let target = write_file(&root, "sub/file.txt", "hello");
        validate_companion_target(&root, &target).unwrap();
        assert!(target.exists());
    }

    #[test]
    fn rejects_dotdot() {
        let root = root();
        let err = safe_companion_relative_path(&root, "../escape").unwrap_err();
        assert!(err.contains("unsafe companion path"), "{err}");
    }

    #[test]
    fn rejects_absolute_unix() {
        let root = root();
        let err = safe_companion_relative_path(&root, "/etc/passwd").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
    }

    #[test]
    fn rejects_absolute_backslash() {
        let root = root();
        let err = safe_companion_relative_path(&root, "\\windows\\escape").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
    }

    #[test]
    fn rejects_leading_tilde() {
        let root = root();
        let err = safe_companion_relative_path(&root, "~/config/secrets").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
    }

    #[test]
    fn rejects_drive_prefix() {
        let root = root();
        let err = safe_companion_relative_path(&root, "c:foo").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
        // Uppercase drive letter must also be rejected.
        let err = safe_companion_relative_path(&root, "C:/x").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
    }

    #[test]
    fn rejects_nul_byte() {
        let root = root();
        let err = safe_companion_relative_path(&root, "a\0b").unwrap_err();
        assert!(err.contains("NUL"), "{err}");
    }

    #[test]
    fn headers_strip_to_unsafe_prefix_detection() {
        // Leading whitespace must not mask the unsafe prefix.
        let root = root();
        let err = safe_companion_relative_path(&root, "  ~/x").unwrap_err();
        assert!(err.contains("unsafe prefix"), "{err}");
    }

    #[cfg(unix)]
    #[test]
    fn validate_companion_target_rejects_symlink() {
        let root = root();
        let outside = write_file(
            &tempfile::tempdir().unwrap().keep(),
            "outside.txt",
            "secret",
        );
        let link = root.join("linked.txt");
        std::os::unix::fs::symlink(&outside, &link).unwrap();
        let err = validate_companion_target(&root, &link).unwrap_err();
        assert!(err.contains("symlink"), "{err}");
    }

    #[cfg(unix)]
    #[test]
    fn validate_companion_target_rejects_hardlink() {
        let root = root();
        let original = write_file(&root, "original.txt", "body");
        let link = root.join("linked.txt");
        std::fs::hard_link(&original, &link).unwrap();
        let err = validate_companion_target(&root, &link).unwrap_err();
        assert!(err.contains("hardlink"), "{err}");
    }

    #[test]
    fn validate_companion_target_missing_resource_root_degrades_gracefully() {
        let missing = Path::new("/nonexistent/companion/root");
        let target = missing.join("any.txt");
        let err = validate_companion_target(missing, &target).unwrap_err();
        // Either stat or canonicalize failure surfaces; both are expected to
        // be handled by the caller as "directory missing → empty result".
        assert!(
            err.contains("cannot stat") || err.contains("canonicalize"),
            "{err}"
        );
    }

    #[test]
    fn validate_companion_target_rejects_out_of_root() {
        let root = root();
        let outside = write_file(&tempfile::tempdir().unwrap().keep(), "outside.txt", "out");
        // We deliberately don't join the out-of-root target through
        // `safe_companion_relative_path` (which would already refuse the
        // path); we exercise the fs-level containment guard directly.
        let err = validate_companion_target(&root, &outside).unwrap_err();
        assert!(err.contains("escapes resource root"), "{err}");
    }
}
