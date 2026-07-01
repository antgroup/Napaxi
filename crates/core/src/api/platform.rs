//! Platform integration API for SDK adapters.

#[cfg(target_os = "android")]
pub use crate::android_assets::register_asset_manager;

#[cfg(target_os = "ios")]
pub use crate::ios_ish_env::{
    is_ready as ios_ish_is_ready,
    register_rootfs_archive_path as register_ios_ish_rootfs_archive_path,
};
