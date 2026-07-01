use crate::{ActivationCriteria, SkillManifest};

use super::*;
use std::fs;

#[tokio::test]
async fn test_discover_empty_dir() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_discover_nonexistent_dir() {
    let registry = SkillRegistry::new(PathBuf::from("/nonexistent/skills"));
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_load_subdirectory_layout() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default12", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "test-skill",
        "---\nname: test-skill\ndescription: A test skill\nactivation:\n  keywords: [\"test\"]\n---\n\nYou are a helpful test assistant.\n",
        "default12",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default12").await;

    assert_eq!(loaded, vec!["test-skill"]);
    assert_eq!(registry.count(), 1);

    let skill = &registry.skills()[0];
    assert_eq!(skill.trust, SkillTrust::Trusted);
    assert!(skill.prompt_content.contains("helpful test assistant"));
}

#[tokio::test]
async fn test_workspace_overrides_user() {
    let user_dir = tempfile::tempdir().unwrap();
    let ws_dir = tempfile::tempdir().unwrap();

    register_afs_user(
        "default",
        vec![user_dir.path().to_path_buf(), ws_dir.path().to_path_buf()],
    );

    // Create skill in user dir
    create_skill_dir(
        user_dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nUser version.\n",
        "default",
    )
    .await;

    // Create same-named skill in workspace dir
    create_skill_dir(
        ws_dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nWorkspace version.\n",
        "default",
    )
    .await;

    let registry = SkillRegistry::new(user_dir.path().to_path_buf())
        .with_workspace_dir(ws_dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;

    assert_eq!(loaded, vec!["my-skill"]);
    assert_eq!(registry.count(), 1);
    assert!(registry.skills()[0].prompt_content.contains("Workspace"));
}

#[tokio::test]
async fn test_gating_failure_skips_skill() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "gated-skill",
        "---\nname: gated-skill\nrequires:\n  bins: [\"__nonexistent_bin__\"]\n---\n\nGated prompt.\n",
        "default",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[cfg(unix)]
#[tokio::test]
async fn test_symlink_rejected() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    let real_dir = dir.path().join("real-skill");
    fs::create_dir(&real_dir).unwrap();
    fs::write(
        real_dir.join("SKILL.md"),
        "---\nname: real-skill\n---\n\nTest.\n",
    )
    .unwrap();

    let skills_dir = dir.path().join("skills");
    fs::create_dir(&skills_dir).unwrap();
    std::os::unix::fs::symlink(&real_dir, skills_dir.join("linked-skill")).unwrap();

    let registry = SkillRegistry::new(skills_dir);
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_file_size_limit() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    let big_content = format!(
        "---\nname: big-skill\n---\n\n{}",
        "x".repeat((MAX_PROMPT_FILE_SIZE + 1) as usize)
    );
    afs_write(
        "default",
        &dir.path().join("big-skill").join("SKILL.md"),
        &big_content,
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_invalid_skill_md_skipped() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    // Missing frontmatter
    create_skill_dir(dir.path(), "bad-skill", "Just plain text", "default").await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_line_ending_normalization() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default14", vec![dir.path().to_path_buf()]);

    create_skill_dir(
        dir.path(),
        "crlf-skill",
        "---\r\nname: crlf-skill\r\n---\r\n\r\nline1\r\nline2\r\n",
        "default14",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("default14").await;

    assert_eq!(registry.count(), 1);
    let skill = &registry.skills()[0];
    assert_eq!(skill.prompt_content, "line1\nline2\n");
}

#[tokio::test]
async fn test_token_budget_rejection() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    let big_prompt = "word ".repeat(4000);
    let content = format!(
        "---\nname: big-prompt\nactivation:\n  max_context_tokens: 100\n---\n\n{}",
        big_prompt
    );
    create_skill_dir(dir.path(), "big-prompt", &content, "default").await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;
    assert!(loaded.is_empty());
}

#[tokio::test]
async fn test_has_and_find_by_name() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    create_skill_dir(
        dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nPrompt.\n",
        "default",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("default").await;

    assert!(registry.has("my-skill"));
    assert!(!registry.has("nonexistent"));
    assert!(registry.find_by_name("my-skill").is_some());
    assert!(registry.find_by_name("nonexistent").is_none());
}

#[tokio::test]
async fn test_install_skill_from_content() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("defaultaa", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content =
        "---\nname: test-install\ndescription: Installed skill\n---\n\nInstalled prompt.\n";
    let name = registry.install_skill(content, "defaultaa").await.unwrap();

    assert_eq!(name, "test-install");
    assert!(registry.has("test-install"));
    assert_eq!(registry.count(), 1);

    // Verify file was written to disk
    let skill_path = dir.path().join("test-install").join("SKILL.md");
    let afs = get_afs("defaultaa").unwrap();
    assert!(afs.physical_exists(&skill_path));
}

#[test]
fn test_resolve_install_content_prefers_requested_slug_for_invalid_name() {
    let content =
        "---\nname: Mortgage Calculator\ndescription: Installed skill\n---\n\nInstalled prompt.\n";

    let (name, rewritten) =
        SkillRegistry::resolve_install_content(content, Some("finance/mortgage-calculator"))
            .unwrap();

    assert_eq!(name, "finance-mortgage-calculator");
    assert!(rewritten.contains("name: finance-mortgage-calculator"));
    assert!(rewritten.contains("Installed prompt."));
}

#[test]
fn test_resolve_install_content_slugifies_invalid_name_without_slug() {
    let content = "---\nname: Mortgage Calculator\n---\n\nPrompt.\n";

    let (name, rewritten) = SkillRegistry::resolve_install_content(content, None).unwrap();

    assert_eq!(name, "mortgage-calculator");
    assert!(rewritten.contains("name: mortgage-calculator"));
}

#[tokio::test]
async fn test_install_skill_normalizes_invalid_name() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default16", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content =
        "---\nname: Mortgage Calculator\ndescription: Installed skill\n---\n\nInstalled prompt.\n";
    let name = registry.install_skill(content, "default16").await.unwrap();

    assert_eq!(name, "mortgage-calculator");
    assert!(registry.has("mortgage-calculator"));

    let skill_path = dir.path().join("mortgage-calculator").join("SKILL.md");
    let afs = get_afs("default16").unwrap();
    assert!(afs.physical_exists(&skill_path));

    let written_bytes = afs.read(&skill_path).await.unwrap();
    let written = String::from_utf8(written_bytes).unwrap();
    assert!(written.contains("name: mortgage-calculator"));
}

