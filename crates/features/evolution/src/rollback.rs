use crate::error::{EvolutionError, EvolutionResult};
use crate::io::copy_dir_all;
use crate::types::{BackupVersion, RollbackResult};
use chrono::Utc;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use tokio::sync::Mutex;
use uuid::Uuid;

/// Rollback manager
pub struct RollbackManager {
    /// Backup storage directory
    backup_dir: PathBuf,
    /// Maximum retained versions
    max_versions: usize,
    /// In-memory index
    index: Mutex<HashMap<String, Vec<BackupVersion>>>,
}

impl RollbackManager {
    pub fn new(backup_dir: PathBuf, max_versions: usize) -> Self {
        Self {
            backup_dir,
            max_versions,
            index: Mutex::new(HashMap::new()),
        }
    }

    /// Create backup for Skill
    pub async fn create_backup(
        &self,
        skill_name: &str,
        skill_dir: &Path,
    ) -> EvolutionResult<BackupVersion> {
        if !skill_dir.exists() {
            return Err(EvolutionError::SkillNotFound(skill_name.to_string()));
        }

        let backup_id = Uuid::new_v4();
        let backup_path = self
            .backup_dir
            .join(format!("{}_{}", skill_name, backup_id));

        // Compute content hash
        let content_hash = compute_dir_hash(skill_dir).await?;

        // Recursively copy entire directory
        copy_dir_all(skill_dir, &backup_path).await?;

        let backup = BackupVersion {
            id: backup_id,
            skill_name: skill_name.to_string(),
            created_at: Utc::now(),
            operation: "pre-edit".to_string(),
            backup_path,
            original_path: skill_dir.to_path_buf(),
            content_hash,
        };

        // Update index and clean up old versions
        {
            let mut index = self.index.lock().await;
            let versions = index.entry(skill_name.to_string()).or_default();
            versions.push(backup.clone());
            versions.sort_by(|a, b| b.created_at.cmp(&a.created_at));

            if versions.len() > self.max_versions {
                let to_remove: Vec<_> = versions.drain(self.max_versions..).collect();
                for old in to_remove {
                    let _ = tokio::fs::remove_dir_all(&old.backup_path).await;
                }
            }
        }

        Ok(backup)
    }

    /// Rollback to latest backup
    pub async fn rollback_latest(&self, skill_name: &str) -> EvolutionResult<RollbackResult> {
        let backup = self
            .find_latest_backup(skill_name)
            .await
            .ok_or(EvolutionError::BackupNotFound(skill_name.to_string()))?;

        self.perform_rollback(&backup).await
    }

    /// Rollback to specified backup
    pub async fn rollback_by_id(&self, backup_id: Uuid) -> EvolutionResult<RollbackResult> {
        let backup = self
            .find_backup_by_id(backup_id)
            .await
            .ok_or(EvolutionError::BackupNotFound(backup_id.to_string()))?;

        self.perform_rollback(&backup).await
    }

    /// List all backup versions
    pub async fn list_versions(&self, skill_name: &str) -> Vec<BackupVersion> {
        let index = self.index.lock().await;
        index.get(skill_name).cloned().unwrap_or_default()
    }

    /// Perform rollback operation
    async fn perform_rollback(&self, backup: &BackupVersion) -> EvolutionResult<RollbackResult> {
        // Verify backup integrity
        if !backup.backup_path.exists() {
            return Err(EvolutionError::BackupCorrupted(backup.id));
        }

        let backup_hash = compute_dir_hash(&backup.backup_path).await?;

        if backup.content_hash != backup_hash {
            return Err(EvolutionError::BackupCorrupted(backup.id));
        }

        // Atomic replacement
        let temp_path = backup.original_path.with_extension("tmp_rollback");

        // 1. Current version -> temporary location (if exists)
        if backup.original_path.exists() {
            tokio::fs::rename(&backup.original_path, &temp_path)
                .await
                .map_err(|e| EvolutionError::RollbackFailed(e.to_string()))?;
        }

        // 2. Backup -> original location
        if let Err(e) = tokio::fs::rename(&backup.backup_path, &backup.original_path).await {
            // Rollback failed, restore original state
            if temp_path.exists() {
                let _ = tokio::fs::rename(&temp_path, &backup.original_path).await;
            }
            return Err(EvolutionError::RollbackFailed(e.to_string()));
        }

        // 3. Clean up temporary files
        if temp_path.exists() {
            let _ = tokio::fs::remove_dir_all(&temp_path).await;
        }

        Ok(RollbackResult {
            success: true,
            rolled_back_to: backup.clone(),
            message: format!("Successfully rolled back {}", backup.skill_name),
        })
    }

