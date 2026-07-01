//! Skill readiness/status diagnostics.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::config::{SkillConfigStore, load_skill_config, skill_config_key};
use super::paths::normalize_agent_id;
use super::source_registry::source_roots;
use super::usage::{lifecycle_json, load_usage_map};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillStatusReport {
    pub entries: Vec<SkillStatusEntry>,
    pub ready: usize,
    pub disabled: usize,
    pub blocked: usize,
    pub missing_requirements: usize,
    pub parse_error: usize,
    pub security_blocked: usize,
    pub too_large: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillStatusEntry {
    pub name: String,
    pub description: String,
    pub source_kind: String,
    pub source: String,
    pub trust: String,
    pub enabled: bool,
    pub eligible: bool,
    pub status: String,
    pub requirements: RequirementSummary,
    pub missing: napaxi_skills::MissingRequirements,
    pub install_options: Vec<serde_json::Value>,
    pub warnings: Vec<String>,
    pub error: Option<String>,
    pub lifecycle: serde_json::Value,
    pub metadata: OpenClawSkillMetadata,
    pub provenance: SkillProvenance,
    #[serde(default)]
    pub remediation_actions: Vec<SkillRemediationAction>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RequirementSummary {
    pub bins: Vec<String>,
    pub any_bins: Vec<String>,
    pub env: Vec<String>,
    pub config: Vec<String>,
    pub os: Vec<String>,
    pub capabilities: Vec<String>,
    pub skills: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct OpenClawSkillMetadata {
    pub user_invocable: bool,
    pub disable_model_invocation: bool,
    pub command_dispatch: Option<String>,
    pub command_tool: Option<String>,
    pub command_arg_mode: Option<String>,
    pub primary_env: Option<String>,
    pub skill_key: Option<String>,
    pub homepage: Option<String>,
    pub emoji: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SkillProvenance {
    pub source_kind: String,
    pub trust: String,
    pub managed_by: String,
    pub legacy: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillRemediationAction {
    pub id: String,
    pub kind: String,
    pub label: String,
    pub requirement: String,
    pub host_handled: bool,
    pub danger_level: String,
}

#[derive(Debug, Clone, Copy)]
enum Status {
    Ready,
    Disabled,
    Blocked,
    MissingRequirements,
    ParseError,
    SecurityBlocked,
    TooLarge,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Disabled => "disabled",
            Self::Blocked => "blocked",
            Self::MissingRequirements => "missing_requirements",
            Self::ParseError => "parse_error",
            Self::SecurityBlocked => "security_blocked",
            Self::TooLarge => "too_large",
        }
    }
}

pub async fn list_skill_status(
    files_dir: &str,
    agent_id: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
) -> String {
    let agent_id = normalize_agent_id(agent_id);
    let config = load_skill_config(files_dir, &agent_id).await;
    let readiness = config.apply_to_readiness(readiness);
    let mut entries = Vec::new();
    let mut seen = HashSet::new();
    let usage = load_usage_map(files_dir, &agent_id).await;
    for source in source_roots(files_dir, &agent_id) {
        let mut scanned = scan_status_dir(
            &source.root,
            &source.kind,
            source.trust,
            &readiness,
            &usage,
            &config,
        )
        .await;
        for entry in scanned.drain(..) {
            let key = entry.name.to_lowercase();
            if !key.is_empty() && !seen.insert(key) {
                continue;
            }
            entries.push(entry);
        }
    }

    entries.sort_by(|left, right| {
        left.status
            .cmp(&right.status)
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    let report = build_report(entries);
    serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string())
}

pub async fn get_skill_status(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
) -> String {
    let report = list_skill_status(files_dir, agent_id, readiness).await;
    let Ok(report) = serde_json::from_str::<serde_json::Value>(&report) else {
        return "null".to_string();
    };
    let Some(entries) = report.get("entries").and_then(serde_json::Value::as_array) else {
        return "null".to_string();
    };
    entries
        .iter()
        .find(|entry| {
            entry
                .get("name")
                .and_then(serde_json::Value::as_str)
                .map(|name| name == skill_name)
                .unwrap_or(false)
        })
        .map(serde_json::Value::to_string)
        .unwrap_or_else(|| "null".to_string())
}

pub async fn check_skills(
    files_dir: &str,
    agent_id: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
) -> String {
    let report = list_skill_status(files_dir, agent_id, readiness).await;
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&report) else {
        return "{}".to_string();
    };
    let entries = value
        .get("entries")
        .and_then(serde_json::Value::as_array)
        .cloned()
        .unwrap_or_default();
    let blockers = entries
        .iter()
        .filter(|entry| {
            matches!(
                entry.get("status").and_then(serde_json::Value::as_str),
                Some("missing_requirements" | "security_blocked" | "parse_error" | "too_large")
            )
        })
        .take(5)
        .cloned()
        .collect::<Vec<_>>();
    serde_json::json!({
        "ready": value.get("ready").cloned().unwrap_or_default(),
        "disabled": value.get("disabled").cloned().unwrap_or_default(),
        "blocked": value.get("blocked").cloned().unwrap_or_default(),
        "missing_requirements": value.get("missing_requirements").cloned().unwrap_or_default(),
        "parse_error": value.get("parse_error").cloned().unwrap_or_default(),
        "security_blocked": value.get("security_blocked").cloned().unwrap_or_default(),
        "too_large": value.get("too_large").cloned().unwrap_or_default(),
        "top_blockers": blockers,
    })
    .to_string()
}

pub async fn list_skill_remediation_actions(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
) -> String {
    let report = list_skill_status(files_dir, agent_id, readiness).await;
    let Ok(report) = serde_json::from_str::<SkillStatusReport>(&report) else {
        return "[]".to_string();
    };
    report
        .entries
        .into_iter()
        .find(|entry| entry.name == skill_name)
        .map(|entry| {
            serde_json::to_string(&entry.remediation_actions).unwrap_or_else(|_| "[]".to_string())
        })
        .unwrap_or_else(|| "[]".to_string())
}

pub async fn list_skill_status_handle(handle: i64, agent_id: &str) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return "{}".to_string();
    };
    list_skill_status(&files_dir, agent_id, &readiness).await
}

pub async fn get_skill_status_handle(handle: i64, agent_id: &str, skill_name: &str) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return "null".to_string();
    };
    get_skill_status(&files_dir, agent_id, skill_name, &readiness).await
}

