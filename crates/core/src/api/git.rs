//! Git identity configuration for the sandbox rootfs.
//!
//! Writes the commit identity (`user.name` / `user.email`) into the rootfs
//! `~/.gitconfig` (`/root/.gitconfig`, since the sandbox shell runs with
//! `HOME=/root`). Adapters call [`EngineHandle::configure_git_identity`] from a
//! settings page; the agent's `git commit` then authors commits with this
//! identity, exactly as it would with a hand-edited gitconfig.

use std::fs;
use std::path::Path;

use crate::api::engine::EngineHandle;
use crate::error::{CoreError, CoreResult};
use crate::runtime::handle_to_arc;
use crate::storage::FileBridge;

/// Sandbox path of the rootfs git config the shell `git` reads at commit time.
const GIT_CONFIG_SANDBOX_PATH: &str = "/root/.gitconfig";

impl EngineHandle {
    /// Write the commit identity (`user.name` / `user.email`) into the sandbox
    /// rootfs `~/.gitconfig`.
    ///
    /// Existing `[user]` settings are replaced in place; all other sections are
    /// preserved verbatim. Both `name` and `email` are required.
    pub fn configure_git_identity(self, name: &str, email: &str) -> CoreResult<()> {
        let engine = unsafe { handle_to_arc(self.raw()) }
            .ok_or(CoreError::InvalidHandle(self.raw()))?;
        let bridge = FileBridge::new(engine.files_dir());
        let real = bridge
            .sandbox_to_real(GIT_CONFIG_SANDBOX_PATH)
            .ok_or_else(|| {
                CoreError::InvalidInput(format!(
                    "unable to resolve sandbox git config path: {GIT_CONFIG_SANDBOX_PATH}"
                ))
            })?;
        let existing = read_existing(&real)?;
        let merged = merge_user_identity(&existing, name, email);
        write_gitconfig(&real, merged.as_bytes())
    }

    /// Read the commit identity from the sandbox rootfs `~/.gitconfig`.
    ///
    /// Returns `Ok(None)` when the file or its `[user]` section is absent.
    pub fn read_git_identity(self) -> CoreResult<Option<(String, String)>> {
        let engine = unsafe { handle_to_arc(self.raw()) }
            .ok_or(CoreError::InvalidHandle(self.raw()))?;
        let bridge = FileBridge::new(engine.files_dir());
        let real = bridge
            .sandbox_to_real(GIT_CONFIG_SANDBOX_PATH)
            .ok_or_else(|| {
                CoreError::InvalidInput(format!(
                    "unable to resolve sandbox git config path: {GIT_CONFIG_SANDBOX_PATH}"
                ))
            })?;
        let existing = read_existing(&real)?;
        Ok(parse_user_identity(&existing))
    }
}

fn read_existing(real: &str) -> CoreResult<String> {
    match fs::read_to_string(real) {
        Ok(content) => Ok(content),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(String::new()),
        Err(error) => Err(CoreError::Storage(error.into())),
    }
}

fn write_gitconfig(real: &str, bytes: &[u8]) -> CoreResult<()> {
    let path = Path::new(real);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| CoreError::Storage(error.into()))?;
    }
    fs::write(path, bytes).map_err(|error| CoreError::Storage(error.into()))
}

/// Rebuild a gitconfig body whose `[user]` section carries `name`/`email`,
/// preserving every other section byte-for-byte. A pre-existing `[user]`
/// section (including duplicates) is replaced; if none exists the new section is
/// appended.
fn merge_user_identity(existing: &str, name: &str, email: &str) -> String {
    let user_block = format!(
        "[user]\n\tname = {}\n\temail = {}\n",
        escape_gitconfig_value(name),
        escape_gitconfig_value(email),
    );

    let mut out = String::new();
    let mut in_user = false;
    let mut wrote_user = false;

    for line in existing.split_inclusive('\n') {
        let header = line.trim_end_matches(['\n', '\r']).trim();
        let is_header = header.starts_with('[') && header.ends_with(']');
        if is_header {
            in_user = header == "[user]";
            if in_user {
                if !wrote_user {
                    out.push_str(&user_block);
                    wrote_user = true;
                }
                // Drop the original (possibly duplicate) [user] header.
                continue;
            }
            out.push_str(line);
            continue;
        }
        if in_user {
            // Drop original [user] key/value lines; the block was rewritten.
            continue;
        }
        out.push_str(line);
    }

    if !wrote_user {
        if !out.is_empty() && !out.ends_with('\n') {
            out.push('\n');
        }
        out.push_str(&user_block);
    }
    out
}

