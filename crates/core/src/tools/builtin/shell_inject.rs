//! Shell injection / netcat data piping detection.

use super::shell_util::is_shell_assignment_prefix;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum ShellSyntaxToken {
    Word(String),
    Pipe,
    RedirectIn,
    HereDoc,
    Segment,
    /// Command/process substitution: `$(body)`, `` `body` ``, `<(body)`, `>(body)`.
    /// The inner text is captured so the hard gate can recurse into it — the real
    /// shell evaluates this content, so static analysis must too.
    Substitution(String),
    /// An unquoted variable expansion (`$VAR` / `${...}`). Carries no value (we do
    /// not expand), only marks that word-splitting/substitution happens here — so
    /// `rm$IFS-rf$IFS/` lexes as `Word(rm) Expansion Word(-rf) Expansion Word(/)`.
    Expansion,
}

pub(super) fn detect_shell_injection(command: &str) -> Option<&'static str> {
    if command.bytes().any(|b| b == 0) {
        return Some("null byte in command");
    }
    let lower = command.to_ascii_lowercase();
    if (lower.contains("base64 -d") || lower.contains("base64 --decode"))
        && contains_shell_pipe(&lower)
    {
        return Some("base64 decode piped to shell");
    }
    if (lower.contains("printf") || lower.contains("echo -e") || lower.contains("echo $'"))
        && (lower.contains("\\x") || lower.contains("\\0"))
        && contains_shell_pipe(&lower)
    {
        return Some("encoded escape sequences piped to shell");
    }
    if (lower.contains("xxd -r") || has_command_token(&lower, "od")) && contains_shell_pipe(&lower)
    {
        return Some("binary decode piped to shell");
    }
    if (has_command_token(&lower, "dig")
        || has_command_token(&lower, "nslookup")
        || has_command_token(&lower, "host"))
        && has_command_substitution(&lower)
    {
        return Some("potential DNS exfiltration via command substitution");
    }
    if detect_netcat_with_data_piping(command) {
        return Some("netcat with data piping");
    }
    if lower.contains("curl")
        && (lower.contains("-d @")
            || lower.contains("-d@")
            || lower.contains("--data @")
            || lower.contains("--data-binary @")
            || lower.contains("--upload-file"))
    {
        return Some("curl posting file contents");
    }
    if lower.contains("wget") && lower.contains("--post-file") {
        return Some("wget posting file contents");
    }
    if (lower.contains("| rev") || lower.contains("|rev")) && contains_shell_pipe(&lower) {
        return Some("string reversal piped to shell");
    }
    None
}

fn contains_shell_pipe(lower: &str) -> bool {
    ["sh", "bash", "zsh", "dash", "/bin/sh", "/bin/bash"]
        .iter()
        .any(|shell| has_pipe_to(lower, shell))
}

fn detect_netcat_with_data_piping(command: &str) -> bool {
    let tokens = shell_syntax_tokens(&strip_heredoc_bodies(command));
    let mut expecting_command = true;
    let mut previous_was_pipe = false;
    let mut current_command_is_netcat = false;

    for token in tokens {
        match token {
            ShellSyntaxToken::Word(word) => {
                if expecting_command {
                    if is_shell_assignment_prefix(&word) || word == "command" {
                        continue;
                    }
                    current_command_is_netcat = is_netcat_command(&word);
                    if current_command_is_netcat && previous_was_pipe {
                        return true;
                    }
                    expecting_command = false;
                    previous_was_pipe = false;
                }
            }
            ShellSyntaxToken::RedirectIn | ShellSyntaxToken::HereDoc => {
                if current_command_is_netcat {
                    return true;
                }
            }
            ShellSyntaxToken::Pipe => {
                expecting_command = true;
                previous_was_pipe = true;
                current_command_is_netcat = false;
            }
            ShellSyntaxToken::Segment => {
                expecting_command = true;
                previous_was_pipe = false;
                current_command_is_netcat = false;
            }
            // A substitution/expansion in command position means the executable is
            // dynamic — not a statically recognizable netcat invocation.
            ShellSyntaxToken::Substitution(_) | ShellSyntaxToken::Expansion => {
                if expecting_command {
                    current_command_is_netcat = false;
                    expecting_command = false;
                    previous_was_pipe = false;
                }
            }
        }
    }

    false
}

fn is_netcat_command(word: &str) -> bool {
    let command = word.rsplit('/').next().unwrap_or(word).to_ascii_lowercase();
    matches!(command.as_str(), "nc" | "ncat" | "netcat")
}

pub(super) fn strip_heredoc_bodies(command: &str) -> String {
    let mut output = String::with_capacity(command.len());
    let mut pending_delimiters: std::collections::VecDeque<String> =
        std::collections::VecDeque::new();

    for line in command.lines() {
        if let Some(delimiter) = pending_delimiters.front() {
            if line.trim_matches('\t') == delimiter {
                pending_delimiters.pop_front();
                output.push_str(line);
            }
            output.push('\n');
            continue;
        }

        pending_delimiters.extend(find_heredoc_delimiters(line));
        output.push_str(line);
        output.push('\n');
    }

    output
}