#[test]
fn test_resolve_install_content_preserves_unknown_frontmatter_fields() {
    // Published manifests may carry custom keys (vendor extensions, future
    // fields) that the typed `SkillManifest` does not know about. Recovery
    // must rewrite only `name` without dropping unknown keys.
    let content = "---\nname: Mortgage Calculator\ndescription: Computes payments\nx-publisher: acme\ncustom_meta:\n  rating: 5\n  tags:\n    - finance\n    - calculator\n---\n\nInstalled prompt.\n";

    let (name, rewritten) = SkillRegistry::resolve_install_content(content, None).unwrap();

    assert_eq!(name, "mortgage-calculator");
    assert!(rewritten.contains("name: mortgage-calculator"));
    assert!(
        rewritten.contains("x-publisher: acme"),
        "unknown top-level key was dropped: {rewritten}"
    );
    assert!(
        rewritten.contains("custom_meta:"),
        "unknown nested mapping was dropped: {rewritten}"
    );
    assert!(
        rewritten.contains("rating: 5"),
        "nested scalar was dropped: {rewritten}"
    );
    assert!(
        rewritten.contains("- finance") && rewritten.contains("- calculator"),
        "nested sequence was dropped: {rewritten}"
    );
    assert!(rewritten.contains("Installed prompt."));
}

#[test]
fn test_resolve_install_content_preserves_owner_for_invalid_slug_name() {
    let content = "---\nname: Mortgage Calculator\n---\n\nPrompt.\n";

    let (name, rewritten) =
        SkillRegistry::resolve_install_content(content, Some("alice/mortgage-calculator")).unwrap();

    assert_eq!(name, "alice-mortgage-calculator");
    assert!(rewritten.contains("name: alice-mortgage-calculator"));
}

#[tokio::test]
async fn test_install_duplicate_rejected() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content = "---\nname: dup-skill\n---\n\nPrompt.\n";
    registry.install_skill(content, "default").await.unwrap();

    let result = registry.install_skill(content, "default").await;
    assert!(matches!(
        result,
        Err(SkillRegistryError::AlreadyExists { .. })
    ));
}

#[tokio::test]
async fn test_remove_user_skill() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default5", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content = "---\nname: removable\n---\n\nPrompt.\n";
    registry.install_skill(content, "default5").await.unwrap();
    assert!(registry.has("removable"));

    registry
        .remove_skill("removable", "default5")
        .await
        .unwrap();
    assert!(!registry.has("removable"));
    assert_eq!(registry.count(), 0);
}

#[tokio::test]
async fn test_remove_workspace_skill_rejected() {
    let dir_temp = tempfile::tempdir().unwrap();
    let dir = dir_temp.path().to_path_buf();
    let user_dir = dir.join("user");
    let ws_dir = user_dir.clone().join("ws");

    register_afs_user(
        "defaultr",
        vec![user_dir.to_path_buf(), ws_dir.to_path_buf()],
    );

    create_skill_dir(
        ws_dir.as_path(),
        "ws-skill",
        "---\nname: ws-skill\n---\n\nWorkspace prompt.\n",
        "defaultr",
    )
    .await;

    let registry =
        SkillRegistry::new(user_dir.to_path_buf()).with_workspace_dir(ws_dir.to_path_buf());
    registry.discover_all("defaultr").await;

    let result = registry.remove_skill("ws-skill", "defaultr").await;
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { .. })
    ));
}

#[tokio::test]
async fn test_remove_nonexistent_fails() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let result = registry.remove_skill("nonexistent", "default").await;
    assert!(matches!(result, Err(SkillRegistryError::NotFound(_))));
}

#[tokio::test]
async fn test_reload_clears_and_rediscovers() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default7", vec![dir.path().to_path_buf()]);

    create_skill_dir(
        dir.path(),
        "persist-skill",
        "---\nname: persist-skill\n---\n\nPrompt.\n",
        "default7",
    )
    .await;

    let mut registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("default7").await;
    assert_eq!(registry.count(), 1);

    let loaded = registry.reload_for_user("default7").await;
    assert_eq!(loaded, vec!["persist-skill"]);
    assert_eq!(registry.count(), 1);
}

#[tokio::test]
async fn test_load_flat_layout() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default13", vec![dir.path().to_path_buf()]);

    // Place a SKILL.md directly in the skills directory (flat layout)
    afs_write(
        "default13",
        &dir.path().join("SKILL.md"),
        "---\nname: flat-skill\ndescription: A flat layout skill\nactivation:\n  keywords: [\"flat\"]\n---\n\nYou are a flat layout test skill.\n",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default13").await;

    assert_eq!(loaded, vec!["flat-skill"]);
    assert_eq!(registry.count(), 1);

    let skill = &registry.skills()[0];
    assert_eq!(skill.trust, SkillTrust::Trusted);
    assert!(skill.prompt_content.contains("flat layout test skill"));
}

#[tokio::test]
async fn test_mixed_flat_and_subdirectory_layout() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default8", vec![dir.path().to_path_buf()]);

    // Flat layout: SKILL.md directly in the skills directory
    afs_write(
        "default8",
        &dir.path().join("SKILL.md"),
        "---\nname: flat-skill\n---\n\nFlat prompt.\n",
    )
    .await;

    // Subdirectory layout: <name>/SKILL.md
    create_skill_dir(
        dir.path(),
        "sub-skill",
        "---\nname: sub-skill\n---\n\nSub prompt.\n",
        "default8",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default8").await;

    assert_eq!(registry.count(), 2);
    assert!(loaded.contains(&"flat-skill".to_string()));
    assert!(loaded.contains(&"sub-skill".to_string()));
}

#[tokio::test]
async fn test_lowercased_fields_populated() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default9", vec![dir.path().to_path_buf()]);

    create_skill_dir(
        dir.path(),
        "case-skill",
        "---\nname: case-skill\nactivation:\n  keywords: [\"Write\", \"EDIT\"]\n  tags: [\"Email\", \"PROSE\"]\n---\n\nTest prompt.\n",
        "default9",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("default9").await;

    let skill = registry.find_by_name("case-skill").unwrap();
    assert_eq!(skill.lowercased_keywords, vec!["write", "edit"]);
    assert_eq!(skill.lowercased_tags, vec!["email", "prose"]);
}

