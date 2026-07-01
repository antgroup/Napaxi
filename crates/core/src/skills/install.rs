//! Skill install paths: raw markdown, JSON bundle, ZIP, URL, and ClawHub.

use std::collections::HashSet;
use std::io::{Cursor, Read};
use std::path::{Path, PathBuf};

use base64::Engine as _;

use super::afs::registry;
use super::catalog::validate_skill_fetch_url;
use super::limits::{
    CLAWHUB_BASE_URL, MAX_EXTRA_FILE_SIZE, MAX_ZIP_FILES, MAX_ZIP_TOTAL_SIZE, error_response,
    invalid_handle_json,
};
use super::paths::{agent_skills_dir, normalize_agent_id, safe_skill_relative_path, safe_zip_path};
use super::types::{
    SkillInstallBundlePayload, SkillInstallExtraFilePayload, SkillInstallPayload, SkillPackage,
};

pub async fn install_skill(files_dir: &str, agent_id: &str, skill_content: &str) -> String {
    let agent_id = normalize_agent_id(agent_id);
    match parse_install_payload(skill_content) {
        Ok(package) => install_skill_package(files_dir, &agent_id, package).await,
        Err(error) => error_response(error),
    }
}

pub async fn install_skill_handle(handle: i64, agent_id: &str, skill_content: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    install_skill(&files_dir, agent_id, skill_content).await
}

pub(super) async fn install_skill_package(
    files_dir: &str,
    agent_id: &str,
    package: SkillPackage,
) -> String {
    let extra_files = match normalize_extra_files(package.extra_files) {
        Ok(files) => files,
        Err(e) => return error_response(e),
    };
    if let Err(error) = scan_skill_package_for_install(&package.skill_md, &extra_files) {
        return error_response(error);
    }
    let registry = registry(files_dir, agent_id).await;
    match registry.install_skill(&package.skill_md, agent_id).await {
        Ok(name) => {
            if let Err(e) = write_skill_extra_files(files_dir, agent_id, &name, &extra_files).await
            {
                return error_response(format!("install extras failed: {e}"));
            }
            serde_json::json!({
                "name": name,
                "success": true,
            })
            .to_string()
        }
        Err(e) => error_response(e),
    }
}

fn scan_skill_package_for_install(
    skill_md: &str,
    extra_files: &[(String, Vec<u8>)],
) -> Result<(), String> {
    let mut decoded_support = Vec::<(String, String)>::new();
    for (path, bytes) in extra_files {
        if let Ok(content) = String::from_utf8(bytes.clone()) {
            decoded_support.push((path.clone(), content));
        }
    }
    let mut scan_files = vec![napaxi_skills::SkillSecurityFile {
        path: "SKILL.md",
        content: skill_md,
    }];
    for (path, content) in &decoded_support {
        scan_files.push(napaxi_skills::SkillSecurityFile { path, content });
    }
    let result = napaxi_skills::scan_skill_package(&scan_files);
    if result.has_critical_findings() {
        Err(format!(
            "security scan blocked skill install: {}",
            result.critical_summary()
        ))
    } else {
        Ok(())
    }
}

fn normalize_extra_files(
    extra_files: Vec<(String, Vec<u8>)>,
) -> Result<Vec<(String, Vec<u8>)>, String> {
    let mut normalized = Vec::with_capacity(extra_files.len());
    let mut seen = HashSet::new();
    let mut total_size = 0usize;
    for (relative_path, bytes) in extra_files {
        match safe_extra_file_path(&relative_path)? {
            Some(path) => {
                if bytes.len() as u64 > MAX_EXTRA_FILE_SIZE {
                    return Err(format!(
                        "skill extra file '{}' too large ({} bytes, max {})",
                        path.display(),
                        bytes.len(),
                        MAX_EXTRA_FILE_SIZE
                    ));
                }
                total_size = total_size.saturating_add(bytes.len());
                if total_size > MAX_ZIP_TOTAL_SIZE {
                    return Err(format!(
                        "skill extra files exceed total limit ({MAX_ZIP_TOTAL_SIZE} bytes)"
                    ));
                }
                let normalized_path = path.display().to_string();
                if !seen.insert(normalized_path.clone()) {
                    return Err(format!(
                        "duplicate skill extra file path: {normalized_path}"
                    ));
                }
                normalized.push((normalized_path, bytes));
            }
            None => {
                tracing::warn!(
                    path = %relative_path,
                    "Skipping skill package metadata file"
                );
            }
        }
    }
    Ok(normalized)
}

fn safe_extra_file_path(relative_path: &str) -> Result<Option<PathBuf>, String> {
    let safe_path = safe_zip_path(relative_path)
        .ok_or_else(|| format!("unsafe skill extra file path: {relative_path}"))?;
    if is_ignored_skill_package_file(&safe_path) {
        Ok(None)
    } else {
        Ok(Some(safe_path))
    }
}

