//! 轻量级 AFS trait 层 — 替代直接依赖 napaxi_sandbox。
//!
//! `AfsAccessor` trait 抽象了 `SkillRegistry` 所需的 8 个文件系统操作。
//! 全局 `AfsUserProvider` 在 server 启动时注册（见 `skills_afs_bridge.rs`）,
//! 通过 user_id 查询。

use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::sync::Arc;

// ── AfsFileType ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AfsFileType {
    File,
    Directory,
    Symlink,
    Other,
}

// ── AfsFileMeta ──────────────────────────────────────────────────────────

/// 轻量级文件元数据，替代 `napaxi_sandbox::afs::user::FileMetadata`。
#[derive(Debug, Clone)]
pub struct AfsFileMeta {
    path: PathBuf,
    file_type: AfsFileType,
}

impl AfsFileMeta {
    pub fn new(path: PathBuf, file_type: AfsFileType) -> Self {
        Self { path, file_type }
    }

    pub fn path(&self) -> PathBuf {
        self.path.clone()
    }

    pub fn file_name(&self) -> Option<&OsStr> {
        self.path.file_name()
    }

    pub fn is_dir(&self) -> bool {
        self.file_type == AfsFileType::Directory
    }

    pub fn is_file(&self) -> bool {
        self.file_type == AfsFileType::File
    }

    pub fn is_symlink(&self) -> bool {
        self.file_type == AfsFileType::Symlink
    }
}

// ── AfsError ─────────────────────────────────────────────────────────────

/// AFS 操作错误类型，替代 `napaxi_sandbox::FileSystemError`。
#[derive(Debug, thiserror::Error)]
pub enum AfsError {
    #[error("Path not found: {0}")]
    NotFound(PathBuf),

    #[error("AFS error: {0}")]
    Other(String),
}

// ── AfsAccessor trait (object-safe, 8 methods) ───────────────────────────

/// AFS 文件访问器 — 抽象了 `SkillRegistry` 需要的所有文件操作。
#[async_trait::async_trait]
pub trait AfsAccessor: Send + Sync {
    /// 列出目录条目。
    async fn read_dir(&self, path: &Path) -> Result<Vec<AfsFileMeta>, AfsError>;

    /// 读取元数据（不跟随符号链接）。
    async fn symlink_metadata(&self, path: &Path) -> Result<AfsFileMeta, AfsError>;

    /// 递归创建目录。
    async fn create_dir_all(&self, path: &Path) -> Result<(), AfsError>;

    /// 写入文件内容（创建或覆盖）。
    async fn write(&self, path: &Path, content: &[u8]) -> Result<(), AfsError>;

    /// 删除文件。
    async fn remove_file(&self, path: &Path) -> Result<(), AfsError>;

    /// 删除空目录。
    async fn remove_dir(&self, path: &Path) -> Result<(), AfsError>;

    /// 读取文件内容。
    async fn read(&self, path: &Path) -> Result<Vec<u8>, AfsError>;

    /// 同步检查路径是否存在（不产生 IO 错误）。
    fn physical_exists(&self, path: &Path) -> bool;
}

// ── AfsUserProvider trait ────────────────────────────────────────────────

/// 用户级 AFS provider — 全局注入点。
pub trait AfsUserProvider: Send + Sync {
    fn get_user(&self, user_id: &str) -> Result<Arc<dyn AfsAccessor>, AfsError>;
}

// ── Global provider ──────────────────────────────────────────────────────

use parking_lot::RwLock as PLRwLock;

static GLOBAL_AFS_PROVIDER: PLRwLock<Option<Box<dyn AfsUserProvider + Send + Sync>>> =
    PLRwLock::new(None);

/// 安装全局 AFS provider。server 启动时调用一次。
/// 测试中可多次调用以重置状态。
pub fn init_afs_provider(provider: Box<dyn AfsUserProvider + Send + Sync>) {
    *GLOBAL_AFS_PROVIDER.write() = Some(provider);
}

/// 内部辅助：获取指定用户的 AFS 访问器。
#[cfg(feature = "registry")]
pub(crate) fn get_afs(user_id: &str) -> Result<Arc<dyn AfsAccessor>, AfsError> {
    if let Some(ref provider) = *GLOBAL_AFS_PROVIDER.read() {
        return provider.get_user(user_id);
    }
    #[cfg(test)]
    {
        // 测试未显式注册 provider 时，使用 passthrough（虚拟路径=物理路径）
        let _ = user_id;
        Ok(Arc::new(test_afs::PassthroughAfsAccessor))
    }
    #[cfg(not(test))]
    {
        Err(AfsError::Other("AFS provider not initialized".to_string()))
    }
}