#[tokio::test]
async fn test_retain_only_empty_is_noop() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    afs_write(
        "default",
        &dir.path().join("SKILL.md"),
        "---\nname: keep-me\ndescription: test\nactivation:\n  keywords: [\"test\"]\n---\n\nKeep this skill.\n",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("default").await;
    assert_eq!(registry.count(), 1);

    registry.retain_only(&[]);
    assert_eq!(
        registry.count(),
        1,
        "empty retain_only should keep all skills"
    );
}

#[test]
fn test_compute_hash_deterministic() {
    let h1 = compute_hash("hello world");
    let h2 = compute_hash("hello world");
    assert_eq!(h1, h2);
    assert!(h1.starts_with("sha256:"));
}

#[test]
fn test_compute_hash_different_content() {
    let h1 = compute_hash("hello");
    let h2 = compute_hash("world");
    assert_ne!(h1, h2);
}

/// Skills in the installed_dir are discovered with SkillTrust::Installed,
/// not Trusted. This ensures registry-installed skills do not gain full
/// tool access after an agent restart.
#[tokio::test]
async fn test_installed_dir_uses_installed_trust() {
    let user_dir = tempfile::tempdir().unwrap();
    let inst_dir = tempfile::tempdir().unwrap();

    register_afs_user(
        "default15",
        vec![user_dir.path().to_path_buf(), inst_dir.path().to_path_buf()],
    );

    // Place a skill in the installed dir
    create_skill_dir(
        inst_dir.path(),
        "registry-skill",
        "---\nname: registry-skill\nversion: \"1.2.3\"\n---\n\nInstalled prompt.\n",
        "default15",
    )
    .await;

    let registry = SkillRegistry::new(user_dir.path().to_path_buf())
        .with_installed_dir(inst_dir.path().to_path_buf());
    let loaded = registry.discover_all("default15").await;

    assert_eq!(loaded, vec!["registry-skill"]);
    let skill = registry.find_by_name("registry-skill").unwrap();
    assert_eq!(
        skill.trust,
        SkillTrust::Installed,
        "installed_dir skills must be Installed"
    );
    assert_eq!(skill.manifest.version, "1.2.3");
}

/// install_target_dir() returns installed_dir when set, user_dir otherwise.
#[test]
fn test_install_target_dir_prefers_installed_dir() {
    let user_dir = PathBuf::from("/tmp/user-skills");
    let inst_dir = PathBuf::from("/tmp/installed-skills");

    let registry = SkillRegistry::new(user_dir.clone()).with_installed_dir(inst_dir.clone());
    assert_eq!(registry.install_target_dir(), inst_dir.as_path());

    let registry_no_inst = SkillRegistry::new(user_dir.clone());
    assert_eq!(registry_no_inst.install_target_dir(), user_dir.as_path());
}

/// User skills (user_dir) remain Trusted even when installed_dir is set.
#[tokio::test]
async fn test_user_dir_stays_trusted_with_installed_dir() {
    let user_dir = tempfile::tempdir().unwrap();
    let inst_dir = tempfile::tempdir().unwrap();

    register_afs_user(
        "default33",
        vec![user_dir.path().to_path_buf(), inst_dir.path().to_path_buf()],
    );

    create_skill_dir(
        user_dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nUser prompt.\n",
        "default33",
    )
    .await;

    let registry = SkillRegistry::new(user_dir.path().to_path_buf())
        .with_installed_dir(inst_dir.path().to_path_buf());
    registry.discover_all("default33").await;

    let skill = registry.find_by_name("my-skill").unwrap();
    assert_eq!(skill.trust, SkillTrust::Trusted);
}

#[tokio::test]
async fn test_bundled_skills_loaded() {
    let dir = tempfile::tempdir().unwrap();

    // Leak the vec so we get a &'static slice
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "bundled-skill".to_string(),
        "---\nname: bundled-skill\ndescription: A bundled test\nactivation:\n  keywords: [\"test\"]\n---\n\nBundled prompt.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    let loaded = registry.discover_all("default").await;

    assert_eq!(loaded, vec!["bundled-skill"]);
    assert_eq!(registry.count(), 1);

    let skill = registry.find_by_name("bundled-skill").unwrap();
    assert_eq!(skill.trust, SkillTrust::Trusted);
    assert!(matches!(skill.source, SkillSource::Bundled(_)));
    assert!(skill.prompt_content.contains("Bundled prompt."));
}

#[tokio::test]
async fn test_bundled_skill_overridden_by_user() {
    let user_dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![user_dir.path().to_path_buf()]);

    // User skill
    create_skill_dir(
        user_dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nUser version.\n",
        "default",
    )
    .await;

    // Bundled skill with same name
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "my-skill".to_string(),
        "---\nname: my-skill\n---\n\nBundled version.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(user_dir.path().to_path_buf()).with_bundled_content(bundled);
    let loaded = registry.discover_all("default").await;

    assert_eq!(loaded, vec!["my-skill", "my-skill"]);
    assert_eq!(registry.count(), 2);
    // User version wins over bundled
    assert!(
        registry.skills()[0]
            .prompt_content
            .contains("User version.")
    );
}

#[tokio::test]
async fn test_bundled_skill_gating_failure_skipped() {
    let dir = tempfile::tempdir().unwrap();

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "gated".to_string(),
        "---\nname: gated\nrequires:\n  bins: [\"__nonexistent__\"]\n---\n\nGated.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    let loaded = registry.discover_all("default").await;

    assert!(loaded.is_empty(), "gated bundled skill should be skipped");
}

#[tokio::test]
async fn test_bundled_skill_cannot_be_removed() {
    let dir = tempfile::tempdir().unwrap();

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "permanent".to_string(),
        "---\nname: permanent\n---\n\nCannot remove.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("default").await;

    let result = registry.remove_skill("permanent", "default").await;
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { .. })
    ));
}

