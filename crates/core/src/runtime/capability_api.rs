//! Capability status query and config update over a runtime engine handle.

use super::handle::{handle_to_arc, invalid_handle_json, parse_config};
use crate::error::{CoreError, CoreResult};

pub fn capability_status_json_handle(
    handle: i64,
    profile_json: &str,
    selection_json: &str,
) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return crate::capabilities::status_json("unknown", profile_json, selection_json);
    };
    let profile = if is_blank_capability_json(profile_json) {
        engine.capability_profile()
    } else {
        crate::capabilities::profile_from_json(profile_json)
    };
    let selection = if is_blank_capability_json(selection_json) {
        engine.capability_selection()
    } else {
        crate::capabilities::selection_from_json(selection_json)
    };
    let platform = profile
        .platform
        .as_deref()
        .unwrap_or_else(|| engine.platform());
    serde_json::to_string(&crate::capabilities::status(
        platform,
        &serde_json::to_string(&profile).unwrap_or_else(|_| "{}".to_string()),
        &serde_json::to_string(&selection).unwrap_or_else(|_| "{}".to_string()),
    ))
    .unwrap_or_else(|_| "[]".to_string())
}

fn is_blank_capability_json(raw: &str) -> bool {
    let trimmed = raw.trim();
    trimmed.is_empty() || trimmed == "{}" || trimmed == "null"
}

pub fn update_config_handle(handle: i64, config_json: &str) -> bool {
    match update_config_handle_typed(handle, config_json) {
        Ok(()) => true,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                handle,
                "update_config_handle failed"
            );
            false
        }
    }
}

/// Result-returning variant. Surfaces `invalid_handle` vs `config` errors
/// instead of collapsing both into `false`.
pub fn update_config_handle_typed(handle: i64, config_json: &str) -> CoreResult<()> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    let config = parse_config(config_json)?;
    if engine.update_config(config) {
        Ok(())
    } else {
        Err(CoreError::LockPoisoned("engine.config"))
    }
}

pub fn get_config_handle(handle: i64) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return invalid_handle_json();
    };
    engine.config_json()
}

/// Result-returning variant. Returns the engine's config JSON or a structured
/// `InvalidHandle` error.
pub fn get_config_handle_typed(handle: i64) -> CoreResult<String> {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    Ok(engine.config_json())
}
