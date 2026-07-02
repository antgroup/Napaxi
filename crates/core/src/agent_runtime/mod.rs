//! Runtime-owned durable state shared by agent turns and background work.

use std::path::{Path, PathBuf};

pub(crate) mod runs;

pub(crate) const RUNTIME_ROOT_DIR: &str = "agent_runtime";

pub(crate) fn root_dir(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(RUNTIME_ROOT_DIR)
}

pub(crate) fn domain_dir(files_dir: &str, domain: &str) -> PathBuf {
    root_dir(files_dir).join(domain)
}

pub(crate) fn legacy_brand_domain_dir(files_dir: &str, domain: &str) -> PathBuf {
    Path::new(files_dir).join("napaxi").join(domain)
}