#[tokio::test]
async fn test_discover_nested_bundle_directory() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default23", vec![dir.path().to_path_buf()]);

    // Bundle directory (no SKILL.md) — create via AFS
    let bundle = dir.path().join("my-org");
    afs_create_dir("default23", &bundle).await;

    // Two skills inside the bundle
    create_skill_dir(
        &bundle,
        "skill-a",
        "---\nname: skill-a\n---\n\nSkill A prompt.\n",
        "default23",
    )
    .await;
    create_skill_dir(
        &bundle,
        "skill-b",
        "---\nname: skill-b\n---\n\nSkill B prompt.\n",
        "default23",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default23").await;

    assert_eq!(registry.count(), 2);
    assert!(loaded.contains(&"skill-a".to_string()));
    assert!(loaded.contains(&"skill-b".to_string()));
}

#[tokio::test]
async fn test_discover_respects_depth_limit() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default21", vec![dir.path().to_path_buf()]);

    // Create skill nested 3 levels deep (a/b/c/deep-skill/SKILL.md)
    create_skill_dir(
        &dir.path().join("a").join("b").join("c"),
        "deep-skill",
        "---\nname: deep-skill\n---\n\nDeep prompt.\n",
        "default21",
    )
    .await;

    // Depth 2 should NOT find it (3 intermediate dirs: a, b, c)
    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_max_scan_depth(2);
    let loaded = registry.discover_all("default21").await;
    assert!(loaded.is_empty(), "depth=2 should not reach 3 levels deep");

    // Depth 3 SHOULD find it
    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_max_scan_depth(3);
    let loaded = registry.discover_all("default21").await;
    assert_eq!(loaded, vec!["deep-skill"]);
}

#[tokio::test]
async fn test_discover_cap_spans_recursive_levels() {
    let dir = PathBuf::from("/tmp");
    register_afs_user("default2233", vec![dir.to_path_buf()]);

    // Spread skills across two bundle directories so the cap must be
    // shared across separate recursive calls (not just within one).
    // Each bundle has 60 skills; with a global cap of 100, the second
    // bundle should be cut short.
    for bundle_name in &["bundle-a", "bundle-b"] {
        let bundle = dir.join(bundle_name);
        for i in 0..60 {
            create_skill_dir(
                &bundle,
                &format!("{}-skill-{:02}", bundle_name, i),
                &format!(
                    "---\nname: {}-skill-{:02}\n---\n\nPrompt.\n",
                    bundle_name, i
                ),
                "default2233",
            )
            .await;
        }
    }

    let registry = SkillRegistry::new(dir.to_path_buf());
    registry.discover_all("default2233").await;

    assert!(
        registry.count() <= MAX_DISCOVERED_SKILLS,
        "global cap should limit total to {} but got {}",
        MAX_DISCOVERED_SKILLS,
        registry.count()
    );
}

#[cfg(unix)]
#[tokio::test]
async fn test_symlink_rejected_in_nested_directory() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default114", vec![dir.path().to_path_buf()]);

    // Real skill outside the bundle
    create_skill_dir(
        dir.path(),
        "real-skill",
        "---\nname: real-skill\n---\n\nReal prompt.\n",
        "default114",
    )
    .await;

    // Bundle directory with a symlink inside
    let bundle = dir.path().join("bundle");
    fs::create_dir(&bundle).unwrap();
    let real_dir = dir.path().join("real-skill");
    std::os::unix::fs::symlink(&real_dir, bundle.join("linked-skill")).unwrap();

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default114").await;

    // The real skill at top level is found, but the symlinked one inside bundle is rejected
    assert_eq!(loaded, vec!["real-skill"]);
    assert_eq!(registry.count(), 1);
}

#[tokio::test]
async fn test_discover_nested_plus_direct() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default22", vec![dir.path().to_path_buf()]);

    // Direct skill at depth 1
    create_skill_dir(
        dir.path(),
        "direct-skill",
        "---\nname: direct-skill\n---\n\nDirect prompt.\n",
        "default22",
    )
    .await;

    // Bundle with nested skill
    let bundle = dir.path().join("bundle");
    create_skill_dir(
        &bundle,
        "nested-skill",
        "---\nname: nested-skill\n---\n\nNested prompt.\n",
        "default22",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default22").await;

    assert_eq!(registry.count(), 2);
    assert!(loaded.contains(&"direct-skill".to_string()));
    assert!(loaded.contains(&"nested-skill".to_string()));
}

#[tokio::test]
async fn test_discover_dedup_direct_vs_bundle_same_name() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("default", vec![dir.path().to_path_buf()]);

    // Direct skill at depth 1
    create_skill_dir(
        dir.path(),
        "my-skill",
        "---\nname: my-skill\n---\n\nDirect version.\n",
        "default",
    )
    .await;

    // Bundle directory containing a skill with the same name
    let bundle = dir.path().join("org-bundle");
    create_skill_dir(
        &bundle,
        "my-skill",
        "---\nname: my-skill\n---\n\nBundle version.\n",
        "default",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    let loaded = registry.discover_all("default").await;

    // Only one instance should survive dedup
    assert_eq!(registry.count(), 1);
    assert_eq!(loaded, vec!["my-skill"]);
}

#[tokio::test]
async fn test_global_cap_shared_across_sources() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("test18", vec![dir.path().to_path_buf()]);
    let afs = get_afs("test18").unwrap();
    // The global cap (MAX_DISCOVERED_SKILLS=100) is shared across all
    // sources. Workspace skills are discovered first, consuming part of
    // the budget, leaving less for user skills.
    let user_dir = PathBuf::from(dir.path()).join("user");
    let ws_dir = PathBuf::from(dir.path()).join("ws");
    // 10 workspace skills (discovered first, highest priority)
    for i in 0..10 {
        let skill_dir = ws_dir.join(format!("ws-skill-{:02}", i));
        afs.create_dir_all(&skill_dir).await.unwrap();
        afs.write(
            &skill_dir.join("SKILL.md"),
            format!("---\nname: ws-skill-{:02}\n---\n\nPrompt.\n", i).as_bytes(),
        )
        .await
        .unwrap();
    }

    // 120 user skills (more than the remaining budget of 90)
    for i in 0..120 {
        let skill_dir = user_dir.join(format!("user-skill-{:03}", i));
        afs.create_dir_all(&skill_dir).await.unwrap();
        afs.write(
            &skill_dir.join("SKILL.md"),
            format!("---\nname: user-skill-{:03}\n---\n\nPrompt.\n", i).as_bytes(),
        )
        .await
        .unwrap();
    }

    let registry =
        SkillRegistry::new(user_dir.to_path_buf()).with_workspace_dir(ws_dir.to_path_buf());
    registry.discover_all("test18").await;

    // Total capped at 100 globally
    assert_eq!(registry.count(), MAX_DISCOVERED_SKILLS);
    // All 10 workspace skills must be present (discovered first)
    for i in 0..10 {
        assert!(
            registry
                .find_by_name(&format!("ws-skill-{:02}", i))
                .is_some(),
            "workspace skill ws-skill-{:02} should be discoverable",
            i
        );
    }
}

