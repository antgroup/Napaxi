//! Napaxi Core — standalone mobile-native AI agent SDK runtime.
//!
//! This crate is the runtime kernel behind the Napaxi SDK: it owns the chat-turn
//! lifecycle, LLM dispatch, tool execution, session/history persistence, the
//! capability admission model, and the skill/evolution subsystems. It is
//! consumed by thin platform adapters (Flutter via `flutter_rust_bridge`,
//! Android via JNI, iOS via the C ABI) rather than by application code directly.
//!
//! # Where to start
//!
//! - [`api`] is the adapter-facing boundary. Every SDK binding enters core
//!   through this namespace; its public surface is held to `#![deny(missing_docs)]`.
//!   The legacy JSON/handle functions and the newer typed (`CoreResult`-returning)
//!   methods both live here.
//! - [`error`] defines the two-layer error model: domain enums plus the umbrella
//!   [`error::CoreError`], which serializes to a stable wire shape via
//!   [`error::CoreError::to_wire_json`].
//!
//! # Engine handles
//!
//! Adapters hold an opaque `i64` engine handle (see [`api::engine::EngineHandle`])
//! rather than a Rust reference. The handle is reconstructed into an `Arc<Engine>`
//! across the FFI boundary; the `unsafe` conversions that do so are the bulk of
//! this crate's `unsafe` and are documented on their `unsafe fn`s.
//!
//! # Invariants enforced at the crate level
//!
//! - Non-test code is `.unwrap()`-free (`clippy::unwrap_used` is warned): mobile
//!   builds use `panic = "abort"`, so an unwrap on bad input would abort the host
//!   app rather than surface a recoverable error.
//! - Every `unsafe` block carries a `// SAFETY:` comment
//!   (`clippy::undocumented_unsafe_blocks` is denied).
//! - The [`api`] boundary requires doc comments on every public item.

// Production code in `napaxi-core` is `.unwrap()`-free in the non-test paths.
// Enforce this at the crate level so a future regression causes a compile
// error instead of a runtime panic on a user's device (mobile builds use
// `panic = "abort"`, so unwrap on bad input would abort the host app).
// Test code is exempt — fixtures and assertions read fine with `.unwrap()`.
#![cfg_attr(not(test), deny(clippy::unwrap_used))]
// Every `unsafe` block in this crate must carry a `// SAFETY:` comment
// justifying its soundness. Most are FFI engine-handle conversions
// (`handle_to_arc`/`handle_consume`) whose contract is documented on those
// `unsafe fn`s in `runtime/handle.rs`; the rest are platform FFI calls and raw
// pointer reconstruction. Enforced crate-wide so new unsafe cannot land
// undocumented.
#![deny(clippy::undocumented_unsafe_blocks)]

/// Adapter-facing API shared by all SDK integration layers.
pub mod api;

/// Two-layer core error model (umbrella `CoreError` + domain enums).
/// Adapter-visible re-exports live under [`api::error`].
pub mod error;

// ============================================================================
// Platform-Agnostic Types & Integration Layer
// ============================================================================

/// Per-turn scene prompt detection and runtime guidance injection.
mod scene_prompt;

/// Mobile-facing message and attachment types.
#[path = "types/mobile.rs"]
mod types;

mod channels {
    pub(crate) use crate::types::IncomingAttachment;
}

/// Agent definitions — user-defined agent persistence and AGENT.md parsing
mod agent_definitions;

/// Mobile SDK storage and sandbox file bridge helpers
mod storage;

/// File-backed mobile workspace seed and prompt helpers.
#[path = "workspace/mod.rs"]
mod workspace;

/// File-backed mobile session metadata and history helpers.
#[path = "session/mod.rs"]
mod session;

/// Minimal HTTP LLM adapter for the standalone mobile SDK runtime.
#[path = "llm/mod.rs"]
mod llm;

/// Mobile runtime orchestration helpers.
#[path = "runtime/mod.rs"]
mod runtime;

/// Durable agent runtime state with neutral internal storage paths.
#[path = "agent_runtime/mod.rs"]
mod agent_runtime;

/// Pluggable agent engine host protocol and tool broker.
#[path = "agent_engine/mod.rs"]
mod agent_engine;

/// Core-owned agent turn lifecycle orchestration.
mod turn;

/// Core-owned context engine and session compaction helpers.
#[path = "context/mod.rs"]
mod context;

