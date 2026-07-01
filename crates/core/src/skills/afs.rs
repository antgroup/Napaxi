//! Local filesystem implementation of the `napaxi_skills` AFS provider trait.

use std::path::Path;
use std::sync::{Arc, Once};

use napaxi_skills::{
    AfsAccessor, AfsError, AfsFileMeta, AfsFileType, AfsUserProvider, SkillRegistry, SkillSource,
    SkillTrust, init_afs_provider,
};

use super::paths::{agent_skills_dir, installed_skills_dir, normalize_agent_id};
use super::source_registry::source_roots;

struct LocalAfsProvider;

impl AfsUserProvider for LocalAfsProvider {
    fn get_user(&self, _user_id: &str) -> Result<Arc<dyn AfsAccessor>, AfsError> {
        Ok(Arc::new(LocalAfsAccessor))
    }
}

struct LocalAfsAccessor;

#[async_trait::async_trait]
impl AfsAccessor for LocalAfsAccessor {
    async fn read_dir(&self, path: &Path) -> Result<Vec<AfsFileMeta>, AfsError> {
        let mut entries = tokio::fs::read_dir(path)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))?;
        let mut out = Vec::new();
        while let Some(entry) = entries
            .next_entry()
            .await
            .map_err(|e| AfsError::Other(e.to_string()))?
        {
            let metadata = entry
                .metadata()
                .await
                .map_err(|e| AfsError::Other(e.to_string()))?;
            out.push(AfsFileMeta::new(
                entry.path(),
                file_type_from_metadata(&metadata),
            ));
        }
        Ok(out)
    }

    async fn symlink_metadata(&self, path: &Path) -> Result<AfsFileMeta, AfsError> {
        let metadata = tokio::fs::symlink_metadata(path).await.map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                AfsError::NotFound(path.to_path_buf())
            } else {
                AfsError::Other(e.to_string())
            }
        })?;
        Ok(AfsFileMeta::new(
            path.to_path_buf(),
            file_type_from_metadata(&metadata),
        ))
    }

    async fn create_dir_all(&self, path: &Path) -> Result<(), AfsError> {
        tokio::fs::create_dir_all(path)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))
    }

    async fn write(&self, path: &Path, content: &[u8]) -> Result<(), AfsError> {
        tokio::fs::write(path, content)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))
    }

    async fn remove_file(&self, path: &Path) -> Result<(), AfsError> {
        tokio::fs::remove_file(path)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))
    }

    async fn remove_dir(&self, path: &Path) -> Result<(), AfsError> {
        tokio::fs::remove_dir(path)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))
    }

    async fn read(&self, path: &Path) -> Result<Vec<u8>, AfsError> {
        tokio::fs::read(path)
            .await
            .map_err(|e| AfsError::Other(e.to_string()))
    }

    fn physical_exists(&self, path: &Path) -> bool {
        path.exists()
    }
}

fn file_type_from_metadata(metadata: &std::fs::Metadata) -> AfsFileType {
    let file_type = metadata.file_type();
    if file_type.is_symlink() {
        AfsFileType::Symlink
    } else if file_type.is_dir() {
        AfsFileType::Directory
    } else if file_type.is_file() {
        AfsFileType::File
    } else {
        AfsFileType::Other
    }
}

fn ensure_afs_provider() {
    static INIT: Once = Once::new();
    INIT.call_once(|| {
        init_afs_provider(Box::new(LocalAfsProvider));
    });
}

pub(super) async fn registry(files_dir: &str, agent_id: &str) -> SkillRegistry {
    ensure_afs_provider();
    let agent_id = normalize_agent_id(agent_id);
    let registry = SkillRegistry::new(agent_skills_dir(files_dir, &agent_id))
        .with_installed_dir(installed_skills_dir(files_dir, &agent_id));
    let _ = registry.discover_all(&agent_id).await;
    merge_additional_sources(files_dir, &agent_id, &registry).await;
    registry
}

async fn merge_additional_sources(files_dir: &str, agent_id: &str, registry: &SkillRegistry) {
    for source in source_roots(files_dir, agent_id)
        .into_iter()
        .filter(|source| !matches!(source.id.as_str(), "agent_created" | "catalog_installed"))
    {
        if !source.root.exists() {
            continue;
        }
        let source_registry = SkillRegistry::new(source.root.clone());
        let _ = source_registry.discover_all(agent_id).await;
        for skill in source_registry.skills_for_user(agent_id) {
            if registry.has_for_user(skill.name(), agent_id) {
                continue;
            }
            let mut cloned = (*skill).clone();
            cloned.trust = if source.trust == "trusted" {
                SkillTrust::Trusted
            } else {
                SkillTrust::Installed
            };
            cloned.source = match source.kind.as_str() {
                "app_bundled" => SkillSource::Bundled(skill_source_path(&cloned)),
                "host_installed" | "catalog_installed" => {
                    SkillSource::Installed(skill_source_path(&cloned))
                }
                _ => SkillSource::User(skill_source_path(&cloned)),
            };
            let name = cloned.name().to_string();
            let _ = registry.commit_install_or_replace(&name, cloned);
        }
    }
}

fn skill_source_path(skill: &napaxi_skills::LoadedSkill) -> std::path::PathBuf {
    match &skill.source {
        SkillSource::Workspace(path)
        | SkillSource::User(path)
        | SkillSource::Installed(path)
        | SkillSource::Bundled(path) => path.clone(),
    }
}
