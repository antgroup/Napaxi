//! Numeric limits, directory names, and well-known string constants.

pub(super) const DEFAULT_AGENT_ID: &str = crate::runtime::DEFAULT_AGENT_ID;
pub(super) const CLAWHUB_BASE_URL: &str = "https://wry-manatee-359.convex.site";
pub(super) const MAX_ZIP_FILES: usize = 50;
pub(super) const MAX_ZIP_TOTAL_SIZE: usize = 5 * 1024 * 1024;
pub(super) const MAX_EXTRA_FILE_SIZE: u64 = 1024 * 1024;
pub(super) const STALE_AFTER_DAYS: i64 = 30;
pub(super) const ARCHIVE_STALE_AFTER_DAYS: i64 = 90;
pub(super) const MAX_ACTIVE_SKILLS_PER_TURN: usize = 8;
pub(super) const MAX_SKILL_CATALOG_ENTRIES: usize = 24;
pub(crate) const SKILL_LOAD_TOOL_NAME: &str = "skill_load";
pub(super) const MAX_PRIVATE_SKILL_COMMAND_SIGNATURES: usize = 32;
pub(super) const SKILL_SESSION_ACTIVE_TURNS: u8 = 6;
pub(super) const SKILL_SESSION_ACTIVE_MAX_AGE_MINUTES: i64 = 30;

pub(super) fn invalid_handle_json() -> String {
    r#"{"error":"invalid engine handle"}"#.to_string()
}

pub(super) fn error_response(message: impl std::fmt::Display) -> String {
    serde_json::json!({ "error": message.to_string() }).to_string()
}
