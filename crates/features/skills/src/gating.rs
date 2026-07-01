//! Requirements gating for skills.
//!
//! Checks that a skill's declared requirements (binaries, environment variables,
//! config files) are satisfied before the skill is loaded.

use std::collections::HashSet;

use crate::types::{GatingRequirements, MissingRequirements, SkillReadinessContext};

/// Result of a gating check.
#[derive(Debug)]
pub struct GatingResult {
    /// Whether all requirements passed.
    pub passed: bool,
    /// Descriptions of failed requirements.
    pub failures: Vec<String>,
    /// Structured missing requirements for UI/status diagnostics.
    pub missing: MissingRequirements,
}

/// Async wrapper around [`check_requirements_sync`] that offloads blocking
/// subprocess calls (`which`/`where`) to a blocking thread pool via
/// `tokio::task::spawn_blocking`.
///
/// Fast path: if the requirements contain no bins, env vars, or config
/// paths to check, return `passed: true` immediately without spawning a
/// blocking task. Companion `skills` entries are advisory-only and do not
/// affect gating, so they don't block the fast path. This avoids a
/// `which` subprocess call per skill load for skills with no
/// subprocess-checkable requirements (the common case).
pub async fn check_requirements(requirements: &GatingRequirements) -> GatingResult {
    if requirements.is_empty() {
        return GatingResult {
            passed: true,
            failures: Vec::new(),
            missing: MissingRequirements::default(),
        };
    }

    let requirements = requirements.clone();
    tokio::task::spawn_blocking(move || check_requirements_sync(&requirements))
        .await
        .unwrap_or_else(|e| {
            let message = if e.is_panic() {
                format!("gating check panicked: {}", e)
            } else if e.is_cancelled() {
                format!("gating check task was cancelled: {}", e)
            } else {
                format!("gating check failed to join: {}", e)
            };
            tracing::error!("{}", message);
            GatingResult {
                passed: false,
                failures: vec![message],
                missing: MissingRequirements::default(),
            }
        })
}

pub async fn check_requirements_with_context(
    requirements: &GatingRequirements,
    context: &SkillReadinessContext,
) -> GatingResult {
    if requirements.is_empty() {
        return GatingResult {
            passed: true,
            failures: Vec::new(),
            missing: MissingRequirements::default(),
        };
    }

    let requirements = requirements.clone();
    let context = context.clone();
    tokio::task::spawn_blocking(move || {
        check_requirements_sync_with_context(&requirements, &context)
    })
    .await
    .unwrap_or_else(|e| {
        let message = if e.is_panic() {
            format!("gating check panicked: {}", e)
        } else if e.is_cancelled() {
            format!("gating check task was cancelled: {}", e)
        } else {
            format!("gating check failed to join: {}", e)
        };
        tracing::error!("{}", message);
        GatingResult {
            passed: false,
            failures: vec![message],
            missing: MissingRequirements::default(),
        }
    })
}

/// Check whether gating requirements are satisfied (synchronous).
///
/// - `bins`: checks that each binary is findable via `which` (PATH lookup).
/// - `env`: checks that each environment variable is set.
/// - `config`: checks that each config file path exists.
///
/// Skills that fail gating should be logged and skipped, not loaded.
///
/// This is the synchronous implementation; prefer the async [`check_requirements`]
/// wrapper when calling from async contexts to avoid blocking the tokio runtime.
pub fn check_requirements_sync(requirements: &GatingRequirements) -> GatingResult {
    check_requirements_sync_with_context(
        requirements,
        &SkillReadinessContext {
            use_process_fallback: true,
            ..Default::default()
        },
    )
}

pub fn check_requirements_sync_with_context(
    requirements: &GatingRequirements,
    context: &SkillReadinessContext,
) -> GatingResult {
    let mut failures = Vec::new();
    let mut missing = MissingRequirements::default();
    let available_bins = normalized_set(&context.available_bins);
    let env_keys = normalized_set(&context.env_keys);
    let config_flags = normalized_set(&context.config_flags);
    let capabilities = normalized_set(&context.capabilities);

    for bin in &requirements.bins {
        if !contains_or_fallback(
            &available_bins,
            bin,
            context.use_process_fallback,
            binary_exists,
        ) {
            failures.push(format!("required binary not found: {}", bin));
            missing.bins.push(bin.clone());
        }
    }

    if !requirements.any_bins.is_empty()
        && !requirements.any_bins.iter().any(|bin| {
            contains_or_fallback(
                &available_bins,
                bin,
                context.use_process_fallback,
                binary_exists,
            )
        })
    {
        failures.push(format!(
            "none of the alternative binaries were found: {}",
            requirements.any_bins.join(", ")
        ));
        missing.any_bins = requirements.any_bins.clone();
    }

    for var in &requirements.env {
        let present = env_keys.contains(&normalize_key(var))
            || (context.use_process_fallback && std::env::var(var).is_ok());
        if !present {
            failures.push(format!("required env var not set: {}", var));
            missing.env.push(var.clone());
        }
    }

    for path in &requirements.config {
        let present = config_flags.contains(&normalize_key(path))
            || (context.use_process_fallback && std::path::Path::new(path).exists());
        if !present {
            failures.push(format!("required config not found: {}", path));
            missing.config.push(path.clone());
        }
    }

    if !requirements.os.is_empty()
        && !platform_matches(&requirements.os, context.platform.as_deref())
    {
        failures.push(format!(
            "skill does not support platform: {}",
            context.platform.as_deref().unwrap_or("unknown")
        ));
        missing.os = requirements.os.clone();
    }

    for capability in &requirements.capabilities {
        if !capabilities.contains(&normalize_key(capability)) {
            failures.push(format!("required capability not enabled: {}", capability));
            missing.capabilities.push(capability.clone());
        }
    }

    // Companion skill dependencies (`requirements.skills`) are intentionally
    // not checked here — the gating module has no access to the skill
    // registry. They are advisory metadata only.

    GatingResult {
        passed: failures.is_empty(),
        failures,
        missing,
    }
}