// ── User isolation tests ──────────────────────────────

fn make_skill_with_owner(
    name: &str,
    trust: SkillTrust,
    source: SkillSource,
    owner: &str,
) -> LoadedSkill {
    LoadedSkill {
        manifest: SkillManifest {
            name: name.to_string(),
            display_name: None,
            version: "1.0.0".to_string(),
            description: String::new(),
            activation: ActivationCriteria::default(),
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "test".to_string(),
        trust,
        source,
        content_hash: "sha256:000".to_string(),
        compiled_patterns: vec![],
        lowercased_keywords: vec![],
        lowercased_exclude_keywords: vec![],
        lowercased_tags: vec![],
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: owner.to_string(),
    }
}

fn skill_md(name: &str, description: &str) -> String {
    format!(
        "---\nname: {}\ndescription: {}\n---\n\nPrompt for {}.\n",
        name, description, name
    )
}

/// 批量注册 AFS 测试用户。
fn register_afs_users(users: &[(&str, Vec<PathBuf>)]) {
    crate::afs_traits::test_afs::init_test_afs_provider(); // 确保 provider 已安装
    for (user_id, virtual_dirs) in users {
        let mut maps = Vec::new();
        for vdir in virtual_dirs {
            maps.push((vdir.clone(), vdir.join(user_id)));
        }
        crate::afs_traits::test_afs::register_test_user(user_id, maps);
    }
}

/// 注册单个 AFS 测试用户。
fn register_afs_user(user_id: &str, virtual_dirs: Vec<PathBuf>) {
    register_afs_users(&[(user_id, virtual_dirs)]);
}

async fn create_skill_dir(base: &Path, skill_name: &str, content: &str, user_id: &str) {
    let afs = get_afs(user_id).unwrap();
    let skill_dir = base.join(skill_name);
    afs.create_dir_all(&skill_dir).await.unwrap();
    afs.write(&skill_dir.join("SKILL.md"), content.as_bytes())
        .await
        .unwrap();
}

async fn afs_write(user_id: &str, path: &Path, content: &str) {
    let afs = get_afs(user_id).unwrap();
    if let Some(parent) = path.parent() {
        afs.create_dir_all(parent).await.unwrap();
    }
    afs.write(path, content.as_bytes()).await.unwrap();
}

async fn afs_create_dir(user_id: &str, path: &Path) {
    let afs = get_afs(user_id).unwrap();
    afs.create_dir_all(path).await.unwrap();
}

#[tokio::test]
async fn test_skills_for_user_returns_only_owned_and_global() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "alice-skill",
        &skill_md("alice-skill", "Alice only"),
        "alice",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("alice").await;

    let alice_skills = registry.skills_for_user("alice");
    assert_eq!(alice_skills.len(), 1);
    assert_eq!(alice_skills[0].manifest.name, "alice-skill");

    let bob_skills = registry.skills_for_user("bob");
    assert!(bob_skills.is_empty());
}

#[tokio::test]
async fn test_skills_for_user_includes_global_skills() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice11", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "user-skill",
        &skill_md("user-skill", "User skill"),
        "alice11",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "bundled-skill".to_string(),
        "---\nname: bundled-skill\ndescription: Global skill\n---\n\nGlobal prompt.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice11").await;

    let alice_skills = registry.skills_for_user("alice11");
    assert_eq!(alice_skills.len(), 2);
    let names: Vec<&str> = alice_skills
        .iter()
        .map(|s| s.manifest.name.as_str())
        .collect();
    assert!(names.contains(&"user-skill"));
    assert!(names.contains(&"bundled-skill"));

    let bob_skills = registry.skills_for_user("bob");
    assert_eq!(bob_skills.len(), 1);
    assert_eq!(bob_skills[0].manifest.name, "bundled-skill");
    assert!(bob_skills[0].owner_user_id.is_empty());
}

#[tokio::test]
async fn test_has_for_user_checks_visibility() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice17", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "alice-skill",
        &skill_md("alice-skill", "Alice only"),
        "alice17",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("alice17").await;

    assert!(registry.has_for_user("alice-skill", "alice17"));
    assert!(!registry.has_for_user("alice-skill", "bob17"));
}

#[tokio::test]
async fn test_has_owned_strict_ownership() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "my-skill",
        &skill_md("my-skill", "User skill"),
        "alice",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "bundled-skill".to_string(),
        "---\nname: bundled-skill\ndescription: Global\n---\n\nGlobal.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice").await;

    assert!(registry.has_owned("my-skill", "alice"));
    assert!(!registry.has_owned("bundled-skill", "alice"));
    assert!(!registry.has_owned("my-skill", "bob"));
}

#[tokio::test]
async fn test_find_by_name_for_user_prefers_owned_over_global() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice20", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "common-skill",
        &skill_md("common-skill", "User version"),
        "alice20",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "common-skill".to_string(),
        "---\nname: common-skill\ndescription: Bundled version\n---\n\nBundled prompt.\n"
            .to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice20").await;

    let found = registry.find_by_name_for_user("common-skill", "alice20");
    assert!(found.is_some());
    assert_eq!(found.unwrap().owner_user_id, "alice20");

    let found_bob = registry.find_by_name_for_user("common-skill", "bob20");
    assert!(found_bob.is_some());
    assert!(found_bob.unwrap().owner_user_id.is_empty());
}

