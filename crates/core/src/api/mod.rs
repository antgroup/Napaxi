//! Napaxi Core API.
//!
//! This module is the adapter-facing boundary for mobile SDK integrations.
//! Flutter, Android, iOS, and future bindings should enter core through this
//! namespace instead of calling `mobile_*` implementation modules directly.
//!
//! Every public item in this boundary must carry a doc comment — `missing_docs`
//! is denied module-wide below, symmetric with the crate-wide
//! `undocumented_unsafe_blocks` gate. This keeps the surface adapter authors
//! actually bind against fully documented; internal modules outside `api` are
//! not held to this bar.
#![deny(missing_docs)]

pub mod a2a;
pub mod agent;
pub mod agent_app;
pub mod agent_engine;
pub mod automation;
pub mod capability;
pub mod channel;
pub mod channel_agent;
pub mod channel_qqbot;
pub mod chat;
pub mod engine;
pub mod error;
pub mod events;
pub mod evolution;
pub mod file_bridge;
pub mod git;
pub mod group;
pub mod mcp;
pub mod platform;
pub mod session;
pub mod session_runs;
pub mod skill;
pub mod skill_catalog;
pub mod tools;
pub mod wire;
pub mod workspace;
