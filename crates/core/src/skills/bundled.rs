//! Embedded bundled skill content and startup deploy.
//!
//! Skills in `bundled_seeds/` are compiled into the binary via `include_str!`
//! and written to `{skills_root}/app_bundled/` on engine startup. This provides
//! offline-ready, high-quality skills without network dependency.

use std::path::PathBuf;

use super::paths::app_bundled_skills_dir;

/// Current bundled skill set version. Increment when updating seed content
/// to trigger re-deployment on next engine start.
const BUNDLED_VERSION: u32 = 1;

/// Embedded skill content: (slug, SKILL.md content).
const BUNDLED_SKILLS: &[(&str, &str)] = &[
    (
        "web-researcher",
        include_str!("bundled_seeds/web-researcher/SKILL.md"),
    ),
    (
        "code-helper",
        include_str!("bundled_seeds/code-helper/SKILL.md"),
    ),
    (
        "translator",
        include_str!("bundled_seeds/translator/SKILL.md"),
    ),
    (
        "summarizer",
        include_str!("bundled_seeds/summarizer/SKILL.md"),
    ),
    (
        "daily-planner",
        include_str!("bundled_seeds/daily-planner/SKILL.md"),
    ),
    (
        "writing-assistant",
        include_str!("bundled_seeds/writing-assistant/SKILL.md"),
    ),
];

/// Deploys bundled skills to disk. Called once during engine creation.
///
/// Behavior:
/// - If the stored version matches `BUNDLED_VERSION`, does nothing.
/// - If the version is older (or missing), writes all bundled skills and updates
///   the version marker.
/// - Never touches `catalog_installed/` — user-installed versions always take
///   priority due to source_registry priority ordering.
pub fn ensure_bundled_skills(files_dir: &str) {
    let base = app_bundled_skills_dir(files_dir);
    let version_file = base.join(".version");

    if is_current_version(&version_file) {
        return;
    }

    if std::fs::create_dir_all(&base).is_err() {
        return;
    }

    for (slug, content) in BUNDLED_SKILLS {
        let skill_dir = base.join(slug);
        let skill_file = skill_dir.join("SKILL.md");
        if std::fs::create_dir_all(&skill_dir).is_ok() {
            let _ = std::fs::write(&skill_file, content);
        }
    }

    let _ = std::fs::write(&version_file, BUNDLED_VERSION.to_string());
}

fn is_current_version(version_file: &PathBuf) -> bool {
    std::fs::read_to_string(version_file)
        .ok()
        .and_then(|v| v.trim().parse::<u32>().ok())
        .is_some_and(|v| v >= BUNDLED_VERSION)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn test_ensure_bundled_skills_creates_files() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();

        ensure_bundled_skills(files_dir);

        let base = app_bundled_skills_dir(files_dir);
        assert!(base.join("web-researcher/SKILL.md").exists());
        assert!(base.join("code-helper/SKILL.md").exists());
        assert!(base.join("translator/SKILL.md").exists());
        assert!(base.join("summarizer/SKILL.md").exists());
        assert!(base.join("daily-planner/SKILL.md").exists());
        assert!(base.join("writing-assistant/SKILL.md").exists());
        assert!(base.join(".version").exists());

        let version = std::fs::read_to_string(base.join(".version")).unwrap();
        assert_eq!(version.trim(), "1");
    }

    #[test]
    fn test_ensure_bundled_skills_idempotent() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();

        ensure_bundled_skills(files_dir);

        let base = app_bundled_skills_dir(files_dir);
        let skill_file = base.join("web-researcher/SKILL.md");
        let _original_content = std::fs::read_to_string(&skill_file).unwrap();

        // Modify the file
        std::fs::write(&skill_file, "modified").unwrap();

        // Second call should NOT overwrite (same version)
        ensure_bundled_skills(files_dir);
        let after = std::fs::read_to_string(&skill_file).unwrap();
        assert_eq!(after, "modified");
    }

    #[test]
    fn test_bundled_skill_count() {
        assert_eq!(BUNDLED_SKILLS.len(), 6);
    }

    #[test]
    fn test_all_bundled_skills_have_valid_content() {
        for (slug, content) in BUNDLED_SKILLS {
            assert!(!slug.is_empty(), "slug must not be empty");
            assert!(
                content.starts_with("---"),
                "skill {slug} must have YAML frontmatter"
            );
            assert!(
                content.contains("\n---\n"),
                "skill {slug} must have closing frontmatter delimiter"
            );
        }
    }
}