fn parse_install_payload(input: &str) -> Result<SkillPackage, String> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err("skill install payload is empty".to_string());
    }

    if trimmed.starts_with('{')
        && let Ok(payload) = serde_json::from_str::<SkillInstallPayload>(trimmed)
    {
        return match payload {
            SkillInstallPayload::Raw(skill_md) => Ok(SkillPackage {
                skill_md,
                extra_files: Vec::new(),
            }),
            SkillInstallPayload::Bundle(bundle) => decode_install_bundle(bundle),
        };
    }

    Ok(SkillPackage {
        skill_md: input.to_string(),
        extra_files: Vec::new(),
    })
}

fn decode_install_bundle(bundle: SkillInstallBundlePayload) -> Result<SkillPackage, String> {
    let mut extra_files = Vec::with_capacity(bundle.extra_files.len());
    for file in bundle.extra_files {
        let Some(path) = safe_extra_file_path(&file.path)? else {
            tracing::warn!(
                path = %file.path,
                "Skipping skill bundle extra file outside known support directories"
            );
            continue;
        };
        let bytes = decode_extra_file(&file)?;
        extra_files.push((path.display().to_string(), bytes));
    }

    Ok(SkillPackage {
        skill_md: bundle.skill_md,
        extra_files,
    })
}

fn decode_extra_file(file: &SkillInstallExtraFilePayload) -> Result<Vec<u8>, String> {
    base64::engine::general_purpose::STANDARD
        .decode(file.content_base64.as_bytes())
        .map_err(|e| format!("invalid base64 for '{}': {e}", file.path))
}

async fn write_skill_extra_files(
    files_dir: &str,
    agent_id: &str,
    skill_name: &str,
    extra_files: &[(String, Vec<u8>)],
) -> Result<(), String> {
    let skill_dir = agent_skills_dir(files_dir, agent_id).join(skill_name);
    for (relative_path, bytes) in extra_files {
        let path = safe_skill_relative_path(Some(relative_path))?;
        let target = skill_dir.join(path);
        atomic_write_bytes(&target, bytes).await?;
    }
    Ok(())
}

pub(super) async fn atomic_write_bytes(path: &Path, bytes: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| format!("create {}: {e}", parent.display()))?;
    }
    let temp = path.with_file_name(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("file"),
        uuid::Uuid::new_v4()
    ));
    if let Err(error) = tokio::fs::write(&temp, bytes).await {
        let _ = tokio::fs::remove_file(&temp).await;
        return Err(format!("write {}: {error}", temp.display()));
    }
    tokio::fs::rename(&temp, path)
        .await
        .map_err(|e| format!("rename {} -> {}: {e}", temp.display(), path.display()))
}

pub async fn install_from_catalog(files_dir: &str, agent_id: &str, slug: &str) -> String {
    let url = format!("{CLAWHUB_BASE_URL}/api/v1/download");
    let client = reqwest::Client::new();
    let bytes = match client.get(&url).query(&[("slug", slug)]).send().await {
        Ok(resp) => match resp.bytes().await {
            Ok(bytes) => bytes,
            Err(e) => return error_response(format!("read body: {e}")),
        },
        Err(e) => return error_response(format!("download failed: {e}")),
    };
    install_downloaded_skill_bytes(files_dir, agent_id, &bytes).await
}

pub async fn install_from_catalog_handle(handle: i64, agent_id: &str, slug: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return invalid_handle_json();
    };
    install_from_catalog(&files_dir, agent_id, slug).await
}

pub async fn install_from_url(files_dir: &str, agent_id: &str, url: &str) -> String {
    let url = match validate_skill_fetch_url(url) {
        Ok(url) => url,
        Err(e) => return error_response(e),
    };
    let client = reqwest::Client::new();
    let bytes = match client.get(url).send().await {
        Ok(resp) => match resp.bytes().await {
            Ok(bytes) => bytes,
            Err(e) => return error_response(format!("read body: {e}")),
        },
        Err(e) => return error_response(format!("download failed: {e}")),
    };
    install_downloaded_skill_bytes(files_dir, agent_id, &bytes).await
}

pub async fn install_from_zip_bytes(files_dir: &str, agent_id: &str, bytes: &[u8]) -> String {
    match extract_skill_from_zip_bytes(bytes) {
        Ok(package) => {
            install_skill_package(files_dir, &normalize_agent_id(agent_id), package).await
        }
        Err(e) => error_response(format!("zip extract failed: {e}")),
    }
}