/// Mobile memory evolution review and auto-apply glue.
#[path = "evolution/mod.rs"]
mod evolution;

/// Mobile SDK host/custom tool boundary.
#[path = "tools/registry/mod.rs"]
mod tool_registry;

/// Mobile platform capability contract shared by SDK adapters.
#[path = "platform_capabilities.rs"]
mod platform_capabilities;

/// Core-owned capability registry and admission hooks.
#[path = "capabilities/mod.rs"]
mod capabilities;

/// Napaxi-owned mobile LLM tool loop orchestration.
#[path = "tools/loop.rs"]
mod tool_loop;

/// Human-in-the-loop broker and ask_human tool contract.
#[path = "human_loop.rs"]
mod human_loop;

/// Napaxi-owned mobile builtin tool composition.
#[path = "tools/builtin/mod.rs"]
mod builtin_tools;

/// Napaxi-owned mobile memory tools backed by the mobile workspace.
#[path = "tools/memory.rs"]
mod memory_tools;

/// Napaxi-owned mobile sandbox file tools.
#[path = "tools/file/mod.rs"]
mod file_tools;

/// Napaxi-owned mobile web search tool.
#[path = "tools/web_search.rs"]
mod web_search_tool;

/// Napaxi-owned mobile HTTP request tool.
#[path = "tools/http.rs"]
mod http_tool;

/// Napaxi-owned persistent browser control tool contract.
#[path = "tools/browser.rs"]
mod browser_tools;

/// Napaxi-owned mobile media capability tools.
#[path = "tools/media.rs"]
mod media_tools;

/// Napaxi-owned mobile webpage fetch tool.
#[path = "tools/web_fetch.rs"]
mod web_fetch_tool;

/// Napaxi-owned mobile skill management tools.
#[path = "tools/skill.rs"]
mod skill_tools;

/// File-backed mobile agent definition store.
#[path = "agents/mod.rs"]
mod agents;

/// File-backed mobile skill management.
#[path = "skills/mod.rs"]
mod skills;

/// File-backed mobile group collaboration state.
#[path = "group/mod.rs"]
mod group;

/// File-backed mobile MCP server state.
#[path = "mcp/mod.rs"]
mod mcp;

/// File-backed mobile channel registration state.
#[path = "channel/mod.rs"]
mod channel;

/// Core-owned channel-to-agent route, session, and HITL runtime.
#[path = "channel_agent/mod.rs"]
mod channel_agent;

/// File-backed mobile automation jobs and run audit log.
#[path = "automation/mod.rs"]
mod automation;

/// Shared HMAC-SHA256 signing primitives (canonical JSON, HMAC, constant-time
/// compare) used by A2A peer envelopes and agent-app trigger bindings.
#[path = "crypto/mod.rs"]
mod crypto;

/// Mobile A2A deep-link task handoff and peer trust state.
#[path = "a2a/mod.rs"]
mod a2a;

/// Android proot Linux environment setup and package installation.
#[path = "platform/android_linux_env.rs"]
mod android_linux_env;

/// Android APK asset access shared by Flutter and native Android bindings.
#[cfg(target_os = "android")]
#[path = "platform/android_assets.rs"]
mod android_assets;

/// iOS iSH Linux environment setup and command execution.
#[cfg(target_os = "ios")]
#[path = "platform/ios_ish_env.rs"]
mod ios_ish_env;

/// Shared SSRF guards for LLM-reachable outbound HTTP.
mod net;

// ============================================================================
// Re-exports for easier access
// ============================================================================

// Adapter-facing types are exported through `api`.

// ============================================================================
// FFI / C API for Android JNI
// ============================================================================

use std::ffi::CString;
use std::os::raw::c_char;

/// Get the library version
#[unsafe(no_mangle)]
pub extern "C" fn napaxi_version() -> *mut c_char {
    let version = env!("CARGO_PKG_VERSION");
    CString::new(version)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Free a string allocated by the library.
///
/// # Safety
///
/// `s` must be either null or a pointer previously returned by a `napaxi_*`
/// function that allocates a string (e.g. via `CString::into_raw`). It must
/// not have been freed already, and must not be used after this call. Passing
/// any other pointer is undefined behavior.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn napaxi_string_free(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: the fn-level contract guarantees a non-null `s` is a pointer
        // previously handed out by a `napaxi_*` allocator (via `CString::into_raw`)
        // and not yet freed, so reclaiming it with `from_raw` to drop it is sound.
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}
