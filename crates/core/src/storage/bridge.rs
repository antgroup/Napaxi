//! `FileBridge` sandbox <-> real path mapping.
//!
//! Public non-`_handle` helpers are reached by SDK adapters via
//! `storage::handles::*`; the in-crate lint cannot see those call sites.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};

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
        if sandbox_path == "/workspace" || sandbox_path.starts_with("/workspace/") {
            return Some(join_mapped(&self.workspace_dir, sandbox_path, "/workspace"));
        }
        if sandbox_path == "/skills" || sandbox_path.starts_with("/skills/") {
            return Some(join_mapped(&self.skills_dir, sandbox_path, "/skills"));
        }
        if ROOTFS_PREFIXES
            .iter()
            .any(|prefix| sandbox_path.starts_with(prefix))
        {
            let rest = sandbox_path.strip_prefix('/').unwrap_or(sandbox_path);
            return Some(self.rootfs_dir.join(rest).display().to_string());
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

fn join_mapped(base: &Path, sandbox_path: &str, prefix: &str) -> String {
    let rest = sandbox_path
        .strip_prefix(prefix)
        .unwrap_or("")
        .strip_prefix('/')
        .unwrap_or("");
    if rest.is_empty() {
        base.display().to_string()
    } else {
        base.join(rest).display().to_string()
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
    let Some(real) = bridge.sandbox_to_real(sandbox_path) else {
        return Ok(());
    };
    let path = Path::new(&real);
    if !path.exists() {
        return Ok(());
    }
    if path.is_dir() {
        fs::remove_dir_all(path)?;
    } else {
        fs::remove_file(path)?;
    }
    Ok(())
}
