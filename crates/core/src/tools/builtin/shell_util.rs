//! Shared utility functions used by shell_inject, shell_safe, and shell_policy.

/// Returns `true` if `word` looks like a shell variable assignment prefix
/// (e.g. `FOO=bar`).
pub(super) fn is_shell_assignment_prefix(word: &str) -> bool {
    let Some((name, _)) = word.split_once('=') else {
        return false;
    };
    let mut chars = name.chars();
    matches!(chars.next(), Some('_') | Some('A'..='Z') | Some('a'..='z'))
        && chars.all(|c| c == '_' || c.is_ascii_alphanumeric())
}

/// Extracts the basename of a command path, stripping directory prefixes and
/// the `.cmd` suffix (for Windows compatibility).
pub(super) fn command_basename(command: &str) -> &str {
    command
        .rsplit('/')
        .next()
        .unwrap_or(command)
        .trim()
        .trim_end_matches(".cmd")
}