pub async fn check_skills_handle(handle: i64, agent_id: &str) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return "{}".to_string();
    };
    check_skills(&files_dir, agent_id, &readiness).await
}

pub async fn list_skill_remediation_actions_handle(
    handle: i64,
    agent_id: &str,
    skill_name: &str,
) -> String {
    let Some((files_dir, readiness)) = readiness_from_handle(handle) else {
        return "[]".to_string();
    };
    list_skill_remediation_actions(&files_dir, agent_id, skill_name, &readiness).await
}

fn readiness_from_handle(handle: i64) -> Option<(String, napaxi_skills::SkillReadinessContext)> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { crate::runtime::handle_to_arc(handle) }?;
    Some((
        engine.files_dir().to_string(),
        engine.skill_readiness_context(),
    ))
}

async fn scan_status_dir(
    root: &Path,
    source_kind: &str,
    trust: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
    usage: &HashMap<String, super::SkillUsageRecord>,
    config: &SkillConfigStore,
) -> Vec<SkillStatusEntry> {
    let Ok(mut dir) = tokio::fs::read_dir(root).await else {
        return Vec::new();
    };
    let mut entries = Vec::new();
    while let Ok(Some(entry)) = dir.next_entry().await {
        let path = entry.path();
        let Ok(metadata) = entry.metadata().await else {
            continue;
        };
        if metadata.is_dir() {
            let skill_md = path.join("SKILL.md");
            if skill_md.exists() {
                entries.push(
                    scan_skill_file(
                        &skill_md,
                        &path,
                        source_kind,
                        trust,
                        readiness,
                        usage,
                        config,
                    )
                    .await,
                );
            }
        } else if metadata.is_file()
            && path.file_name().and_then(|name| name.to_str()) == Some("SKILL.md")
        {
            entries.push(
                scan_skill_file(&path, root, source_kind, trust, readiness, usage, config).await,
            );
        }
    }
    entries
}

