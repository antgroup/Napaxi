//! Known-safe command allow-list with per-argument validation.
//!
//! Ported from codex's `is_known_safe_command`
//! (`shell-command/src/command_safety/is_safe_command.rs`). A command is
//! "known safe" only when every segment of a plain pipeline is itself a
//! read-only command whose arguments cannot write, delete, or execute.
//!
//! Built on the existing [`shell_syntax_tokens`] lexer — no new parser. The
//! allow-list mirrors codex faithfully; extending it is a deliberate decision,
//! not a default.

use super::shell_inject::{ShellSyntaxToken, shell_syntax_tokens, strip_heredoc_bodies};

/// Returns true when the whole command is a plain pipeline of known-safe,
/// read-only segments. Anything unrecognized returns false so the caller's
/// approval posture decides what to do.
pub(super) fn is_known_safe_command(command: &str) -> bool {
    let tokens = shell_syntax_tokens(&strip_heredoc_bodies(command));
    let mut segments: Vec<Vec<String>> = Vec::new();
    let mut current: Vec<String> = Vec::new();
    for token in tokens {
        match token {
            ShellSyntaxToken::Word(word) => current.push(word),
            ShellSyntaxToken::Pipe | ShellSyntaxToken::Segment => {
                segments.push(std::mem::take(&mut current));
            }
            // Redirections and heredocs can write files or feed data, so a
            // command using them is not "plain read-only".
            ShellSyntaxToken::RedirectIn | ShellSyntaxToken::HereDoc => return false,
            // Command/process substitution and variable expansion are evaluated
            // by the real shell — their effect can't be statically bounded, so a
            // command containing them is never known-safe (e.g. `echo $(rm -rf /)`,
            // `cat $FILE`). The hard gate inspects the substitution body separately.
            ShellSyntaxToken::Substitution(_) | ShellSyntaxToken::Expansion => return false,
        }
    }
    segments.push(current);

    let non_empty: Vec<&Vec<String>> = segments.iter().filter(|seg| !seg.is_empty()).collect();
    !non_empty.is_empty() && non_empty.iter().all(|seg| is_known_safe_segment(seg))
}

/// Normalizes an executable token to its lookup key: path basename, with
/// `zsh` folded to `bash` to match codex.
fn command_lookup_key(raw: &str) -> &str {
    let base = super::shell_util::command_basename(raw);
    if base == "zsh" { "bash" } else { base }
}

fn is_known_safe_segment(words: &[String]) -> bool {
    let Some(cmd0) = words.first().map(String::as_str) else {
        return false;
    };

    match command_lookup_key(cmd0) {
        // ── A. pure read-only commands (no unsafe arguments possible) ──────
        "cat" | "cd" | "cut" | "echo" | "expr" | "false" | "grep" | "head" | "id" | "ls" | "nl"
        | "paste" | "pwd" | "rev" | "seq" | "stat" | "tail" | "tr" | "true" | "uname" | "uniq"
        | "wc" | "which" | "whoami" | "numfmt" | "tac" => true,

        // ── B. commands safe only with read-only arguments ─────────────────
        "find" => !words
            .iter()
            .any(|arg| UNSAFE_FIND_OPTIONS.contains(&arg.as_str())),

        "rg" => !words.iter().any(|arg| {
            UNSAFE_RG_OPTIONS_WITHOUT_ARGS.contains(&arg.as_str())
                || UNSAFE_RG_OPTIONS_WITH_ARGS
                    .iter()
                    .any(|opt| arg == opt || arg.starts_with(&format!("{opt}=")))
        }),

        "base64" => !words
            .iter()
            .skip(1)
            .any(|arg| arg.starts_with("-o") || arg == "--output" || arg.starts_with("--output=")),

        // Only `sed -n {N|M,N}p [file]` (print a line range).
        "sed" => {
            words.len() <= 4
                && words.get(1).map(String::as_str) == Some("-n")
                && is_valid_sed_n_arg(words.get(2).map(String::as_str))
        }

        "git" => is_safe_git_command(words),

        // ── C. everything else: not known safe ─────────────────────────────
        _ => false,
    }
}

#[rustfmt::skip]
const UNSAFE_FIND_OPTIONS: &[&str] = &[
    // Execute arbitrary commands.
    "-exec", "-execdir", "-ok", "-okdir",
    // Delete matching files.
    "-delete",
    // Write pathnames to a file.
    "-fls", "-fprint", "-fprint0", "-fprintf",
];

const UNSAFE_RG_OPTIONS_WITH_ARGS: &[&str] = &[
    // Runs a command for each match.
    "--pre",
    // Can obtain the local hostname.
    "--hostname-bin",
];

const UNSAFE_RG_OPTIONS_WITHOUT_ARGS: &[&str] = &[
    // Calls out to decompression tools.
    "--search-zip",
    "-z",
];

// ── git ────────────────────────────────────────────────────────────────────

