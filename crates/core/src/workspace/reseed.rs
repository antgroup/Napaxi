//! Workspace seeding and migration from legacy memory layouts.

use std::fs;
use std::path::Path;

use super::files::write_workspace_file;
use super::meta::invalid_handle_json;
use super::paths::{
    AGENTS, BOOTSTRAP, HEARTBEAT, IDENTITY, LEGACY_MEMORY_PATHS, MEMORY, PROJECT, README, SOUL,
    TOOLS, USER, memory_dir, workspace_path,
};
use crate::storage::FileBridge;

const SEED_FILES: &[(&str, &str)] = &[
    (README, include_str!("seeds/README.md")),
    (MEMORY, include_str!("seeds/MEMORY.md")),
    (PROJECT, include_str!("seeds/PROJECT.md")),
    (IDENTITY, include_str!("seeds/IDENTITY.md")),
    (SOUL, include_str!("seeds/SOUL.md")),
    (AGENTS, include_str!("seeds/AGENTS.md")),
    (USER, include_str!("seeds/USER.md")),
    (HEARTBEAT, include_str!("seeds/HEARTBEAT.md")),
    (TOOLS, include_str!("seeds/TOOLS.md")),
];

pub fn reseed_workspace(files_dir: &str) -> String {
    let bridge = FileBridge::new(files_dir);
    if !bridge.ensure_workspace() || fs::create_dir_all(memory_dir(files_dir)).is_err() {
        return super::meta::error_json("Failed to create mobile workspace");
    }
    migrate_legacy_workspace_memory(files_dir, bridge.workspace_dir());

    let is_fresh = [BOOTSTRAP, AGENTS, SOUL, USER].iter().all(|path| {
        workspace_path(files_dir, path)
            .map(|p| !p.exists())
            .unwrap_or(false)
    });

    let mut count = 0;
    for (path, content) in SEED_FILES {
        let Ok(real_path) = workspace_path(files_dir, path) else {
            continue;
        };
        if real_path.exists() {
            continue;
        }
        if write_workspace_file(files_dir, path, content) {
            count += 1;
        }
    }

    // Seed BOOTSTRAP.md on fresh install so memory_write(target: "bootstrap")
    // has a file to clear. The prompt injection no longer depends on this file.
    if is_fresh {
        let Ok(bootstrap_path) = workspace_path(files_dir, BOOTSTRAP) else {
            return format!(r#"{{"seeded":{count}}}"#);
        };
        if !bootstrap_path.exists()
            && write_workspace_file(files_dir, BOOTSTRAP, include_str!("seeds/BOOTSTRAP.md"))
        {
            count += 1;
        }
    }

    format!(r#"{{"seeded":{count}}}"#)
}

pub fn reseed_workspace_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    reseed_workspace(&files_dir)
}

fn migrate_legacy_workspace_memory(files_dir: &str, legacy_workspace_dir: &Path) {
    let memory_dir = memory_dir(files_dir);
    for path in LEGACY_MEMORY_PATHS {
        let legacy_path = legacy_workspace_dir.join(path);
        if !legacy_path.exists() {
            continue;
        }
        let target_path = memory_dir.join(path);
        if target_path.exists() {
            continue;
        }
        if let Some(parent) = target_path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let _ = fs::rename(&legacy_path, &target_path).or_else(|_| {
            if legacy_path.is_dir() {
                copy_dir_all(&legacy_path, &target_path)?;
                fs::remove_dir_all(&legacy_path)
            } else {
                fs::copy(&legacy_path, &target_path)?;
                fs::remove_file(&legacy_path)
            }
        });
    }
}

fn copy_dir_all(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir_all(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}