async fn scan_skill_file(
    skill_md: &Path,
    skill_dir: &Path,
    source_kind: &str,
    trust: &str,
    readiness: &napaxi_skills::SkillReadinessContext,
    usage: &HashMap<String, super::SkillUsageRecord>,
    config: &SkillConfigStore,
) -> SkillStatusEntry {
    let fallback_name = skill_dir
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("SKILL.md")
        .to_string();
    let source = skill_dir.display().to_string();
    let raw = match tokio::fs::read(skill_md).await {
        Ok(raw) => raw,
        Err(error) => {
            return error_entry(
                fallback_name,
                source_kind,
                trust,
                source,
                Status::Blocked,
                format!("read {}: {error}", skill_md.display()),
            );
        }
    };
    if raw.len() as u64 > napaxi_skills::MAX_PROMPT_FILE_SIZE {
        return error_entry(
            fallback_name,
            source_kind,
            trust,
            source,
            Status::TooLarge,
            format!(
                "SKILL.md is {} bytes (max {})",
                raw.len(),
                napaxi_skills::MAX_PROMPT_FILE_SIZE
            ),
        );
    }
    let content = match String::from_utf8(raw) {
        Ok(content) => content,
        Err(error) => {
            return error_entry(
                fallback_name,
                source_kind,
                trust,
                source,
                Status::ParseError,
                format!("invalid UTF-8: {error}"),
            );
        }
    };
    let parsed = match napaxi_skills::parse_skill_md(&content) {
        Ok(parsed) => parsed,
        Err(error) => {
            return error_entry(
                fallback_name,
                source_kind,
                trust,
                source,
                Status::ParseError,
                error.to_string(),
            );
        }
    };

    let mut warnings = Vec::new();
    if !config.is_enabled(&parsed.manifest) {
        return manifest_entry(
            &parsed.manifest,
            source_kind,
            trust,
            source,
            Status::Disabled,
            napaxi_skills::MissingRequirements::default(),
            warnings,
            None,
            usage,
            config,
        );
    }

    let security_support_files = collect_security_files(skill_dir).await;
    let mut security_files = vec![napaxi_skills::SkillSecurityFile {
        path: "SKILL.md",
        content: &content,
    }];
    for (path, support_content) in &security_support_files {
        security_files.push(napaxi_skills::SkillSecurityFile {
            path,
            content: support_content,
        });
    }
    let security = napaxi_skills::scan_skill_package(&security_files);
    warnings.extend(
        security
            .findings
            .iter()
            .filter(|finding| finding.severity == napaxi_skills::SkillSecuritySeverity::Warning)
            .map(|finding| format!("{}: {}", finding.category, finding.message)),
    );
    if security.has_critical_findings() {
        return manifest_entry(
            &parsed.manifest,
            source_kind,
            trust,
            source,
            Status::SecurityBlocked,
            napaxi_skills::MissingRequirements::default(),
            warnings,
            Some(security.critical_summary()),
            usage,
            config,
        );
    }

    let gating =
        napaxi_skills::check_requirements_with_context(&parsed.manifest.requires, readiness).await;
    if !gating.passed {
        return manifest_entry(
            &parsed.manifest,
            source_kind,
            trust,
            source,
            Status::MissingRequirements,
            gating.missing,
            warnings,
            Some(gating.failures.join("; ")),
            usage,
            config,
        );
    }

    manifest_entry(
        &parsed.manifest,
        source_kind,
        trust,
        source,
        Status::Ready,
        napaxi_skills::MissingRequirements::default(),
        warnings,
        None,
        usage,
        config,
    )
}

async fn collect_security_files(skill_dir: &Path) -> Vec<(String, String)> {
    let mut owned = Vec::<(String, String)>::new();
    collect_security_dir(skill_dir, skill_dir, &mut owned).await;
    owned
}

async fn collect_security_dir(skill_dir: &Path, dir: &Path, out: &mut Vec<(String, String)>) {
    if out.len() >= napaxi_skills::security::MAX_SECURITY_SCAN_FILES {
        return;
    }
    let Ok(mut entries) = tokio::fs::read_dir(dir).await else {
        return;
    };
    while let Ok(Some(entry)) = entries.next_entry().await {
        if out.len() >= napaxi_skills::security::MAX_SECURITY_SCAN_FILES {
            return;
        }
        let path = entry.path();
        let Ok(metadata) = tokio::fs::symlink_metadata(&path).await else {
            continue;
        };
        if metadata.file_type().is_symlink() {
            out.push((
                "__security_scan_error__".to_string(),
                "skill package contains a symlink in support files".to_string(),
            ));
            continue;
        }
        if is_hidden_security_path(skill_dir, &path) {
            continue;
        }
        if metadata.is_dir() {
            Box::pin(collect_security_dir(skill_dir, &path, out)).await;
        } else if metadata.is_file()
            && metadata.len() <= super::limits::MAX_EXTRA_FILE_SIZE
            && path_resolves_inside(skill_dir, &path).await
            && let Ok(content) = tokio::fs::read_to_string(&path).await
            && let Ok(relative) = path.strip_prefix(skill_dir)
            && relative != Path::new("SKILL.md")
            && relative != Path::new("_meta.json")
        {
            out.push((relative.display().to_string(), content));
        }
    }
}