fn normalized_set(items: &[String]) -> HashSet<String> {
    items.iter().map(|item| normalize_key(item)).collect()
}

fn normalize_key(value: &str) -> String {
    value.trim().to_lowercase()
}

fn contains_or_fallback(
    available: &HashSet<String>,
    value: &str,
    use_fallback: bool,
    fallback: impl Fn(&str) -> bool,
) -> bool {
    available.contains(&normalize_key(value)) || (use_fallback && fallback(value))
}

fn platform_matches(required: &[String], platform: Option<&str>) -> bool {
    let platform = platform.unwrap_or("").trim().to_lowercase();
    required.iter().any(|candidate| {
        let candidate = candidate.trim().to_lowercase();
        candidate == "all" || (!platform.is_empty() && candidate == platform)
    })
}

/// Check if a binary exists on PATH using `std::process::Command`.
pub fn binary_exists(name: &str) -> bool {
    #[cfg(unix)]
    {
        std::process::Command::new("which")
            .arg(name)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
    }
    #[cfg(windows)]
    {
        std::process::Command::new("where")
            .arg(name)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .is_ok_and(|s| s.success())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_requirements_pass() {
        let req = GatingRequirements::default();
        let result = check_requirements_sync(&req);
        assert!(result.passed);
        assert!(result.failures.is_empty());
    }

    #[test]
    fn test_missing_binary_fails() {
        let req = GatingRequirements {
            bins: vec!["__napaxi_nonexistent_binary_xyz__".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(!result.passed);
        assert_eq!(result.failures.len(), 1);
        assert!(result.failures[0].contains("binary not found"));
        assert_eq!(
            result.missing.bins,
            vec!["__napaxi_nonexistent_binary_xyz__"]
        );
    }

    #[test]
    fn test_missing_env_var_fails() {
        let req = GatingRequirements {
            env: vec!["__NAPAXI_TEST_NONEXISTENT_VAR__".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(!result.passed);
        assert!(result.failures[0].contains("env var not set"));
    }

    #[test]
    fn test_present_env_var_passes() {
        let req = GatingRequirements {
            env: vec!["PATH".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(result.passed);
    }

    #[test]
    fn test_missing_config_fails() {
        let req = GatingRequirements {
            config: vec!["/nonexistent/path/napaxi_test.conf".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(!result.passed);
        assert!(result.failures[0].contains("config not found"));
    }

    #[test]
    fn test_multiple_mixed_requirements() {
        let req = GatingRequirements {
            bins: vec!["__no_such_bin__".to_string()],
            env: vec!["__NO_SUCH_VAR__".to_string()],
            config: vec!["/no/such/file".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(!result.passed);
        assert_eq!(result.failures.len(), 3);
    }

    #[test]
    fn test_skill_dependencies_are_ignored_by_gating() {
        // Companion skill dependencies are advisory metadata only — gating
        // does not check them. Gating should pass even when `skills` is
        // populated.
        let req = GatingRequirements {
            skills: vec![
                "commitment-triage".to_string(),
                "commitment-digest".to_string(),
            ],
            ..Default::default()
        };
        let result = check_requirements_sync(&req);
        assert!(result.passed);
        assert!(result.failures.is_empty());
    }

    #[test]
    fn test_context_any_bins_and_platform() {
        let req = GatingRequirements {
            any_bins: vec!["node".to_string(), "bun".to_string()],
            os: vec!["android".to_string()],
            capabilities: vec!["napaxi.platform_tool.open_url".to_string()],
            ..Default::default()
        };
        let context = SkillReadinessContext {
            platform: Some("android".to_string()),
            available_bins: vec!["bun".to_string()],
            capabilities: vec!["napaxi.platform_tool.open_url".to_string()],
            ..Default::default()
        };
        let result = check_requirements_sync_with_context(&req, &context);
        assert!(result.passed);
    }
}
