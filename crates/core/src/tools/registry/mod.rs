//! Mobile tool boundary for host-provided custom tools.
//!
//! Public surface preserved through pub use below. Split into:
//!
//! - [`types`]: descriptor, execution context, dispatcher type, bridge
//! - [`rate_limit`]: per-tool sliding-window rate limiter + per-tool policy
//! - [`pending`]: pending request tables and global request-id routing
//! - [`bridge`]: host tool dispatch over a request bridge
//! - [`prepare`]: schema-driven argument preparation and validation
//! - [`redact`]: secret redaction for arguments and output, plus truncation
//! - [`registry`]: `ToolRegistry` itself

#![allow(unused_imports)] // re-export aggregator: lint cannot see external bridge consumers.

mod bridge;
mod pending;
mod prepare;
mod rate_limit;
mod redact;
mod registry;
mod types;

#[cfg(test)]
mod tests;

pub use bridge::request_host_tool_execution;
pub(crate) use bridge::request_host_tool_execution_with_context;
pub use pending::resolve_tool_execution;
pub use prepare::{normalize_parameters_schema, prepare_tool_arguments};
pub use rate_limit::check_tool_rate_limit;
pub use redact::{redact_sensitive_json, redact_tool_arguments_json, sanitize_tool_output};
pub use registry::ToolRegistry;
pub use types::{ToolDescriptor, ToolEffect, ToolExecutionContext, ToolRequestDispatcher};

pub(crate) use types::ToolRequestBridge;