fn is_hidden_security_path(root: &Path, path: &Path) -> bool {
    path.strip_prefix(root)
        .ok()
        .and_then(|relative| relative.components().next())
        .and_then(|component| match component {
            std::path::Component::Normal(part) => part.to_str(),
            _ => None,
        })
        .map(|part| part.starts_with('.'))
        .unwrap_or(false)
}

async fn path_resolves_inside(root: &Path, path: &Path) -> bool {
    let Ok(root) = tokio::fs::canonicalize(root).await else {
        return false;
    };
    let Ok(path) = tokio::fs::canonicalize(path).await else {
        return false;
    };
    path.starts_with(root)
}

fn manifest_entry(
    manifest: &napaxi_skills::SkillManifest,
    source_kind: &str,
    trust: &str,
    source: String,
    status: Status,
    missing: napaxi_skills::MissingRequirements,
    warnings: Vec<String>,
    error: Option<String>,
    usage: &HashMap<String, super::SkillUsageRecord>,
    config: &SkillConfigStore,
) -> SkillStatusEntry {
    let lifecycle = lifecycle_json(usage.get(&manifest.name));
    let enabled = config.is_enabled(manifest);
    let requirements = requirement_summary(&manifest.requires);
    let metadata = openclaw_metadata(manifest);
    let remediation_actions = remediation_actions_for(
        &manifest.name,
        &skill_config_key(manifest),
        status,
        &requirements,
        &missing,
        &metadata,
        enabled,
    );
    SkillStatusEntry {
        name: manifest.name.clone(),
        description: manifest.description.clone(),
        source_kind: source_kind.to_string(),
        source,
        trust: trust.to_string(),
        enabled,
        eligible: enabled && matches!(status, Status::Ready),
        status: status.as_str().to_string(),
        requirements,
        missing,
        install_options: manifest
            .openclaw_metadata()
            .and_then(|metadata| metadata.get("install"))
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default(),
        warnings,
        error,
        lifecycle,
        metadata,
        provenance: provenance(source_kind, trust),
        remediation_actions,
    }
}

fn error_entry(
    name: String,
    source_kind: &str,
    trust: &str,
    source: String,
    status: Status,
    error: String,
) -> SkillStatusEntry {
    SkillStatusEntry {
        name,
        description: String::new(),
        source_kind: source_kind.to_string(),
        source,
        trust: trust.to_string(),
        enabled: true,
        eligible: false,
        status: status.as_str().to_string(),
        requirements: RequirementSummary::default(),
        missing: napaxi_skills::MissingRequirements::default(),
        install_options: Vec::new(),
        warnings: Vec::new(),
        error: Some(error),
        lifecycle: lifecycle_json(None),
        metadata: OpenClawSkillMetadata::default(),
        provenance: provenance(source_kind, trust),
        remediation_actions: Vec::new(),
    }
}

fn requirement_summary(requirements: &napaxi_skills::GatingRequirements) -> RequirementSummary {
    RequirementSummary {
        bins: requirements.bins.clone(),
        any_bins: requirements.any_bins.clone(),
        env: requirements.env.clone(),
        config: requirements.config.clone(),
        os: requirements.os.clone(),
        capabilities: requirements.capabilities.clone(),
        skills: requirements.skills.clone(),
    }
}

fn openclaw_metadata(manifest: &napaxi_skills::SkillManifest) -> OpenClawSkillMetadata {
    OpenClawSkillMetadata {
        user_invocable: manifest.user_invocable(),
        disable_model_invocation: manifest.disable_model_invocation(),
        command_dispatch: manifest.metadata_string("command-dispatch"),
        command_tool: manifest.metadata_string("command-tool"),
        command_arg_mode: manifest.metadata_string("command-arg-mode"),
        primary_env: manifest.metadata_string("primaryEnv"),
        skill_key: manifest.metadata_string("skillKey"),
        homepage: manifest.metadata_string("homepage"),
        emoji: manifest.metadata_string("emoji"),
    }
}