/// Parse the `[user]` section of a gitconfig body into `(name, email)` when both
/// keys are present.
fn parse_user_identity(existing: &str) -> Option<(String, String)> {
    let mut in_user = false;
    let mut name = None::<String>;
    let mut email = None::<String>;
    for line in existing.lines() {
        let header = line.trim();
        if header.starts_with('[') && header.ends_with(']') {
            in_user = header == "[user]";
            continue;
        }
        if !in_user {
            continue;
        }
        if let Some((key, value)) = split_key_value(line) {
            match key.trim() {
                "name" => name = Some(unquote_gitconfig_value(value.trim())),
                "email" => email = Some(unquote_gitconfig_value(value.trim())),
                _ => {}
            }
        }
    }
    match (name, email) {
        (Some(name), Some(email)) => Some((name, email)),
        _ => None,
    }
}

fn split_key_value(line: &str) -> Option<(&str, &str)> {
    let line = line.trim_start_matches(['\t', ' ']);
    let idx = line.find('=')?;
    Some((line[..idx].trim(), line[idx + 1..].trim()))
}

/// Quote/escape a gitconfig value per git's rules: values containing whitespace
/// at the edges, comment characters, quotes, or backslashes are wrapped in
/// double quotes with `\` and `"` escaped.
fn escape_gitconfig_value(value: &str) -> String {
    let needs_quotes = value.is_empty()
        || value.starts_with(' ')
        || value.starts_with('\t')
        || value.ends_with(' ')
        || value.ends_with('\t')
        || value.contains('"')
        || value.contains(';')
        || value.contains('#')
        || value.contains('\\');
    if !needs_quotes {
        return value.to_string();
    }
    let mut out = String::from("\"");
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            _ => out.push(ch),
        }
    }
    out.push('"');
    out
}

/// Inverse of [`escape_gitconfig_value`]: strip surrounding double quotes and
/// unescape `\"` / `\\`. Bare values are returned trimmed as-is.
fn unquote_gitconfig_value(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.len() >= 2 && trimmed.starts_with('"') && trimmed.ends_with('"') {
        let inner = &trimmed[1..trimmed.len() - 1];
        let mut out = String::with_capacity(inner.len());
        let mut chars = inner.chars();
        while let Some(ch) = chars.next() {
            if ch == '\\' {
                if let Some(escaped) = chars.next() {
                    out.push(escaped);
                }
            } else {
                out.push(ch);
            }
        }
        out
    } else {
        trimmed.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_inserts_user_section_when_absent() {
        let merged = merge_user_identity("", "Ada Lovelace", "ada@example.com");
        assert!(merged.contains("[user]"));
        assert!(merged.contains("name = Ada Lovelace"));
        assert!(merged.contains("email = ada@example.com"));
    }

    #[test]
    fn merge_preserves_other_sections_and_replaces_user() {
        let existing = "[core]\n\trepositoryformatversion = 0\n\n[user]\n\tname = Old\n\temail = old@example.com\n\n[remote \"origin\"]\n\turl = https://example.com\n";
        let merged = merge_user_identity(existing, "New Name", "new@example.com");
        assert_eq!(merged.matches("[user]").count(), 1);
        assert!(!merged.contains("Old"));
        assert!(!merged.contains("old@example.com"));
        assert!(merged.contains("name = New Name"));
        assert!(merged.contains("email = new@example.com"));
        // Other sections survive.
        assert!(merged.contains("[core]"));
        assert!(merged.contains("repositoryformatversion = 0"));
        assert!(merged.contains("[remote \"origin\"]"));
        assert!(merged.contains("url = https://example.com"));
    }

    #[test]
    fn roundtrip_read_after_write() {
        let merged = merge_user_identity("", "Grace Hopper", "grace@navy.mil");
        let (name, email) = parse_user_identity(&merged).expect("identity present");
        assert_eq!(name, "Grace Hopper");
        assert_eq!(email, "grace@navy.mil");
    }

    #[test]
    fn parses_tabbed_and_spaced_keys() {
        let body = "[user]\n\tname = Tabbed\n    email = spaced@example.com\n";
        let (name, email) = parse_user_identity(body).expect("identity present");
        assert_eq!(name, "Tabbed");
        assert_eq!(email, "spaced@example.com");
    }

    #[test]
    fn read_returns_none_without_user_section() {
        assert_eq!(parse_user_identity("[core]\n\tbare = false\n"), None);
        assert_eq!(parse_user_identity(""), None);
    }

    #[test]
    fn escapes_quotes_and_comment_chars() {
        let escaped = escape_gitconfig_value("a\"b#c;d\\e");
        assert!(escaped.starts_with('"'));
        assert!(escaped.ends_with('"'));
        // Round-trips through the unquoter.
        assert_eq!(unquote_gitconfig_value(&escaped), "a\"b#c;d\\e");
    }

    #[test]
    fn invalid_handle_identity_methods_reject() {
        let h = EngineHandle::new(0);
        assert_eq!(
            h.configure_git_identity("x", "y").unwrap_err().code(),
            "invalid_handle"
        );
        assert_eq!(
            h.read_git_identity().unwrap_err().code(),
            "invalid_handle"
        );
    }
}
