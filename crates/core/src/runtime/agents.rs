//! Agent registry handle wrappers (get-or-create / list / delete).

use super::engine::{DEFAULT_AGENT_ID, normalize_agent_id};
use super::handle::handle_to_arc;
use crate::error::{CoreError, CoreResult};

fn agent_error_json(message: impl Into<String>) -> String {
    serde_json::json!({
        "error": message.into(),
    })
    .to_string()
}

pub fn get_or_create_agent_handle(handle: i64, agent_id: &str) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return agent_error_json("engine handle is not available");
    };
    let agent_id = normalize_agent_id(agent_id);
    let created = engine.ensure_agent(&agent_id);
    serde_json::json!({
        "agent_id": agent_id,
        "created": created,
    })
    .to_string()
}

pub fn list_agents_handle(handle: i64) -> String {
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let Some(engine) = (unsafe { handle_to_arc(handle) }) else {
        return "[]".to_string();
    };
    engine.list_agents_json()
}

pub fn delete_agent_handle(handle: i64, agent_id: &str) -> bool {
    match delete_agent_handle_typed(handle, agent_id) {
        Ok(()) => true,
        Err(error) => {
            tracing::warn!(
                error = %error,
                code = error.code(),
                handle,
                agent_id,
                "delete_agent_handle failed"
            );
            false
        }
    }
}

/// Result-returning variant. Adapters that want structured error codes
/// (`invalid_handle`, `invalid_input`) should call this instead.
pub fn delete_agent_handle_typed(handle: i64, agent_id: &str) -> CoreResult<()> {
    let agent_id = normalize_agent_id(agent_id);
    if agent_id == DEFAULT_AGENT_ID {
        return Err(CoreError::InvalidInput(format!(
            "cannot delete default agent {DEFAULT_AGENT_ID}"
        )));
    }
    // SAFETY: `handle` is a live engine handle produced by `create_engine_handle`; `handle_to_arc` returns `None` for a `0`/invalid handle rather than dereferencing it.
    let engine = unsafe { handle_to_arc(handle) }.ok_or(CoreError::InvalidHandle(handle))?;
    if engine.delete_agent(&agent_id) {
        Ok(())
    } else {
        Err(CoreError::InvalidInput(format!(
            "agent {agent_id} not found"
        )))
    }
}
