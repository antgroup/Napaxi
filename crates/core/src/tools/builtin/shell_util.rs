//! Shared utility functions used by shell_inject, shell_safe, and shell_policy.

/// Returns `true` if `word` looks like a shell variable assignment prefix
/// (e.g. `FOO=bar`). Recognizes plain `NAME=value`, `NAME+=value` (already
/// covered by `split_once('=')`), and array-subscript forms `NAME[idx]=value`
/// / `NAME[$idx]=value`, since Bash arithmetic-evaluates the subscript (a
/// recursive shell evaluation surface — idea ref: OpenClaw #187499).
pub(super) fn is_shell_assignment_prefix(word: &str) -> bool {
    let Some((name, _)) = word.split_once('=') else {
        return false;
    };
    // Array subscript: `IDENT[...]` — strip the subscript before validating
    // the head. The subscript body itself is a recursive evaluation surface
    // (Bash arithmetic) and is inspected separately by the policy layer.
    let head = match name.find('[') {
        Some(idx) => &name[..idx],
        None => name,
    };
    let mut chars = head.chars();
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