const UNSAFE_GIT_GLOBAL_OPTIONS: &[&str] = &[
    "-C",
    "-c",
    "-p",
    "--config-env",
    "--exec-path",
    "--git-dir",
    "--namespace",
    "--paginate",
    "--super-prefix",
    "--work-tree",
];

const UNSAFE_GIT_SUBCOMMAND_OPTIONS: &[&str] = &["--output", "--ext-diff", "--textconv", "--exec"];

/// `git` is safe only for read-only subcommands, with no global option that can
/// redirect the repo/config/exec path (which would bypass the subcommand
/// allow-list, e.g. `git -C /other status` or `git -c core.pager=...`).
fn is_safe_git_command(words: &[String]) -> bool {
    let Some((sub_idx, sub)) = find_git_subcommand(words) else {
        return false;
    };
    let global_args = &words[1..sub_idx];
    if global_args
        .iter()
        .any(|arg| is_unsafe_git_global_option(arg))
    {
        return false;
    }
    let sub_args = &words[sub_idx + 1..];
    match sub {
        "status" | "log" | "diff" | "show" => git_sub_args_read_only(sub_args),
        "branch" => git_sub_args_read_only(sub_args) && git_branch_is_read_only(sub_args),
        _ => false,
    }
}

fn is_unsafe_git_global_option(arg: &str) -> bool {
    if UNSAFE_GIT_GLOBAL_OPTIONS.contains(&arg) {
        return true;
    }
    // Inline-value forms: `--git-dir=...`, `-Cpath`, `-ckey=val`.
    if arg.starts_with("--config-env=")
        || arg.starts_with("--exec-path=")
        || arg.starts_with("--git-dir=")
        || arg.starts_with("--namespace=")
        || arg.starts_with("--super-prefix=")
        || arg.starts_with("--work-tree=")
    {
        return true;
    }
    (arg.starts_with("-C") || arg.starts_with("-c")) && arg.len() > 2
}

fn git_sub_args_read_only(args: &[String]) -> bool {
    !args.iter().any(|arg| {
        UNSAFE_GIT_SUBCOMMAND_OPTIONS
            .iter()
            .any(|opt| arg == opt || arg.starts_with(&format!("{opt}=")))
    })
}

/// `git branch` is safe only when arguments clearly indicate a read-only query,
/// never a create/rename/delete.
fn git_branch_is_read_only(branch_args: &[String]) -> bool {
    if branch_args.is_empty() {
        return true;
    }
    let mut saw_read_only_flag = false;
    for arg in branch_args.iter().map(String::as_str) {
        match arg {
            "--list" | "-l" | "--show-current" | "-a" | "--all" | "-r" | "--remotes" | "-v"
            | "-vv" | "--verbose" => saw_read_only_flag = true,
            _ if arg.starts_with("--format=") => saw_read_only_flag = true,
            _ => return false,
        }
    }
    saw_read_only_flag
}

/// Finds the first git subcommand, skipping known global options (and the
/// values of those that take one) so `git -C dir status` resolves to `status`.
fn find_git_subcommand(words: &[String]) -> Option<(usize, &str)> {
    if command_lookup_key(words.first()?.as_str()) != "git" {
        return None;
    }
    const SUBCOMMANDS: &[&str] = &["status", "log", "diff", "show", "branch"];
    const GLOBAL_OPTS_WITH_VALUE: &[&str] = &[
        "-C",
        "-c",
        "--config-env",
        "--exec-path",
        "--git-dir",
        "--namespace",
        "--super-prefix",
        "--work-tree",
    ];
    let mut skip_next = false;
    for (idx, arg) in words.iter().enumerate().skip(1) {
        if skip_next {
            skip_next = false;
            continue;
        }
        let arg = arg.as_str();
        // Inline-value global option (`--git-dir=...`, `-Cpath`): consumes value itself.
        if arg.contains('=') || ((arg.starts_with("-C") || arg.starts_with("-c")) && arg.len() > 2)
        {
            continue;
        }
        if GLOBAL_OPTS_WITH_VALUE.contains(&arg) {
            skip_next = true;
            continue;
        }
        if arg.starts_with('-') {
            // Other global flag without a value (e.g. -p, --paginate).
            continue;
        }
        if SUBCOMMANDS.contains(&arg) {
            return Some((idx, arg));
        }
        // First non-option token is some other subcommand: not in allow-list.
        return None;
    }
    None
}

/// Returns true if `arg` matches `^(\d+,)?\d+p$` (a `sed -n` line-range print).
fn is_valid_sed_n_arg(arg: Option<&str>) -> bool {
    let Some(core) = arg.and_then(|s| s.strip_suffix('p')) else {
        return false;
    };
    let parts: Vec<&str> = core.split(',').collect();
    match parts.as_slice() {
        [num] => !num.is_empty() && num.chars().all(|c| c.is_ascii_digit()),
        [a, b] => {
            !a.is_empty()
                && !b.is_empty()
                && a.chars().all(|c| c.is_ascii_digit())
                && b.chars().all(|c| c.is_ascii_digit())
        }
        _ => false,
    }
}