fn provenance(source_kind: &str, trust: &str) -> SkillProvenance {
    let legacy = source_kind.starts_with("legacy");
    let source_kind_mapped = match source_kind {
        "user" => "agent_created",
        "installed" => "catalog_installed",
        "legacy_user" | "legacy_installed" => "legacy",
        other => other,
    };
    SkillProvenance {
        source_kind: source_kind_mapped.to_string(),
        trust: trust.to_string(),
        managed_by: if legacy { "legacy" } else { "core" }.to_string(),
        legacy,
    }
}

fn remediation_actions_for(
    skill_name: &str,
    skill_key: &str,
    status: Status,
    requirements: &RequirementSummary,
    missing: &napaxi_skills::MissingRequirements,
    metadata: &OpenClawSkillMetadata,
    enabled: bool,
) -> Vec<SkillRemediationAction> {
    let mut actions = Vec::new();
    if !enabled || matches!(status, Status::Disabled) {
        actions.push(SkillRemediationAction {
            id: format!("enable:{skill_key}"),
            kind: "enable".to_string(),
            label: format!("Enable {skill_name}"),
            requirement: skill_key.to_string(),
            host_handled: false,
            danger_level: "low".to_string(),
        });
    }
    for env in &missing.env {
        actions.push(SkillRemediationAction {
            id: format!("env:{skill_key}:{env}"),
            kind: "env".to_string(),
            label: format!("Configure environment key {env}"),
            requirement: env.clone(),
            host_handled: true,
            danger_level: "medium".to_string(),
        });
    }
    for config in &missing.config {
        actions.push(SkillRemediationAction {
            id: format!("config:{skill_key}:{config}"),
            kind: "config".to_string(),
            label: format!("Enable config {config}"),
            requirement: config.clone(),
            host_handled: true,
            danger_level: "low".to_string(),
        });
    }
    for capability in &missing.capabilities {
        actions.push(SkillRemediationAction {
            id: format!("capability:{skill_key}:{capability}"),
            kind: "capability".to_string(),
            label: format!("Request capability {capability}"),
            requirement: capability.clone(),
            host_handled: true,
            danger_level: "medium".to_string(),
        });
    }
    for bin in missing.bins.iter().chain(missing.any_bins.iter()) {
        actions.push(SkillRemediationAction {
            id: format!("install_hint:{skill_key}:{bin}"),
            kind: "install_hint".to_string(),
            label: format!("Install or provide {bin}"),
            requirement: bin.clone(),
            host_handled: true,
            danger_level: "medium".to_string(),
        });
    }
    if !requirements.skills.is_empty() {
        for skill in &requirements.skills {
            actions.push(SkillRemediationAction {
                id: format!("companion_skill:{skill_key}:{skill}"),
                kind: "companion_skill".to_string(),
                label: format!("Install companion skill {skill}"),
                requirement: skill.clone(),
                host_handled: true,
                danger_level: "low".to_string(),
            });
        }
    }
    if metadata.primary_env.is_some() && missing.env.is_empty() && actions.is_empty() {
        actions.push(SkillRemediationAction {
            id: format!("config_check:{skill_key}"),
            kind: "check".to_string(),
            label: "Check skill configuration".to_string(),
            requirement: skill_key.to_string(),
            host_handled: true,
            danger_level: "low".to_string(),
        });
    }
    actions
}

fn build_report(entries: Vec<SkillStatusEntry>) -> SkillStatusReport {
    let mut report = SkillStatusReport {
        entries,
        ready: 0,
        disabled: 0,
        blocked: 0,
        missing_requirements: 0,
        parse_error: 0,
        security_blocked: 0,
        too_large: 0,
    };
    for entry in &report.entries {
        match entry.status.as_str() {
            "ready" => report.ready += 1,
            "disabled" => report.disabled += 1,
            "missing_requirements" => report.missing_requirements += 1,
            "parse_error" => report.parse_error += 1,
            "security_blocked" => report.security_blocked += 1,
            "too_large" => report.too_large += 1,
            _ => report.blocked += 1,
        }
    }
    report.blocked += report.missing_requirements
        + report.parse_error
        + report.security_blocked
        + report.too_large;
    report
}