#[tokio::test]
async fn test_same_name_skill_coexists_across_users() {
    let alice_temp = tempfile::tempdir().unwrap();
    let alice_dir = alice_temp.path().to_path_buf();
    let bob_dir = alice_dir.clone();

    register_afs_users(&[
        ("alice4", vec![alice_dir.clone()]),
        ("bob4", vec![bob_dir.clone()]),
    ]);

    create_skill_dir(
        alice_dir.as_path(),
        "shared-name",
        &skill_md("shared-name", "Alice version"),
        "alice4",
    )
    .await;
    create_skill_dir(
        bob_dir.as_path(),
        "shared-name",
        &skill_md("shared-name", "Bob version"),
        "bob4",
    )
    .await;

    let registry = SkillRegistry::new(alice_dir.to_path_buf());
    registry.discover_all("alice4").await;

    let loaded = registry.discover_for_user("bob4").await;
    assert!(loaded.contains(&"shared-name".to_string()));

    assert_eq!(registry.skills().len(), 2);

    let alice_skills = registry.skills_for_user("alice4");
    assert_eq!(alice_skills.len(), 1);
    assert_eq!(alice_skills[0].manifest.description, "Alice version");

    let bob_skills = registry.skills_for_user("bob4");
    assert_eq!(bob_skills.len(), 1);
    assert_eq!(bob_skills[0].manifest.description, "Bob version");
}

#[tokio::test]
async fn test_commit_install_allows_same_name_different_owner() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let alice_skill = make_skill_with_owner(
        "my-tool",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/my-tool")),
        "alice",
    );
    assert!(registry.commit_install("my-tool", alice_skill).is_ok());

    let bob_skill = make_skill_with_owner(
        "my-tool",
        SkillTrust::Installed,
        SkillSource::Installed(PathBuf::from("bob/my-tool")),
        "bob",
    );
    assert!(registry.commit_install("my-tool", bob_skill).is_ok());

    let alice_dup = make_skill_with_owner(
        "my-tool",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/my-tool")),
        "alice",
    );
    assert!(matches!(
        registry.commit_install("my-tool", alice_dup),
        Err(SkillRegistryError::AlreadyExists { .. })
    ));
}

#[tokio::test]
async fn test_validate_remove_rejects_other_users_skill() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content = skill_md("alice-skill", "Alice only");
    registry.install_skill(&content, "alice").await.unwrap();

    let result = registry.validate_remove("alice-skill", "bob");
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { .. })
    ));

    let result = registry.validate_remove("alice-skill", "alice");
    assert!(result.is_ok());
}

#[tokio::test]
async fn test_validate_remove_rejects_bundled_skill_for_any_user() {
    let dir = tempfile::tempdir().unwrap();
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "permanent".to_string(),
        "---\nname: permanent\n---\n\nCannot remove.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice").await;

    let result = registry.validate_remove("permanent", "alice");
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { reason, .. }) if reason.contains("global") || reason.contains("bundled")
    ));
}

#[tokio::test]
async fn test_commit_remove_only_removes_owners_skill() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let alice_skill = make_skill_with_owner(
        "shared",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/shared")),
        "alice",
    );
    registry.commit_install("shared", alice_skill).unwrap();

    let bob_skill = make_skill_with_owner(
        "shared",
        SkillTrust::Installed,
        SkillSource::Installed(PathBuf::from("bob/shared")),
        "bob",
    );
    registry.commit_install("shared", bob_skill).unwrap();

    assert_eq!(registry.skills().len(), 2);

    registry.commit_remove("shared", "alice").unwrap();

    assert_eq!(registry.skills().len(), 1);
    assert_eq!(registry.skills()[0].owner_user_id, "bob");
}

#[tokio::test]
async fn test_commit_remove_rejects_global_skill() {
    let dir = tempfile::tempdir().unwrap();
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "global".to_string(),
        "---\nname: global\n---\n\nGlobal.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice").await;

    let result = registry.commit_remove("global", "alice");
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { reason, .. }) if reason.contains("global") || reason.contains("bundled")
    ));
}

#[tokio::test]
async fn test_commit_remove_rejects_other_users_skill() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let alice_skill = make_skill_with_owner(
        "alice-skill",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/my-skill")),
        "alice",
    );
    registry.commit_install("alice-skill", alice_skill).unwrap();

    let result = registry.commit_remove("alice-skill", "bob");
    assert!(matches!(
        result,
        Err(SkillRegistryError::CannotRemove { .. })
    ));
}

#[tokio::test]
async fn test_install_skill_allows_same_name_as_bundled() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![dir.path().to_path_buf()]);
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "shared-name".to_string(),
        "---\nname: shared-name\ndescription: Bundled version\n---\n\nBundled.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice").await;

    assert!(registry.has("shared-name"));

    let content = skill_md("shared-name", "User version");
    let result = registry.install_skill(&content, "alice").await;
    assert!(
        result.is_ok(),
        "User should be able to install skill with same name as bundled"
    );

    let common_count = registry
        .skills()
        .iter()
        .filter(|s| s.manifest.name == "shared-name")
        .count();
    assert!(common_count >= 2);
    let alice_skill = registry
        .find_by_name_for_user("shared-name", "alice")
        .unwrap();
    assert_eq!(alice_skill.owner_user_id, "alice");
}

#[tokio::test]
async fn test_discover_for_user_loads_skills_with_owner() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_users(&[
        ("alice24", vec![dir.path().to_path_buf()]),
        ("bob24", vec![dir.path().to_path_buf()]),
    ]);

    create_skill_dir(
        dir.path(),
        "alice-skill",
        &skill_md("alice-skill", "Alice's"),
        "alice24",
    )
    .await;
    create_skill_dir(
        dir.path(),
        "bob-skill",
        &skill_md("bob-skill", "Bob's"),
        "bob24",
    )
    .await;

    let registry = SkillRegistry::new(dir.path().to_path_buf());
    registry.discover_all("alice24").await;
    assert_eq!(registry.skills_for_user("alice24").len(), 1);

    let loaded = registry.discover_for_user("bob24").await;
    assert_eq!(loaded, vec!["bob-skill"]);

    assert_eq!(registry.skills_for_user("bob24").len(), 1);
    assert_eq!(registry.skills_for_user("alice24").len(), 1);
}

#[tokio::test]
async fn test_discover_for_user_idempotent_no_duplicate() {
    let alice_dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![alice_dir.path().to_path_buf()]);
    create_skill_dir(
        alice_dir.path(),
        "alice-skill",
        &skill_md("alice-skill", "Alice's"),
        "alice",
    )
    .await;

    let registry = SkillRegistry::new(alice_dir.path().to_path_buf());
    registry.discover_all("alice").await;

    let loaded = registry.discover_for_user("alice").await;
    assert!(loaded.is_empty());
    assert_eq!(
        registry
            .skills()
            .iter()
            .filter(|s| s.owner_user_id == "alice")
            .count(),
        1
    );
}

