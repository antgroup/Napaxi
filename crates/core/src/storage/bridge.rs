//! `FileBridge` sandbox <-> real path mapping.
//!
//! Public non-`_handle` helpers are reached by SDK adapters via
//! `storage::handles::*`; the in-crate lint cannot see those call sites.
#![allow(dead_code)]

use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::error::StorageError;

pub(super) const ROOTFS_PREFIXES: &[&str] = &[
    "/tmp", "/root", "/home", "/var", "/usr", "/opt", "/etc", "/srv", "/run",
];

pub struct FileBridge {
    workspace_dir: PathBuf,
    rootfs_dir: PathBuf,
    skills_dir: PathBuf,
}

impl FileBridge {
    pub fn new(files_dir: &str) -> Self {
        Self::new_with_workspace_files_dir(files_dir, files_dir)
    }

    pub fn new_with_workspace_files_dir(files_dir: &str, workspace_files_dir: &str) -> Self {
        let files = PathBuf::from(files_dir);
        let workspace_files = PathBuf::from(workspace_files_dir);
        let rootfs_dir = if cfg!(target_os = "ios") {
            files
                .parent()
                .map(|parent| parent.join("ish-rootfs"))
                .unwrap_or_else(|| files.join("ish-rootfs"))
        } else {
            files.join("linux-env").join("rootfs")
        };

        Self {
            workspace_dir: workspace_files.join("linux-env").join("workspace"),
            rootfs_dir,
            skills_dir: files.join("prompt_skills"),
        }
    }

    pub fn ensure_workspace(&self) -> bool {
        match self.ensure_workspace_inner() {
            Ok(()) => true,
            Err(error) => {
                tracing::warn!(
                    error = %error,
                    code = error.code(),
                    dir = %self.workspace_dir.display(),
                    "ensure_workspace failed"
                );
                false
            }
        }
    }

    pub(crate) fn ensure_workspace_inner(&self) -> Result<(), StorageError> {
        fs::create_dir_all(&self.workspace_dir)?;
        Ok(())
    }

    pub fn workspace_dir(&self) -> &Path {
        &self.workspace_dir
    }

    pub fn rootfs_dir(&self) -> &Path {
        &self.rootfs_dir
    }

    pub fn skills_dir(&self) -> &Path {
        &self.skills_dir
    }

    pub fn sandbox_to_real(&self, sandbox_path: &str) -> Option<String> {
        if is_sandbox_root_or_child(sandbox_path, "/workspace") {
            return join_mapped(&self.workspace_dir, sandbox_path, "/workspace")
                .ok()
                .map(|path| path.display().to_string());
        }
        if is_sandbox_root_or_child(sandbox_path, "/skills") {
            return join_mapped(&self.skills_dir, sandbox_path, "/skills")
                .ok()
                .map(|path| path.display().to_string());
        }
        if ROOTFS_PREFIXES
            .iter()
            .any(|prefix| is_sandbox_root_or_child(sandbox_path, prefix))
        {
            let rest = sandbox_path.strip_prefix('/').unwrap_or(sandbox_path);
            return join_validated(&self.rootfs_dir, rest, sandbox_path)
                .ok()
                .map(|path| path.display().to_string());
        }
        None
    }

    pub fn real_to_sandbox(&self, real_path: &str) -> Option<String> {
        let normalized = normalize_path(Path::new(real_path));
        if let Some(path) = strip_base(
            &normalized,
            &normalize_path(&self.workspace_dir),
            "/workspace",
        ) {
            return Some(path);
        }
        if let Some(path) = strip_base(&normalized, &normalize_path(&self.skills_dir), "/skills") {
            return Some(path);
        }
        if let Some(rest) = strip_path_prefix(&normalized, &normalize_path(&self.rootfs_dir)) {
            return Some(format!("/{}", rest.display()));
        }
        None
    }
}

fn is_sandbox_root_or_child(sandbox_path: &str, root: &str) -> bool {
    sandbox_path == root
        || sandbox_path
            .strip_prefix(root)
            .is_some_and(|rest| rest.starts_with('/'))
}

fn join_mapped(base: &Path, sandbox_path: &str, prefix: &str) -> Result<PathBuf, StorageError> {
    let rest = sandbox_path
        .strip_prefix(prefix)
        .unwrap_or("")
        .strip_prefix('/')
        .unwrap_or("");
    join_validated(base, rest, sandbox_path)
}