// ── Test utilities (仅在测试时编译) ─────────────────────────────────────

#[cfg(test)]
pub(crate) mod test_afs {
    use super::*;
    use parking_lot::RwLock;
    use std::collections::HashMap;

    /// Provider-internal state: initialized once per process.
    static TEST_STATE: std::sync::LazyLock<Arc<RwLock<HashMap<String, Vec<(PathBuf, PathBuf)>>>>> =
        std::sync::LazyLock::new(|| Arc::new(RwLock::new(HashMap::new())));

    /// Register per-user path maps for tests.
    pub(crate) fn register_test_user(user_id: &str, maps: Vec<(PathBuf, PathBuf)>) {
        TEST_STATE
            .write()
            .entry(user_id.to_string())
            .or_default()
            .extend(maps);
    }

    /// 测试用 AFS 访问器，委托给 tokio::fs / std::fs。
    /// 维护 (virtual_prefix → physical_prefix) 映射以实现 per-user 隔离。
    struct PrefixedAfsAccessor {
        maps: Vec<(PathBuf, PathBuf)>,
    }

    impl PrefixedAfsAccessor {
        /// 虚拟路径 → 物理路径前缀替换。
        fn map_path(&self, path: &Path) -> PathBuf {
            if path.is_relative() {
                return self
                    .maps
                    .first()
                    .map(|(_, p)| p.join(path))
                    .unwrap_or_else(|| path.to_path_buf());
            }
            for (v_prefix, p_prefix) in &self.maps {
                if let Ok(rel) = path.strip_prefix(v_prefix) {
                    return p_prefix.join(rel);
                }
            }
            path.to_path_buf()
        }

        /// 物理路径 → 虚拟路径反向映射（用于 read_dir 返回值的路径翻译）。
        fn reverse_map_path(&self, physical: &Path) -> PathBuf {
            for (v_prefix, p_prefix) in &self.maps {
                if let Ok(rel) = physical.strip_prefix(p_prefix) {
                    return v_prefix.join(rel);
                }
            }
            physical.to_path_buf()
        }
    }