#[tokio::test]
async fn test_discover_for_user_finds_newly_added_skill() {
    let alice_dir = tempfile::tempdir().unwrap();
    register_afs_user("alice25", vec![alice_dir.path().to_path_buf()]);
    create_skill_dir(
        alice_dir.path(),
        "skill-a",
        &skill_md("skill-a", "First"),
        "alice25",
    )
    .await;

    let registry = SkillRegistry::new(alice_dir.path().to_path_buf());
    registry.discover_all("alice25").await;
    assert_eq!(registry.skills_for_user("alice25").len(), 1);

    create_skill_dir(
        alice_dir.path(),
        "skill-b",
        &skill_md("skill-b", "Newly added"),
        "alice25",
    )
    .await;

    let loaded = registry.discover_for_user("alice25").await;
    assert_eq!(loaded, vec!["skill-b"]);
    assert_eq!(registry.skills_for_user("alice25").len(), 2);
}

#[tokio::test]
async fn test_discover_for_user_user_skill_coexists_with_bundled() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice33", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "common-skill",
        &skill_md("common-skill", "User version"),
        "alice33",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "common-skill".to_string(),
        "---\nname: common-skill\ndescription: Bundled version\n---\n\nBundled prompt.\n"
            .to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice33").await;

    let common_count = registry
        .skills()
        .iter()
        .filter(|s| s.manifest.name == "common-skill")
        .count();
    assert_eq!(
        common_count, 2,
        "user version and global version should coexist"
    );

    let alice_skill = registry
        .find_by_name_for_user("common-skill", "alice33")
        .unwrap();
    assert_eq!(alice_skill.owner_user_id, "alice33");

    // bob has no user-skill, so find_by_name_for_user falls back to bundled
    let bob_skill = registry
        .find_by_name_for_user("common-skill", "bob33")
        .unwrap();
    assert!(bob_skill.owner_user_id.is_empty());
}

#[tokio::test]
async fn test_discover_all_sets_owner_on_user_skills() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice26", vec![dir.path().to_path_buf()]);
    create_skill_dir(
        dir.path(),
        "my-skill",
        &skill_md("my-skill", "User skill"),
        "alice26",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "global-skill".to_string(),
        "---\nname: global-skill\n---\n\nGlobal.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice26").await;

    let user_skill = registry.find_owned("my-skill", "alice26").unwrap();
    assert_eq!(user_skill.owner_user_id, "alice26");

    let skills = registry.skills();
    let global_skill = skills
        .iter()
        .find(|s| s.manifest.name == "global-skill")
        .unwrap();
    assert!(global_skill.owner_user_id.is_empty());
}

#[tokio::test]
async fn test_install_skill_sets_owner_user_id() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_user("alice", vec![dir.path().to_path_buf()]);
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let content = skill_md("installed-skill", "New skill");
    let name = registry.install_skill(&content, "alice").await.unwrap();

    let skill = registry.find_owned(&name, "alice").unwrap();
    assert_eq!(skill.owner_user_id, "alice");
}

#[tokio::test]
async fn test_reload_for_user_preserves_other_users_skills() {
    let alice_temp = tempfile::tempdir().unwrap();
    let alice_dir = alice_temp.path().to_path_buf();
    let bob_dir = alice_dir.clone();

    register_afs_users(&[
        ("alice6", vec![alice_dir.clone()]),
        ("bob6", vec![bob_dir.clone()]),
    ]);

    create_skill_dir(
        alice_dir.as_path(),
        "alice-skill",
        &skill_md("alice-skill", "Alice"),
        "alice6",
    )
    .await;
    create_skill_dir(
        bob_dir.as_path(),
        "bob-skill",
        &skill_md("bob-skill", "Bob"),
        "bob6",
    )
    .await;

    let mut registry = SkillRegistry::new(alice_dir.to_path_buf());
    registry.discover_all("alice6").await;
    registry.discover_for_user("bob6").await;

    assert_eq!(registry.skills().len(), 2);

    let loaded = registry.reload_for_user("alice6").await;
    assert!(loaded.contains(&"alice-skill".to_string()));

    assert!(registry.find_owned("bob-skill", "bob6").is_some());
    assert_eq!(registry.skills_for_user("bob6").len(), 1);
}

#[tokio::test]
async fn test_bundled_skill_deletion_completely_blocked() {
    let dir = tempfile::tempdir().unwrap();
    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "system-skill".to_string(),
        "---\nname: system-skill\n---\n\nSystem critical.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);
    registry.discover_all("alice").await;

    let v_result = registry.validate_remove("system-skill", "alice");
    assert!(v_result.is_err());

    let c_result = registry.commit_remove("system-skill", "alice");
    assert!(c_result.is_err());

    let r_result = registry.remove_skill("system-skill", "alice").await;
    assert!(r_result.is_err());

    assert!(registry.has("system-skill"));
    assert_eq!(registry.skills().len(), 1);
}

#[tokio::test]
async fn test_commit_remove_in_multi_user_same_name_scenario() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    for user in &["alice", "bob", "charlie"] {
        let skill = make_skill_with_owner(
            "team-skill",
            SkillTrust::Trusted,
            SkillSource::User(PathBuf::from(format!("{}/team-skill", user))),
            user,
        );
        registry.commit_install("team-skill", skill).unwrap();
    }

    assert_eq!(registry.skills().len(), 3);

    registry.commit_remove("team-skill", "alice").unwrap();
    assert_eq!(registry.skills().len(), 2);
    let skills = registry.skills();
    let remaining_owners: Vec<&str> = skills.iter().map(|s| s.owner_user_id.as_str()).collect();
    assert!(remaining_owners.contains(&"bob"));
    assert!(remaining_owners.contains(&"charlie"));
    assert!(!remaining_owners.contains(&"alice"));
}

#[test]
fn test_find_owned_returns_none_for_nonexistent() {
    let registry = SkillRegistry::new(PathBuf::from("/nonexistent"));
    assert!(registry.find_owned("no-skill", "alice").is_none());
}

