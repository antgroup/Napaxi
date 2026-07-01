//! Adapter-visible error model.
//!
//! Re-exported from [`crate::error`] so adapter bindings (FRB, FFI) can match
//! against stable error codes and surface `CoreError::to_wire_json()` results.

pub use crate::error::{
    CapabilityError, CoreError, CoreResult, LlmError, McpError, StorageError, ToolError,
};