fn join_validated(
    base: &Path,
    relative_path: &str,
    sandbox_path: &str,
) -> Result<PathBuf, StorageError> {
    let relative_path = Path::new(relative_path);
    if relative_path.components().any(|component| {
        matches!(
            component,
            Component::ParentDir | Component::CurDir | Component::RootDir | Component::Prefix(_)
        )
    }) {
        return Err(StorageError::OutsideSandbox(sandbox_path.to_string()));
    }
    if relative_path.as_os_str().is_empty() {
        Ok(base.to_path_buf())
    } else {
        Ok(base.join(relative_path))
    }
}

fn normalize_path(path: &Path) -> PathBuf {
    path.components().collect()
}

fn strip_path_prefix(path: &Path, base: &Path) -> Option<PathBuf> {
    path.strip_prefix(base).ok().map(PathBuf::from)
}

fn strip_base(path: &Path, base: &Path, sandbox_root: &str) -> Option<String> {
    if path == base {
        return Some(sandbox_root.to_string());
    }
    let rest = strip_path_prefix(path, base)?;
    let rest_str = rest.display().to_string();
    if rest_str.is_empty() {
        Some(sandbox_root.to_string())
    } else {
        Some(format!("{sandbox_root}/{rest_str}"))
    }
}

pub fn sandbox_to_real(files_dir: &str, sandbox_path: &str) -> Option<String> {
    FileBridge::new(files_dir).sandbox_to_real(sandbox_path)
}

pub fn real_to_sandbox(files_dir: &str, real_path: &str) -> Option<String> {
    FileBridge::new(files_dir).real_to_sandbox(real_path)
}

pub fn delete_sandbox_file(files_dir: &str, sandbox_path: &str) -> bool {
    let bridge = FileBridge::new(files_dir);
    delete_sandbox_file_with_bridge(&bridge, sandbox_path)
}

pub(super) fn delete_sandbox_file_with_bridge(bridge: &FileBridge, sandbox_path: &str) -> bool {
    match delete_sandbox_file_with_bridge_inner(bridge, sandbox_path) {
        Ok(()) => true,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                sandbox_path,
                "delete_sandbox_file failed"
            );
            false
        }
    }
}

pub(crate) fn delete_sandbox_file_with_bridge_inner(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<(), StorageError> {
    let Some((path, base)) = delete_target(bridge, sandbox_path)? else {
        return Ok(());
    };
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    ensure_delete_target_inside_base(&path, &base, &metadata, sandbox_path)?;
    if metadata.file_type().is_symlink() {
        fs::remove_file(path)?;
    } else if metadata.is_dir() {
        fs::remove_dir_all(path)?;
    } else {
        fs::remove_file(path)?;
    }
    Ok(())
}

fn delete_target(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<Option<(PathBuf, PathBuf)>, StorageError> {
    if is_sandbox_root_or_child(sandbox_path, "/workspace") {
        return join_mapped(&bridge.workspace_dir, sandbox_path, "/workspace")
            .map(|path| Some((path, bridge.workspace_dir.clone())));
    }
    if is_sandbox_root_or_child(sandbox_path, "/skills") {
        return Err(StorageError::OutsideSandbox(sandbox_path.to_string()));
    }
    if ROOTFS_PREFIXES
        .iter()
        .any(|prefix| is_sandbox_root_or_child(sandbox_path, prefix))
    {
        let rest = sandbox_path.strip_prefix('/').unwrap_or(sandbox_path);
        return join_validated(&bridge.rootfs_dir, rest, sandbox_path)
            .map(|path| Some((path, bridge.rootfs_dir.clone())));
    }
    Ok(None)
}

fn ensure_delete_target_inside_base(
    path: &Path,
    base: &Path,
    metadata: &fs::Metadata,
    sandbox_path: &str,
) -> Result<(), StorageError> {
    let canonical_base = base.canonicalize()?;
    let canonical_guard = if metadata.file_type().is_symlink() {
        path.parent()
            .unwrap_or(base)
            .canonicalize()
            .map_err(StorageError::from)?
    } else {
        path.canonicalize()?
    };
    if canonical_guard == canonical_base || canonical_guard.starts_with(&canonical_base) {
        Ok(())
    } else {
        Err(StorageError::OutsideSandbox(sandbox_path.to_string()))
    }
}