    /// Find backup by specified ID
    async fn find_backup_by_id(&self, id: Uuid) -> Option<BackupVersion> {
        let index = self.index.lock().await;
        for versions in index.values() {
            if let Some(backup) = versions.iter().find(|v| v.id == id) {
                return Some(backup.clone());
            }
        }
        None
    }

    /// Find latest backup
    async fn find_latest_backup(&self, skill_name: &str) -> Option<BackupVersion> {
        let index = self.index.lock().await;
        index.get(skill_name)?.first().cloned()
    }
}

/// Compute directory hash
async fn compute_dir_hash(dir: &Path) -> EvolutionResult<String> {
    use sha2::{Digest, Sha256};

    let mut hasher = Sha256::new();

    let mut entries = tokio::fs::read_dir(dir).await.map_err(EvolutionError::Io)?;

    while let Some(entry) = entries.next_entry().await.map_err(EvolutionError::Io)? {
        let path = entry.path();
        let metadata = entry.metadata().await.map_err(EvolutionError::Io)?;

        if metadata.is_file() {
            let content = tokio::fs::read(&path).await.map_err(EvolutionError::Io)?;
            hasher.update(&content);
        }
    }

    Ok(format!("{:x}", hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn test_rollback_manager() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");
        let skill_dir = temp.path().join("skills").join("test-skill");

        // Create original skill
        tokio::fs::create_dir_all(&skill_dir).await.unwrap();
        tokio::fs::write(skill_dir.join("SKILL.md"), "original content")
            .await
            .unwrap();

        // Create manager
        let manager = RollbackManager::new(backup_dir.clone(), 5);

        // Create backup
        let _backup = manager
            .create_backup("test-skill", &skill_dir)
            .await
            .unwrap();
        assert!(backup_dir.exists());

        // Modify skill
        tokio::fs::write(skill_dir.join("SKILL.md"), "modified content")
            .await
            .unwrap();

        // Rollback
        let result = manager.rollback_latest("test-skill").await.unwrap();
        assert!(result.success);

        // Verify content was restored
        let content = tokio::fs::read_to_string(skill_dir.join("SKILL.md"))
            .await
            .unwrap();
        assert_eq!(content, "original content");
    }

    #[tokio::test]
    async fn test_rollback_nonexistent_skill() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");

        let manager = RollbackManager::new(backup_dir, 5);

        // Rolling back nonexistent skill should fail
        let result = manager.rollback_latest("nonexistent-skill").await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_backup_nonexistent_skill() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");

        let manager = RollbackManager::new(backup_dir, 5);

        // Backing up nonexistent skill should fail
        let result = manager
            .create_backup("nonexistent", Path::new("/nonexistent/path"))
            .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_rollback_by_id_not_found() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");

        let manager = RollbackManager::new(backup_dir, 5);

        // Rolling back nonexistent backup_id should fail
        let fake_id = Uuid::new_v4();
        let result = manager.rollback_by_id(fake_id).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_max_versions_cleanup() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");
        let skill_dir = temp.path().join("skills").join("test-skill");

        tokio::fs::create_dir_all(&skill_dir).await.unwrap();
        tokio::fs::write(skill_dir.join("SKILL.md"), "content")
            .await
            .unwrap();

        // Keep at most 2 versions
        let manager = RollbackManager::new(backup_dir.clone(), 2);

        // Create 4 backups
        for i in 0..4 {
            tokio::fs::write(skill_dir.join("SKILL.md"), format!("content {}", i))
                .await
                .unwrap();
            manager
                .create_backup("test-skill", &skill_dir)
                .await
                .unwrap();
        }

        // Should only have 2 versions left
        let versions = manager.list_versions("test-skill").await;
        assert_eq!(versions.len(), 2);
    }

    #[tokio::test]
    async fn test_list_versions_empty() {
        let temp = TempDir::new().unwrap();
        let backup_dir = temp.path().join("backups");

        let manager = RollbackManager::new(backup_dir, 5);

        // Query skill with no backups
        let versions = manager.list_versions("no-such-skill").await;
        assert!(versions.is_empty());
    }
}