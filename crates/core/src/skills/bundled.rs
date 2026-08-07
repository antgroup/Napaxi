//! Embedded bundled skill content and startup deploy.
//!
//! Skills in `bundled_seeds/` are compiled into the binary via `include_str!`
//! and written to `{skills_root}/app_bundled/` on engine startup. This provides
//! offline-ready, high-quality skills without network dependency.

use std::path::PathBuf;

use super::paths::app_bundled_skills_dir;

/// Current bundled skill set version. Increment when updating seed content
/// to trigger re-deployment on next engine start.
const BUNDLED_VERSION: u32 = 17;

struct BundledSkill {
    slug: &'static str,
    files: &'static [(&'static str, &'static str)],
}

/// Embedded skill content: skill slug plus files relative to the skill directory.
const BUNDLED_SKILLS: &[BundledSkill] = &[
    BundledSkill {
        slug: "android-apk-build",
        files: &[
            (
                "SKILL.md",
                include_str!("bundled_seeds/android-apk-build/SKILL.md"),
            ),
            (
                "scripts/build_apk.sh",
                include_str!("bundled_seeds/android-apk-build/scripts/build_apk.sh"),
            ),
            (
                "templates/agent-app.json.template",
                include_str!("bundled_seeds/android-apk-build/templates/agent-app.json.template"),
            ),
            (
                "templates/NapaxiActionActivity.java.template",
                include_str!(
                    "bundled_seeds/android-apk-build/templates/NapaxiActionActivity.java.template"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderLite.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderLite.java"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderInstallActivity.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderInstallActivity.java"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderActionRegistry.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderActionRegistry.java"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderDiagnostics.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderDiagnostics.java"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderDiagnosticsInitializer.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderDiagnosticsInitializer.java"
                ),
            ),
            (
                "sdk/java/agent/provider/lite/AgentProviderDiagnosticsActivity.java",
                include_str!(
                    "../../../../packages/agent_provider/android_lite/src/main/java/agent/provider/lite/AgentProviderDiagnosticsActivity.java"
                ),
            ),
        ],
    },
    BundledSkill {
        slug: "web-researcher",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/web-researcher/SKILL.md"),
        )],
    },
    BundledSkill {
        slug: "code-helper",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/code-helper/SKILL.md"),
        )],
    },
    BundledSkill {
        slug: "translator",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/translator/SKILL.md"),
        )],
    },
    BundledSkill {
        slug: "summarizer",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/summarizer/SKILL.md"),
        )],
    },
    BundledSkill {
        slug: "daily-planner",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/daily-planner/SKILL.md"),
        )],
    },
    BundledSkill {
        slug: "writing-assistant",
        files: &[(
            "SKILL.md",
            include_str!("bundled_seeds/writing-assistant/SKILL.md"),
        )],
    },
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

    for skill in BUNDLED_SKILLS {
        let skill_dir = base.join(skill.slug);
        if std::fs::create_dir_all(&skill_dir).is_err() {
            continue;
        }
        for (relative_path, content) in skill.files {
            let target = skill_dir.join(relative_path);
            if let Some(parent) = target.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(&target, content);
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
    use std::process::Command;

    #[test]
    fn test_ensure_bundled_skills_creates_files() {
        let tmp = tempfile::tempdir().unwrap();
        let files_dir = tmp.path().to_str().unwrap();

        ensure_bundled_skills(files_dir);

        let base = app_bundled_skills_dir(files_dir);
        assert!(base.join("android-apk-build/SKILL.md").exists());
        let build_script = base.join("android-apk-build/scripts/build_apk.sh");
        assert!(build_script.exists());
        let build_script_content = std::fs::read_to_string(build_script).unwrap();
        assert!(build_script_content.contains("base.zip"));
        assert!(build_script_content.contains("cleanup_intermediate_outputs"));
        assert!(build_script_content.contains("Agent App Provider support enabled"));
        assert!(build_script_content.contains("--without-agent-provider"));
        assert!(build_script_content.contains("AgentProviderActionRegistry"));
        assert!(build_script_content.contains("agent.provider.action.HANDLE_PROPOSAL"));
        assert!(!build_script_content.contains("base.apk"));
        assert!(
            base.join("android-apk-build/sdk/java/agent/provider/lite/AgentProviderLite.java")
                .exists()
        );
        assert!(
            base.join(
                "android-apk-build/sdk/java/agent/provider/lite/AgentProviderActionRegistry.java"
            )
            .exists()
        );
        let diagnostics = base
            .join("android-apk-build/sdk/java/agent/provider/lite/AgentProviderDiagnostics.java");
        assert!(diagnostics.exists());
        let diagnostics_content = std::fs::read_to_string(diagnostics).unwrap();
        assert!(diagnostics_content.contains("MAX_LOGS = 300"));
        assert!(diagnostics_content.contains("setDetailedLoggingEnabled"));
        assert!(
            base.join(
                "android-apk-build/sdk/java/agent/provider/lite/AgentProviderDiagnosticsActivity.java"
            )
            .exists()
        );
        assert!(
            base.join("android-apk-build/templates/agent-app.json.template")
                .exists()
        );
        assert!(
            base.join("android-apk-build/templates/NapaxiActionActivity.java.template")
                .exists()
        );
        assert!(base.join("web-researcher/SKILL.md").exists());
        assert!(base.join("code-helper/SKILL.md").exists());
        assert!(base.join("translator/SKILL.md").exists());
        assert!(base.join("summarizer/SKILL.md").exists());
        assert!(base.join("daily-planner/SKILL.md").exists());
        assert!(base.join("writing-assistant/SKILL.md").exists());
        assert!(base.join(".version").exists());

        let version = std::fs::read_to_string(base.join(".version")).unwrap();
        assert_eq!(version.trim(), BUNDLED_VERSION.to_string());
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
    fn test_android_provider_project_validator_is_generic_and_fails_closed() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let script = root
            .join("crates/core/src/skills/bundled_seeds/android-apk-build/scripts/build_apk.sh");
        for example in ["android_generated_notes", "android_generated_tasks"] {
            let status = Command::new("bash")
                .arg(&script)
                .args(["--project-dir"])
                .arg(root.join("examples/provider_app").join(example))
                .arg("--validate-only")
                .status()
                .unwrap();
            assert!(status.success(), "validator rejected {example}");
        }

        let temp = tempfile::tempdir().unwrap();
        let source = temp.path().join("app/src/main");
        std::fs::create_dir_all(source.join("assets")).unwrap();
        std::fs::create_dir_all(source.join("java/demo/invalid")).unwrap();
        std::fs::create_dir_all(source.join("res/values")).unwrap();
        std::fs::write(
            source.join("AndroidManifest.xml"),
            r#"<manifest><application>
              <meta-data android:name="agent.provider.TRUSTED_REFRESH_SUPPORTED" android:value="true" />
              <activity><intent-filter><action android:name="agent.provider.action.INSTALL_AGENT" /></intent-filter></activity>
              <activity><intent-filter><action android:name="agent.provider.action.HANDLE_PROPOSAL" /></intent-filter></activity>
            </application></manifest>"#,
        )
        .unwrap();
        std::fs::write(
            source.join("assets/agent-app.json"),
            r#"{
              "provider_id": "demo.invalid",
              "agent_id": "demo.invalid.agent",
              "display_name": "Invalid",
              "actions": [
                {
                  "action_id": "item.create"
                }
              ]
            }"#,
        )
        .unwrap();
        std::fs::write(
            source.join("java/demo/invalid/NapaxiActionActivity.java"),
            "class NapaxiActionActivity { AgentProviderActionRegistry registry; }",
        )
        .unwrap();
        std::fs::write(source.join("res/values/strings.xml"), "<resources/>").unwrap();

        let output = Command::new("bash")
            .arg(&script)
            .args(["--project-dir"])
            .arg(temp.path())
            .arg("--validate-only")
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(
            String::from_utf8_lossy(&output.stderr)
                .contains("has no AgentProviderActionRegistry handlers")
        );

        std::fs::write(
            source.join("java/demo/invalid/NapaxiActionActivity.java"),
            r#"class NapaxiActionActivity {
              AgentProviderActionRegistry registry;
              void register() {
                registry.register("item.create", true, null);
                registry.register("item.extra", false, null);
              }
            }"#,
        )
        .unwrap();
        let extra_handler = Command::new("bash")
            .arg(&script)
            .args(["--project-dir"])
            .arg(temp.path())
            .arg("--validate-only")
            .output()
            .unwrap();
        assert!(!extra_handler.status.success());
        assert!(
            String::from_utf8_lossy(&extra_handler.stderr)
                .contains("handler is not declared in agent-app.json: item.extra")
        );

        let conflicting_opt_out = Command::new("bash")
            .arg(&script)
            .args(["--project-dir"])
            .arg(temp.path())
            .args(["--without-agent-provider", "--validate-only"])
            .output()
            .unwrap();
        assert!(!conflicting_opt_out.status.success());
        assert!(
            String::from_utf8_lossy(&conflicting_opt_out.stderr)
                .contains("conflicts with assets/agent-app.json")
        );

        std::fs::remove_file(source.join("assets/agent-app.json")).unwrap();
        std::fs::write(
            source.join("AndroidManifest.xml"),
            "<manifest><application /></manifest>",
        )
        .unwrap();
        let legacy = Command::new("bash")
            .arg(&script)
            .args(["--project-dir"])
            .arg(temp.path())
            .arg("--validate-only")
            .status()
            .unwrap();
        assert!(legacy.success(), "legacy project should remain buildable");
        let explicit_opt_out = Command::new("bash")
            .arg(&script)
            .args(["--project-dir"])
            .arg(temp.path())
            .args(["--without-agent-provider", "--validate-only"])
            .status()
            .unwrap();
        assert!(explicit_opt_out.success());
    }

    #[test]
    fn test_bundled_skill_count() {
        assert_eq!(BUNDLED_SKILLS.len(), 7);
    }

    #[test]
    fn test_all_bundled_skills_have_valid_content() {
        for skill in BUNDLED_SKILLS {
            assert!(!skill.slug.is_empty(), "slug must not be empty");
            let content = skill
                .files
                .iter()
                .find_map(|(path, content)| (*path == "SKILL.md").then_some(*content))
                .unwrap_or_else(|| panic!("skill {} must include SKILL.md", skill.slug));
            assert!(
                content.starts_with("---"),
                "skill {} must have YAML frontmatter",
                skill.slug
            );
            assert!(
                content.contains("\n---\n"),
                "skill {} must have closing frontmatter delimiter",
                skill.slug
            );
        }
    }
}