fn find_heredoc_delimiters(line: &str) -> Vec<String> {
    let tokens = shell_syntax_tokens(line);
    let mut delimiters = Vec::new();
    let mut after_heredoc = false;

    for token in tokens {
        match token {
            ShellSyntaxToken::HereDoc => after_heredoc = true,
            ShellSyntaxToken::Word(word) if after_heredoc => {
                if let Some(delimiter) = normalize_heredoc_delimiter(&word) {
                    delimiters.push(delimiter);
                }
                after_heredoc = false;
            }
            ShellSyntaxToken::Pipe
            | ShellSyntaxToken::RedirectIn
            | ShellSyntaxToken::Segment
            | ShellSyntaxToken::Substitution(_)
            | ShellSyntaxToken::Expansion => after_heredoc = false,
            ShellSyntaxToken::Word(_) => {}
        }
    }

    delimiters
}

fn normalize_heredoc_delimiter(word: &str) -> Option<String> {
    let delimiter = word.trim_matches(|c| c == '\'' || c == '"');
    if delimiter.is_empty() || delimiter.starts_with('&') {
        None
    } else {
        Some(delimiter.to_string())
    }
}

pub(super) fn shell_syntax_tokens(command: &str) -> Vec<ShellSyntaxToken> {
    let bytes = command.as_bytes();
    let mut tokens = Vec::new();
    let mut word = String::new();
    let mut i = 0;
    let mut quote: Option<u8> = None;

    while i < bytes.len() {
        let b = bytes[i];
        if let Some(q) = quote {
            // Single quotes: every byte is literal until the closing quote — no
            // substitution or expansion happens, matching the real shell.
            if q == b'\'' {
                if b == q {
                    quote = None;
                } else {
                    word.push(b as char);
                }
                i += 1;
                continue;
            }
            // Double quotes: word-splitting/globbing are suppressed, but the
            // shell STILL evaluates command substitution (`$(…)`, `` `…` ``) and
            // variable expansion (`$VAR` / `${…}`) inside them. Static analysis
            // must do the same, or `echo "$(rm -rf /)"` slips past the hard gate.
            if b == b'\\' && i + 1 < bytes.len() {
                // In double quotes `\` only escapes `$ ` ` " \ ` and newline; for
                // those, the next byte is literal (so `\$(…)` is a literal `$(…)`,
                // NOT a substitution). Treating any `\X` as literal `X` is a safe
                // over-approximation here — it can only make a substitution look
                // less dangerous, never hide a real one.
                word.push(bytes[i + 1] as char);
                i += 2;
                continue;
            }
            if b == b'"' {
                quote = None;
                i += 1;
                continue;
            }
            if b == b'$' && i + 1 < bytes.len() && bytes[i + 1] == b'(' {
                push_shell_word(&mut tokens, &mut word);
                let (body, next) = read_balanced_parens(bytes, i + 1);
                tokens.push(ShellSyntaxToken::Substitution(body));
                i = next;
                continue;
            }
            if b == b'`' {
                push_shell_word(&mut tokens, &mut word);
                let (body, next) = read_backtick(bytes, i + 1);
                tokens.push(ShellSyntaxToken::Substitution(body));
                i = next;
                continue;
            }
            if b == b'$'
                && let Some(next) = read_variable_expansion(bytes, i)
            {
                push_shell_word(&mut tokens, &mut word);
                tokens.push(ShellSyntaxToken::Expansion);
                i = next;
                continue;
            }
            word.push(b as char);
            i += 1;
            continue;
        }

        match b {
            b'\'' | b'"' => {
                quote = Some(b);
                i += 1;
            }
            b'\\' if i + 1 < bytes.len() => {
                word.push(bytes[i + 1] as char);
                i += 2;
            }
            // `$(...)` command substitution and `${...}` / `$VAR` expansion.
            b'$' if i + 1 < bytes.len() && bytes[i + 1] == b'(' => {
                push_shell_word(&mut tokens, &mut word);
                let (body, next) = read_balanced_parens(bytes, i + 1);
                tokens.push(ShellSyntaxToken::Substitution(body));
                i = next;
            }
            b'$' => {
                // `${...}` / `$VAR` expand; a bare `$` (no name follows) is literal.
                if let Some(next) = read_variable_expansion(bytes, i) {
                    push_shell_word(&mut tokens, &mut word);
                    tokens.push(ShellSyntaxToken::Expansion);
                    i = next;
                } else {
                    word.push('$');
                    i += 1;
                }
            }
            // Backtick command substitution: `` `...` ``.
            b'`' => {
                push_shell_word(&mut tokens, &mut word);
                let (body, next) = read_backtick(bytes, i + 1);
                tokens.push(ShellSyntaxToken::Substitution(body));
                i = next;
            }
            // Process substitution `<(...)` / `>(...)`.
            b'<' | b'>' if i + 1 < bytes.len() && bytes[i + 1] == b'(' => {
                push_shell_word(&mut tokens, &mut word);
                let (body, next) = read_balanced_parens(bytes, i + 1);
                tokens.push(ShellSyntaxToken::Substitution(body));
                i = next;
            }
            b' ' | b'\t' | b'\r' => {
                push_shell_word(&mut tokens, &mut word);
                i += 1;
            }
            b'\n' | b';' => {
                push_shell_word(&mut tokens, &mut word);
                tokens.push(ShellSyntaxToken::Segment);
                i += 1;
            }
            b'|' => {
                push_shell_word(&mut tokens, &mut word);
                if i + 1 < bytes.len() && bytes[i + 1] == b'|' {
                    tokens.push(ShellSyntaxToken::Segment);
                    i += 2;
                } else {
                    tokens.push(ShellSyntaxToken::Pipe);
                    i += 1;
                }
            }
            b'&' if i + 1 < bytes.len() && bytes[i + 1] == b'&' => {
                push_shell_word(&mut tokens, &mut word);
                tokens.push(ShellSyntaxToken::Segment);
                i += 2;
            }
            b'<' => {
                push_shell_word(&mut tokens, &mut word);
                if i + 1 < bytes.len() && bytes[i + 1] == b'<' {
                    tokens.push(ShellSyntaxToken::HereDoc);
                    i += 2;
                    if i < bytes.len() && bytes[i] == b'<' {
                        i += 1;
                    }
                    if i < bytes.len() && bytes[i] == b'-' {
                        i += 1;
                    }
                } else {
                    tokens.push(ShellSyntaxToken::RedirectIn);
                    i += 1;
                }
            }
            _ => {
                word.push(b as char);
                i += 1;
            }
        }
    }

    push_shell_word(&mut tokens, &mut word);
    tokens
}