async fn install_downloaded_skill_bytes(files_dir: &str, agent_id: &str, bytes: &[u8]) -> String {
    let agent_id = normalize_agent_id(agent_id);
    if bytes.starts_with(b"PK\x03\x04") {
        return match extract_skill_from_zip_bytes(bytes) {
            Ok(package) => install_skill_package(files_dir, &agent_id, package).await,
            Err(e) => error_response(format!("zip extract failed: {e}")),
        };
    }
    match String::from_utf8(bytes.to_vec()) {
        Ok(content) => install_skill(files_dir, &agent_id, &content).await,
        Err(e) => error_response(format!("invalid UTF-8: {e}")),
    }
}

pub(super) fn extract_skill_from_zip_bytes(data: &[u8]) -> Result<SkillPackage, String> {
    let reader = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(reader).map_err(|e| e.to_string())?;
    let mut skill_md = None;
    let mut extra_files = Vec::new();
    let mut total_size = 0usize;
    let mut file_count = 0usize;

    for index in 0..archive.len() {
        let mut file = archive.by_index(index).map_err(|e| e.to_string())?;
        let name = file.name().to_string();
        if file.is_dir() || name.trim().is_empty() {
            continue;
        }
        let safe_path =
            safe_zip_path(&name).ok_or_else(|| format!("unsafe ZIP entry path: {name}"))?;
        if file
            .unix_mode()
            .map(|mode| mode & 0o170000 == 0o120000)
            .unwrap_or(false)
        {
            return Err(format!("ZIP entry '{}' is a symlink", name));
        }

        file_count += 1;
        if file_count > MAX_ZIP_FILES {
            return Err(format!(
                "ZIP archive contains too many files (max {MAX_ZIP_FILES})"
            ));
        }

        let is_skill_md = safe_path == Path::new("SKILL.md");
        if !is_skill_md && is_ignored_skill_package_file(&safe_path) {
            // ClawHub injects auxiliary files such as `_meta.json` next to
            // SKILL.md. Drop package metadata instead of failing the install.
            tracing::warn!(
                entry = %name,
                "Skipping ZIP package metadata entry"
            );
            continue;
        }
        let max_size = if is_skill_md {
            napaxi_skills::MAX_PROMPT_FILE_SIZE
        } else {
            MAX_EXTRA_FILE_SIZE
        };
        if file.size() > max_size {
            return Err(format!(
                "ZIP entry '{}' too large to decompress safely ({} bytes, max {})",
                name,
                file.size(),
                max_size
            ));
        }

        let mut bytes = Vec::with_capacity(file.size().min(max_size) as usize);
        file.read_to_end(&mut bytes)
            .map_err(|e| format!("read ZIP entry '{name}': {e}"))?;
        total_size = total_size.saturating_add(bytes.len());
        if total_size > MAX_ZIP_TOTAL_SIZE {
            return Err(format!(
                "ZIP archive total decompressed size exceeds limit ({MAX_ZIP_TOTAL_SIZE} bytes)"
            ));
        }

        let normalized_path = safe_path.display().to_string();
        if !seen_zip_entry(
            &extra_files,
            &normalized_path,
            is_skill_md,
            skill_md.is_some(),
        )? {
            continue;
        }

        if is_skill_md {
            let content = String::from_utf8(bytes)
                .map_err(|e| format!("SKILL.md in archive is not valid UTF-8: {e}"))?;
            skill_md = Some(content);
        } else {
            extra_files.push((safe_path.display().to_string(), bytes));
        }
    }

    Ok(SkillPackage {
        skill_md: skill_md
            .ok_or_else(|| "ZIP archive does not contain top-level SKILL.md".to_string())?,
        extra_files,
    })
}

fn seen_zip_entry(
    extra_files: &[(String, Vec<u8>)],
    normalized_path: &str,
    is_skill_md: bool,
    skill_md_seen: bool,
) -> Result<bool, String> {
    if is_skill_md {
        if skill_md_seen {
            return Err("ZIP archive contains duplicate SKILL.md".to_string());
        }
        return Ok(true);
    }
    if extra_files
        .iter()
        .any(|(existing, _)| existing == normalized_path)
    {
        return Err(format!(
            "ZIP archive contains duplicate entry: {normalized_path}"
        ));
    }
    Ok(true)
}

fn is_ignored_skill_package_file(path: &Path) -> bool {
    if path == Path::new("SKILL.md") || path == Path::new("_meta.json") {
        return true;
    }
    path.components()
        .next()
        .and_then(|component| match component {
            std::path::Component::Normal(part) => part.to_str(),
            _ => None,
        })
        .map(|part| part.starts_with('.'))
        .unwrap_or(false)
}

// Re-export PathBuf so mod-level callers don't need to import it; not exposed
// publicly outside the skills crate.
#[allow(dead_code)]
type _PathBuf = PathBuf;