#[test]
fn test_find_by_name_for_user_returns_none_for_nonexistent() {
    let registry = SkillRegistry::new(PathBuf::from("/nonexistent"));
    assert!(
        registry
            .find_by_name_for_user("no-skill", "alice")
            .is_none()
    );
}

#[test]
fn test_validate_remove_returns_not_found_for_missing_skill() {
    let registry = SkillRegistry::new(PathBuf::from("/nonexistent"));
    let result = registry.validate_remove("no-skill", "alice");
    assert!(matches!(result, Err(SkillRegistryError::NotFound(_))));
}

#[test]
fn test_commit_remove_returns_not_found_for_missing_skill() {
    let registry = SkillRegistry::new(PathBuf::from("/nonexistent"));
    let result = registry.commit_remove("no-skill", "alice");
    assert!(matches!(result, Err(SkillRegistryError::NotFound(_))));
}

#[tokio::test]
async fn test_full_multi_user_scenario() {
    let dir = tempfile::tempdir().unwrap();
    register_afs_users(&[
        ("alice19", vec![dir.path().to_path_buf()]),
        ("bob19", vec![dir.path().to_path_buf()]),
    ]);

    create_skill_dir(
        dir.path(),
        "alice-a",
        &skill_md("alice-a", "Alice A"),
        "alice19",
    )
    .await;
    create_skill_dir(
        dir.path(),
        "common",
        &skill_md("common", "Alice common"),
        "alice19",
    )
    .await;
    create_skill_dir(dir.path(), "bob-b", &skill_md("bob-b", "Bob B"), "bob19").await;
    create_skill_dir(
        dir.path(),
        "common",
        &skill_md("common", "Bob common"),
        "bob19",
    )
    .await;

    let bundled: &'static [(String, String)] = Box::leak(Box::new(vec![(
        "global".to_string(),
        "---\nname: global\n---\n\nGlobal.\n".to_string(),
    )]));

    let registry = SkillRegistry::new(dir.path().to_path_buf()).with_bundled_content(bundled);

    registry.discover_all("alice19").await;
    let alice_skills = registry.skills_for_user("alice19");
    assert_eq!(alice_skills.len(), 3);

    registry.discover_for_user("bob19").await;

    let alice_skills = registry.skills_for_user("alice19");
    assert_eq!(alice_skills.len(), 3);

    let bob_skills = registry.skills_for_user("bob19");
    assert_eq!(bob_skills.len(), 3);

    let alice_common = registry.find_by_name_for_user("common", "alice19").unwrap();
    assert_eq!(alice_common.manifest.description, "Alice common");
    let bob_common = registry.find_by_name_for_user("common", "bob19").unwrap();
    assert_eq!(bob_common.manifest.description, "Bob common");

    assert!(matches!(
        registry.validate_remove("bob-b", "alice19"),
        Err(SkillRegistryError::CannotRemove { .. })
    ));
    assert!(matches!(
        registry.validate_remove("global", "alice19"),
        Err(SkillRegistryError::CannotRemove { .. })
    ));

    registry.remove_skill("common", "alice19").await.unwrap();

    let alice_skills = registry.skills_for_user("alice19");
    assert_eq!(alice_skills.len(), 2);

    let bob_skills = registry.skills_for_user("bob19");
    assert_eq!(bob_skills.len(), 3);
}

// ── commit_install_or_replace ────────────────────────────────

#[tokio::test]
async fn test_commit_install_or_replace_replaces_same_owner_skill() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    // Install initial version
    let v1 = make_skill_with_owner(
        "my-skill",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/my-skill")),
        "alice",
    );
    assert!(registry.commit_install("my-skill", v1).is_ok());

    // Same owner, same name → AlreadyExists
    let v2_dup = make_skill_with_owner(
        "my-skill",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/my-skill")),
        "alice",
    );
    assert!(matches!(
        registry.commit_install("my-skill", v2_dup),
        Err(SkillRegistryError::AlreadyExists { .. })
    ));

    // commit_install_or_replace succeeds, replacing v1 with v2
    let v2 = make_skill_with_owner(
        "my-skill",
        SkillTrust::Installed,
        SkillSource::Installed(PathBuf::from("alice/my-skill-v2")),
        "alice",
    );
    assert!(registry.commit_install_or_replace("my-skill", v2).is_ok());

    // Only one skill with this name for alice
    let alice_skills = registry.skills_for_user("alice");
    assert_eq!(alice_skills.len(), 1);
    assert_eq!(alice_skills[0].trust, SkillTrust::Installed);
}

#[tokio::test]
async fn test_commit_install_or_replace_does_not_affect_other_owners() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let alice_skill = make_skill_with_owner(
        "shared",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/shared")),
        "alice",
    );
    let bob_skill = make_skill_with_owner(
        "shared",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("bob/shared")),
        "bob",
    );
    registry.commit_install("shared", alice_skill).unwrap();
    registry.commit_install("shared", bob_skill).unwrap();
    assert_eq!(registry.skills().len(), 2);

    // Alice replaces her version — Bob's must be unaffected
    let alice_v2 = make_skill_with_owner(
        "shared",
        SkillTrust::Installed,
        SkillSource::Installed(PathBuf::from("alice/shared-v2")),
        "alice",
    );
    registry
        .commit_install_or_replace("shared", alice_v2)
        .unwrap();

    assert_eq!(registry.skills().len(), 2);
    let bob_skill = registry.find_owned("shared", "bob").unwrap();
    assert_eq!(bob_skill.trust, SkillTrust::Trusted);
    let alice_skill = registry.find_owned("shared", "alice").unwrap();
    assert_eq!(alice_skill.trust, SkillTrust::Installed);
}

#[tokio::test]
async fn test_commit_install_or_replace_installs_new_when_not_exists() {
    let dir = tempfile::tempdir().unwrap();
    let registry = SkillRegistry::new(dir.path().to_path_buf());

    let skill = make_skill_with_owner(
        "new-skill",
        SkillTrust::Trusted,
        SkillSource::User(PathBuf::from("alice/new-skill")),
        "alice",
    );
    assert!(
        registry
            .commit_install_or_replace("new-skill", skill)
            .is_ok()
    );
    assert_eq!(registry.skills_for_user("alice").len(), 1);
}
