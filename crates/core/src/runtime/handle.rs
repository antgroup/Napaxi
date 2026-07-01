//! Engine handle creation, lifetime, and FFI-friendly handle <-> Arc conversion.

use std::sync::Arc;

use crate::error::{CoreError, CoreResult};
use crate::types::PlatformLlmConfig;

use super::engine::{Engine, PlatformContext};

pub fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

pub(super) fn parse_config(config_json: &str) -> CoreResult<PlatformLlmConfig> {
    serde_json::from_str(config_json)
        .map_err(|e| CoreError::Config(format!("Invalid config JSON: {e}")))
}

fn parse_platform_context(platform_context_json: &str) -> CoreResult<PlatformContext> {
    serde_json::from_str(platform_context_json)
        .map_err(|e| CoreError::Config(format!("Invalid platform context JSON: {e}")))
}

#[cfg(target_os = "android")]
fn setup_android_sandbox(context: &PlatformContext) -> CoreResult<()> {
    let native_library_dir = context
        .native_library_dir
        .as_deref()
        .ok_or_else(|| CoreError::Config("missing native_library_dir".into()))?;
    if crate::android_linux_env::is_ready(&context.files_dir, native_library_dir) {
        return Ok(());
    }
    let lib_talloc =
        crate::android_assets::read_asset("libtalloc.so.2").map_err(|e| CoreError::Other(e))?;
    let rootfs =
        crate::android_assets::read_asset("alpine-rootfs.bin").map_err(|e| CoreError::Other(e))?;
    crate::android_linux_env::setup(&context.files_dir, native_library_dir, &lib_talloc, &rootfs)
        .map_err(|e| CoreError::Other(e))?;
    Ok(())
}

pub fn create_engine_handle(config_json: &str, platform_context_json: &str) -> CoreResult<i64> {
    let config = parse_config(config_json)?;
    let context = parse_platform_context(platform_context_json)?;

    #[cfg(target_os = "android")]
    setup_android_sandbox(&context)?;

    let bridge = crate::storage::FileBridge::new(&context.files_dir);
    bridge
        .ensure_workspace_inner()
        .map_err(CoreError::Storage)?;
    let _ = crate::workspace::reseed_workspace(&context.files_dir);
    crate::skills::bundled::ensure_bundled_skills(&context.files_dir);
    crate::agent_runtime::runs::mark_stale_running_runs_lost(&context.files_dir);

    let engine = Arc::new(Engine::new(
        context.files_dir,
        context.platform,
        context.native_library_dir,
        config,
        context.capability_profile,
        context.capability_selection,
        context.skill_readiness,
    ));
    Ok(Arc::into_raw(engine) as i64)
}

/// # Safety
///
/// `handle` must have been produced by `create_engine_handle` and not already
/// consumed by `handle_consume`.
pub unsafe fn handle_to_arc(handle: i64) -> Option<Arc<Engine>> {
    if handle == 0 {
        return None;
    }
    let ptr = handle as *const Engine;
    // SAFETY: by the documented precondition `handle` came from
    // `create_engine_handle` (an `Arc::into_raw`) and has not been consumed, so
    // `ptr` is a live `Arc<Engine>` allocation. Bumping the strong count before
    // `from_raw` reconstructs a borrow without taking ownership of the caller's
    // reference, keeping the original handle valid.
    unsafe {
        Arc::increment_strong_count(ptr);
        Some(Arc::from_raw(ptr))
    }
}

/// # Safety
///
/// `handle` must have been produced by `create_engine_handle`, and this must be
/// called at most once for a live handle.
pub unsafe fn handle_consume(handle: i64) -> Option<Arc<Engine>> {
    if handle == 0 {
        return None;
    }
    let ptr = handle as *const Engine;
    // SAFETY: by the documented precondition `handle` came from
    // `create_engine_handle` and `handle_consume` is called at most once for it,
    // so `ptr` is a live `Arc<Engine>` allocation whose ownership we now take
    // back exactly once via `from_raw`.
    Some(unsafe { Arc::from_raw(ptr) })
}

pub fn dispose_engine_handle(handle: i64) {
    // SAFETY: `handle` is an opaque engine handle owned by the caller; disposal
    // happens once per handle, satisfying `handle_consume`'s contract.
    let _ = unsafe { handle_consume(handle) };
}

pub fn files_dir_from_handle(handle: i64) -> Option<String> {
    // SAFETY: `handle` is a live engine handle from `create_engine_handle`; an
    // invalid `0` handle yields `None` inside `handle_to_arc`.
    let engine = unsafe { handle_to_arc(handle) }?;
    Some(engine.files_dir().to_string())
}

#[allow(dead_code)] // Public handle inspector; reserved for adapter diagnostics.
pub fn platform_from_handle(handle: i64) -> Option<String> {
    // SAFETY: `handle` is a live engine handle from `create_engine_handle`; an
    // invalid `0` handle yields `None` inside `handle_to_arc`.
    let engine = unsafe { handle_to_arc(handle) }?;
    Some(engine.platform().to_string())
}