    #[async_trait::async_trait]
    impl AfsAccessor for PrefixedAfsAccessor {
        async fn read_dir(&self, path: &Path) -> Result<Vec<AfsFileMeta>, AfsError> {
            let physical = self.map_path(path);
            let mut entries = Vec::new();
            let mut dir = tokio::fs::read_dir(&physical).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })?;
            while let Some(entry) = dir
                .next_entry()
                .await
                .map_err(|e| AfsError::Other(e.to_string()))?
            {
                let ft = entry
                    .file_type()
                    .await
                    .map_err(|e| AfsError::Other(e.to_string()))?;
                let file_type = if ft.is_symlink() {
                    AfsFileType::Symlink
                } else if ft.is_dir() {
                    AfsFileType::Directory
                } else if ft.is_file() {
                    AfsFileType::File
                } else {
                    AfsFileType::Other
                };
                // 反向映射：物理路径 → 虚拟路径，后续操作才能正确映射
                let virtual_path = self.reverse_map_path(&entry.path());
                entries.push(AfsFileMeta::new(virtual_path, file_type));
            }
            Ok(entries)
        }

        async fn symlink_metadata(&self, path: &Path) -> Result<AfsFileMeta, AfsError> {
            let physical = self.map_path(path);
            let m = tokio::fs::symlink_metadata(&physical).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })?;
            let file_type = if m.file_type().is_symlink() {
                AfsFileType::Symlink
            } else if m.is_dir() {
                AfsFileType::Directory
            } else if m.is_file() {
                AfsFileType::File
            } else {
                AfsFileType::Other
            };
            Ok(AfsFileMeta::new(path.to_path_buf(), file_type))
        }

        async fn create_dir_all(&self, path: &Path) -> Result<(), AfsError> {
            let physical = self.map_path(path);
            tokio::fs::create_dir_all(&physical)
                .await
                .map_err(|e| AfsError::Other(e.to_string()))
        }

        async fn write(&self, path: &Path, content: &[u8]) -> Result<(), AfsError> {
            let physical = self.map_path(path);
            if let Some(parent) = physical.parent() {
                let _ = tokio::fs::create_dir_all(parent).await;
            }
            tokio::fs::write(&physical, content)
                .await
                .map_err(|e| AfsError::Other(e.to_string()))
        }

        async fn remove_file(&self, path: &Path) -> Result<(), AfsError> {
            let physical = self.map_path(path);
            tokio::fs::remove_file(&physical)
                .await
                .map_err(|e| AfsError::Other(e.to_string()))
        }

        async fn remove_dir(&self, path: &Path) -> Result<(), AfsError> {
            let physical = self.map_path(path);
            tokio::fs::remove_dir(&physical)
                .await
                .map_err(|e| AfsError::Other(e.to_string()))
        }

        async fn read(&self, path: &Path) -> Result<Vec<u8>, AfsError> {
            let physical = self.map_path(path);
            tokio::fs::read(&physical).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })
        }

        fn physical_exists(&self, path: &Path) -> bool {
            self.map_path(path).exists()
        }
    }

    /// 测试用 AFS provider：从全局 TEST_STATE 读取。
    pub(crate) struct TestAfsProvider;

    impl AfsUserProvider for TestAfsProvider {
        fn get_user(&self, user_id: &str) -> Result<Arc<dyn AfsAccessor>, AfsError> {
            let maps = TEST_STATE.read().get(user_id).cloned().unwrap_or_default();
            if maps.is_empty() {
                return Ok(Arc::new(PassthroughAfsAccessor));
            }
            Ok(Arc::new(PrefixedAfsAccessor { maps }))
        }
    }

    /// Passthrough accessor — 虚拟路径即物理路径，无前缀替换。
    pub(crate) struct PassthroughAfsAccessor;

    #[async_trait::async_trait]
    impl AfsAccessor for PassthroughAfsAccessor {
        async fn read_dir(&self, path: &Path) -> Result<Vec<AfsFileMeta>, AfsError> {
            let mut entries = Vec::new();
            let mut dir = tokio::fs::read_dir(path).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })?;
            while let Some(entry) = dir
                .next_entry()
                .await
                .map_err(|e| AfsError::Other(e.to_string()))?
            {
                let ft = entry
                    .file_type()
                    .await
                    .map_err(|e| AfsError::Other(e.to_string()))?;
                let file_type = if ft.is_symlink() {
                    AfsFileType::Symlink
                } else if ft.is_dir() {
                    AfsFileType::Directory
                } else if ft.is_file() {
                    AfsFileType::File
                } else {
                    AfsFileType::Other
                };
                entries.push(AfsFileMeta::new(entry.path(), file_type));
            }
            Ok(entries)
        }

        async fn symlink_metadata(&self, path: &Path) -> Result<AfsFileMeta, AfsError> {
            let m = tokio::fs::symlink_metadata(path).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })?;
            let file_type = if m.file_type().is_symlink() {
                AfsFileType::Symlink
            } else if m.is_dir() {
                AfsFileType::Directory
            } else if m.is_file() {
                AfsFileType::File
            } else {
                AfsFileType::Other
            };
            Ok(AfsFileMeta::new(path.to_path_buf(), file_type))
        }

        async fn create_dir_all(&self, path: &Path) -> Result<(), AfsError> {
            tokio::fs::create_dir_all(path)
                .await
                .map_err(|e| AfsError::Other(e.to_string()))
        }

        async fn write(&self, path: &Path, content: &[u8]) -> Result<(), AfsError> {
            if let Some(parent) = path.parent() {
                let _ = tokio::fs::create_dir_all(parent).await;
            }
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
            tokio::fs::read(path).await.map_err(|e| {
                if e.kind() == std::io::ErrorKind::NotFound {
                    AfsError::NotFound(path.to_path_buf())
                } else {
                    AfsError::Other(e.to_string())
                }
            })
        }

        fn physical_exists(&self, path: &Path) -> bool {
            path.exists()
        }
    }

    /// 安装测试 AFS provider（idempotent：首次设置后后续调用为 no-op）。
    pub(crate) fn init_test_afs_provider() {
        // 确保 provider 已安装（GLOBAL_AFS_PROVIDER 的 RwLock 支持重写）
        init_afs_provider(Box::new(TestAfsProvider));
    }

    /// 清空所有用户映射。每个测试开头调用一次。
    #[allow(dead_code)]
    pub(crate) fn reset_test_users() {
        // Tests in this crate run in parallel. Clearing the process-global
        // test map from one test can invalidate another test's active AFS
        // accessor, so reset is intentionally a no-op. Test mappings use
        // unique temp-directory prefixes and are harmless to retain.
    }

    /// 每个测试首次调用时清空旧映射。
    #[allow(dead_code)]
    pub(crate) fn maybe_reset_test_users() {
        reset_test_users();
    }
}