fn push_shell_word(tokens: &mut Vec<ShellSyntaxToken>, word: &mut String) {
    if !word.is_empty() {
        tokens.push(ShellSyntaxToken::Word(std::mem::take(word)));
    }
}

/// Reads a `$(...)` / `<(...)` / `>(...)` body starting at the opening `(`
/// (`bytes[open]` must be `b'('`). Returns the inner text (paren-balanced,
/// excluding the outer parens) and the index just past the closing `)`. If the
/// parens never balance, consumes to end-of-input.
fn read_balanced_parens(bytes: &[u8], open: usize) -> (String, usize) {
    let mut depth = 0usize;
    let mut body = String::new();
    let mut i = open;
    while i < bytes.len() {
        match bytes[i] {
            b'(' => {
                if depth > 0 {
                    body.push('(');
                }
                depth += 1;
            }
            b')' => {
                depth -= 1;
                if depth == 0 {
                    return (body, i + 1);
                }
                body.push(')');
            }
            b => body.push(b as char),
        }
        i += 1;
    }
    (body, i)
}

/// Reads a backtick-substitution body starting just past the opening backtick.
/// Returns the inner text and the index just past the closing backtick (or
/// end-of-input if unterminated).
fn read_backtick(bytes: &[u8], start: usize) -> (String, usize) {
    let mut body = String::new();
    let mut i = start;
    while i < bytes.len() {
        if bytes[i] == b'`' {
            return (body, i + 1);
        }
        body.push(bytes[i] as char);
        i += 1;
    }
    (body, i)
}

/// If a variable expansion begins at `bytes[dollar]` (`b'$'`), returns the index
/// just past it: `${...}` (brace-balanced) or `$NAME` / `$1` / `$@` / `$*` / `$?`
/// / `$$` / `$#`. Returns `None` for a bare `$` with nothing expandable after it.
fn read_variable_expansion(bytes: &[u8], dollar: usize) -> Option<usize> {
    let after = dollar + 1;
    if after >= bytes.len() {
        return None;
    }
    match bytes[after] {
        b'{' => {
            let mut i = after + 1;
            while i < bytes.len() && bytes[i] != b'}' {
                i += 1;
            }
            // Past the closing brace if present, else end-of-input.
            Some((i + 1).min(bytes.len()))
        }
        // Special single-char parameters.
        b'@' | b'*' | b'?' | b'$' | b'#' | b'!' | b'-' | b'0'..=b'9' => Some(after + 1),
        // `$NAME`: a run of name characters.
        b'_' | b'A'..=b'Z' | b'a'..=b'z' => {
            let mut i = after;
            while i < bytes.len() && (bytes[i] == b'_' || bytes[i].is_ascii_alphanumeric()) {
                i += 1;
            }
            Some(i)
        }
        _ => None,
    }
}

fn has_pipe_to(lower: &str, shell: &str) -> bool {
    for prefix in ["| ", "|"] {
        let pattern = format!("{prefix}{shell}");
        for (idx, _) in lower.match_indices(&pattern) {
            let end = idx + pattern.len();
            if end >= lower.len()
                || matches!(
                    lower.as_bytes()[end],
                    b' ' | b'\t' | b'\n' | b';' | b'|' | b'&' | b')'
                )
            {
                return true;
            }
        }
    }
    false
}

fn has_command_token(lower: &str, command: &str) -> bool {
    lower
        .split(|c: char| !c.is_ascii_alphanumeric() && c != '_' && c != '-' && c != '/')
        .any(|token| token == command)
}

fn has_command_substitution(lower: &str) -> bool {
    lower.contains("$(") || lower.contains('`')
}
