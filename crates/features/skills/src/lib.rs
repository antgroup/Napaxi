//! Skill types, parsing, selection, and management for Napaxi.
//!
//! Skills are SKILL.md files (YAML frontmatter + markdown prompt) that extend the
//! agent's behavior through prompt-level instructions. This crate provides the core
//! types, SKILL.md parser, and filesystem management.
//!
//! # V2 Engine
//!
//! In the v2 engine, skill **selection and scoring** happen in the Python orchestrator
//! (`orchestrator/default.py`), not in Rust. The engine uses this crate only for:
//! - **`types`** + **`v2`** — Data structures (`SkillManifest`, `V2SkillMetadata`, etc.)
//! - **`parser`** — Parsing SKILL.md files during v1→v2 migration
//! - **`validation`** — Name/content escaping, credential spec validation
//!
//! # V1 Agent (remove after migration)
//!
//! The following modules are used **only by the v1 agent** (`src/agent/`). Once
//! the v1 agent is removed, they can be deleted or feature-gated:
//!
//! - **`selector`** — Rust-side deterministic scoring (`prefilter_skills`). In v2,
//!   the equivalent logic lives in `orchestrator/default.py:score_skill()`.
//! - **`gating`** — Binary/env/config requirement checks at load time. In v2,
//!   skills are stored as MemoryDocs and gating is not applicable.
//! - **`registry`** (feature-gated) — Filesystem discovery and install/remove.
//!   In v2, skills are managed as MemoryDocs via the Store.
//! - **`catalog`** (feature-gated) — ClawHub HTTP catalog. In v2, skill
//!   installation happens through the skill-extraction mission or direct API.
//!
//! # Trust Model
//!
//! Skills have two trust states that determine their authority:
//! - **Trusted**: User-placed skills (local/workspace) with full tool access
//! - **Installed**: Registry/external skills, restricted to read-only tools
//!
//! In v1, trust-based tool filtering happens via `src/skills/attenuation.rs`.
//! In v2, the Python orchestrator handles trust labels and the policy engine
//! controls tool access via capability leases.

// Non-test paths in this crate are `.unwrap()`-free. Lock that in at the crate
// level so a future regression surfaces as a clippy warning instead of a panic
// in a host app (mobile builds use `panic = "abort"`). Mirrors `napaxi-core`.
// Test code is exempt — fixtures and assertions read fine with `.unwrap()`.
#![cfg_attr(not(test), warn(clippy::unwrap_used))]

pub mod afs_traits;
pub mod gating;
pub mod parser;
pub mod security;
pub mod selector;
pub mod types;
pub mod v2;
pub mod validation;

#[cfg(feature = "catalog")]
pub mod catalog;
#[cfg(feature = "registry")]
pub mod registry;

// Re-export core types at crate root for convenience.
pub use types::{
    ActivationCriteria, GatingRequirements, LoadedSkill, MAX_PROMPT_FILE_SIZE, MissingRequirements,
    ProviderRefreshStrategy, SkillCredentialLocation, SkillCredentialSpec, SkillManifest,
    SkillOAuthConfig, SkillReadinessContext, SkillSource, SkillTrust,
};

pub use gating::{
    GatingResult, check_requirements, check_requirements_sync,
    check_requirements_sync_with_context, check_requirements_with_context,
};
pub use parser::{ParsedSkill, SkillParseError, parse_skill_md};
pub use security::{
    SkillSecurityFile, SkillSecurityFinding, SkillSecurityScanResult, SkillSecuritySeverity,
    scan_skill_package,
};
pub use selector::{MAX_SKILL_CONTEXT_TOKENS, extract_skill_mentions, prefilter_skills};
pub use validation::{
    escape_skill_content, escape_xml_attr, normalize_line_endings, validate_credential_name,
    validate_credential_spec, validate_skill_name,
};

// afs_traits re-exports（始终可用，与 registry feature 无关）
pub use afs_traits::{
    AfsAccessor, AfsError, AfsFileMeta, AfsFileType, AfsUserProvider, init_afs_provider,
};

#[cfg(feature = "catalog")]
pub use catalog::{
    CatalogEntry, CatalogResolveError, CatalogSearchOutcome, SkillCatalog,
    catalog_entry_is_installed, resolve_catalog_slug_for_name, shared_catalog,
};
#[cfg(feature = "registry")]
pub use registry::{SkillRegistry, SkillRegistryError, compute_hash};
