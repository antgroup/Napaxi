//! Shell command security decision.
//!
//! Three-step model (SDK provides the mechanism, the host selects the policy):
//!
//! 1. **Hard gate** — destructive / data-exfiltration commands are rejected in
//!    every mode (a core gate, never relaxed). Built on token-stream parsing.
//! 2. **Known-safe allow-list** — read-only commands run automatically
//!    regardless of mode (see [`super::shell_safe`]).
//! 3. **Approval posture** — everything else is decided by [`ShellApprovalMode`]:
//!    prompt the host, run directly, reject, or delegate to a policy hook.
//!
//! `NEVER_AUTO_APPROVE_PATTERNS` are "dangerous but legitimate" commands
//! (`sudo`, `git push -f`, `kill -9`, …). They are NOT the hard gate: they are
//! simply *not known-safe*, so the mode decides their fate. Under `TrustedAllow`
//! they run; under `OnRequest`/`ReadOnlyOnly` they prompt.

use std::time::Duration;

use crate::tool_registry::{ToolRequestBridge, request_host_tool_execution};
use crate::types::{ShellApprovalMode, ShellDecision};

use super::shell_inject::{
    ShellSyntaxToken, detect_shell_injection, shell_syntax_tokens, strip_heredoc_bodies,
};
use super::shell_safe::is_known_safe_command;
use super::shell_util::{command_basename, is_shell_assignment_prefix};
use super::{APPROVAL_TOOL_NAME, parse_approval_response};

/// Classifies a command under the given approval mode into a [`ShellDecision`].
///
/// The hard gate (`Reject`) and the known-safe allow-list (`Allow`) are applied
/// before the mode is consulted, so they hold in every mode.
pub(super) fn classify_shell_command(command: &str, mode: ShellApprovalMode) -> ShellDecision {
    // ① Hard gate — rejected in every mode.
    if let Some(reason) = hard_gate_reason(command) {
        return ShellDecision::Reject(format!("shell command blocked: {reason}"));
    }
    // ② Known-safe read-only commands run automatically, regardless of mode.
    if is_known_safe_command(command) {
        return ShellDecision::Allow;
    }
    // ③ Approval posture decides the rest.
    match mode {
        ShellApprovalMode::ReadOnlyOnly => ShellDecision::Prompt(
            "command is not known-safe read-only; approval required".to_string(),
        ),
        ShellApprovalMode::OnRequest => {
            ShellDecision::Prompt("command requires approval".to_string())
        }
        ShellApprovalMode::TrustedAllow => ShellDecision::Allow,
        ShellApprovalMode::Custom => {
            ShellDecision::Prompt("command deferred to host policy".to_string())
        }
    }
}

/// The hard gate: destructive or data-exfiltration commands that are rejected
/// regardless of approval mode. Returns a human-readable reason when blocked.
pub(super) fn hard_gate_reason(command: &str) -> Option<&'static str> {
    hard_gate_reason_depth(command, 0)
}

/// Maximum substitution-nesting depth the hard gate recurses into. Bounds
/// pathological inputs like `$($($(…)))` while covering every realistic case.
/// Beyond this depth the gate fails CLOSED (see `hard_gate_reason_depth`).
const MAX_SUBSTITUTION_DEPTH: usize = 8;

/// Reason returned when substitution nesting exceeds [`MAX_SUBSTITUTION_DEPTH`].
const DEEP_NESTING_REASON: &str =
    "command substitution nested too deeply to analyze; rejected for safety";

fn hard_gate_reason_depth(command: &str, depth: usize) -> Option<&'static str> {
    if let Some(reason) = blocked_shell_command_reason(command) {
        return Some(reason);
    }
    if let Some(reason) = detect_shell_injection(command) {
        return Some(reason);
    }
    // The real shell evaluates command/process substitutions; so must we. Recurse
    // into each `$(…)` / `` `…` `` / `<(…)` body so e.g. `echo $(rm -rf /)` is a
    // hard-gate hit even though `echo` itself is harmless.
    for token in shell_syntax_tokens(&strip_heredoc_bodies(command)) {
        let ShellSyntaxToken::Substitution(body) = token else {
            continue;
        };
        // Fail CLOSED past the recursion bound: the shell still evaluates the
        // inner command, so silently allowing a too-deep nest would let
        // `$($($(…rm -rf /…)))` escape the gate. Reject instead.
        if depth + 1 >= MAX_SUBSTITUTION_DEPTH {
            return Some(DEEP_NESTING_REASON);
        }
        if let Some(reason) = hard_gate_reason_depth(&body, depth + 1) {
            return Some(reason);
        }
    }
    None
}

#[cfg(test)]
pub(super) fn validate_shell_command(command: &str) -> Result<(), String> {
    match classify_shell_command(command, ShellApprovalMode::OnRequest) {
        ShellDecision::Reject(reason) => Err(reason),
        ShellDecision::Allow | ShellDecision::Prompt(_) => Ok(()),
    }
}

pub(super) async fn ensure_shell_command_allowed(
    command: &str,
    mode: ShellApprovalMode,
    approval_bridge: Option<ToolRequestBridge>,
) -> Result<(), String> {
    match classify_shell_command(command, mode) {
        ShellDecision::Allow => Ok(()),
        ShellDecision::Reject(reason) => Err(reason),
        ShellDecision::Prompt(reason) => {
            request_shell_approval(command, &reason, approval_bridge).await
        }
    }
}

async fn request_shell_approval(
    command: &str,
    reason: &str,
    approval_bridge: Option<ToolRequestBridge>,
) -> Result<(), String> {
    let Some(bridge) = approval_bridge else {
        return Err(format!("{reason}, and no approval bridge is registered"));
    };
    let response = request_host_tool_execution(
        bridge,
        APPROVAL_TOOL_NAME,
        serde_json::json!({
            "tool_name": "shell",
            "description": "Approve shell command execution",
            "parameters": serde_json::json!({ "command": command }).to_string(),
            "allow_always": false
        }),
        Duration::from_secs(600),
    )
    .await?;
    parse_approval_response(&response)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum GitShellIntent {
    GitCommand {
        preferred_tool: Option<&'static str>,
        args: Vec<String>,
    },
    InstallGit,
}

pub(crate) fn git_shell_intent(command: &str) -> Option<GitShellIntent> {
    git_shell_intent_depth(command, 0)
}

fn git_shell_intent_depth(command: &str, depth: usize) -> Option<GitShellIntent> {
    let stripped = strip_heredoc_bodies(command);
    let mut segment = Vec::new();
    for token in shell_syntax_tokens(&stripped) {
        match token {
            ShellSyntaxToken::Word(word) => segment.push(word),
            ShellSyntaxToken::Pipe | ShellSyntaxToken::Segment => {
                if let Some(intent) = git_segment_intent(&segment) {
                    return Some(intent);
                }
                segment.clear();
            }
            ShellSyntaxToken::Substitution(body) if depth < MAX_SUBSTITUTION_DEPTH => {
                if let Some(intent) = git_shell_intent_depth(&body, depth + 1) {
                    return Some(intent);
                }
            }
            ShellSyntaxToken::RedirectIn
            | ShellSyntaxToken::HereDoc
            | ShellSyntaxToken::Substitution(_)
            | ShellSyntaxToken::Expansion => {}
        }
    }
    git_segment_intent(&segment)
}

fn git_segment_intent(words: &[String]) -> Option<GitShellIntent> {
    let (command, args) = executable_segment(words)?;
    if command == "git" {
        return Some(GitShellIntent::GitCommand {
            preferred_tool: git_preferred_tool(args),
            args: args.to_vec(),
        });
    }
    if package_manager_installs_git(command, args) {
        return Some(GitShellIntent::InstallGit);
    }
    None
}

fn executable_segment(words: &[String]) -> Option<(&str, &[String])> {
    let mut index = executable_word_index(words)?;
    loop {
        let command = command_basename(&words[index]);
        let mut args_start = index + 1;
        if command == "sudo" {
            while args_start < words.len() && words[args_start].starts_with('-') {
                args_start += 1;
            }
            if args_start >= words.len() {
                return Some((command, &words[index + 1..]));
            }
            index = args_start;
            continue;
        }
        return Some((command, &words[args_start..]));
    }
}

fn git_preferred_tool(args: &[String]) -> Option<&'static str> {
    let mut index = 0;
    while index < args.len() {
        let arg = args[index].as_str();
        if matches!(arg, "-C" | "-c" | "--git-dir" | "--work-tree") {
            index += 2;
            continue;
        }
        if arg.starts_with('-') {
            index += 1;
            continue;
        }
        return match arg {
            "clone" => Some("git_clone"),
            "status" => Some("git_status"),
            "diff" => Some("git_diff"),
            "branch" => Some("git_list_branches"),
            "checkout" | "switch" => Some("git_switch_branch"),
            "remote" => match args.get(index + 1).map(String::as_str) {
                Some("add" | "set-url" | "remove" | "rm") => Some("git_set_remote"),
                _ => Some("git_list_remotes"),
            },
            "fetch" => Some("git_fetch"),
            _ => None,
        };
    }
    None
}

fn package_manager_installs_git(command: &str, args: &[String]) -> bool {
    if !args.iter().any(|arg| arg == "git") {
        return false;
    }
    match command {
        "apt" | "apt-get" | "yum" | "dnf" | "microdnf" | "zypper" | "pkg" | "brew" => {
            args.iter().any(|arg| arg == "install")
        }
        "apk" => args.iter().any(|arg| arg == "add"),
        "pacman" => args
            .iter()
            .any(|arg| arg == "-S" || arg == "-Sy" || arg == "-Syu"),
        _ => false,
    }
}

/// Hard-gate detection for destructive / remote-execution commands.
///
/// Narrow by design: only irreversibly destructive actions, raw block-device
/// access, fork bombs, piping into a shell, and fetching+executing remote
/// content. "Dangerous but legitimate" commands (`sudo`, reading sensitive
/// files, force-push, …) are intentionally NOT here — they are merely
/// not-known-safe and handled by the approval mode.
///
/// Operates on the token stream so quoted/heredoc text is treated as data, not
/// as a command (e.g. `echo "rm -rf /"` is not a hard-gate hit).
fn blocked_shell_command_reason(command: &str) -> Option<&'static str> {
    if let Some(reason) = blocked_long_running_service_reason(command) {
        return Some(reason);
    }
    let stripped = strip_heredoc_bodies(command);
    // Fork bomb — structural, recognized on the raw (heredoc-stripped) text.
    if stripped.replace(' ', "").contains(":(){:|:&};:") {
        return Some("fork bomb");
    }
    // Fetch-and-execute via command substitution: $(curl …), `wget …`.
    if has_remote_fetch_substitution(&stripped) {
        return Some("remote fetch in command substitution");
    }
    // Walk segments; check each for destructive commands and pipe-to-shell.
    let mut segment: Vec<String> = Vec::new();
    let mut preceded_by_pipe = false;
    let mut segment_has_substitution = false;
    let mut segment_has_heredoc = false;
    for token in shell_syntax_tokens(&stripped) {
        match token {
            ShellSyntaxToken::Word(word) => segment.push(word),
            ShellSyntaxToken::Pipe | ShellSyntaxToken::Segment => {
                if let Some(reason) = destructive_segment_reason(
                    &segment,
                    preceded_by_pipe,
                    segment_has_substitution,
                    segment_has_heredoc,
                ) {
                    return Some(reason);
                }
                segment.clear();
                preceded_by_pipe = matches!(token, ShellSyntaxToken::Pipe);
                segment_has_substitution = false;
                segment_has_heredoc = false;
            }
            // A `<(…)` / `$(…)` argument feeds dynamic content to the segment's
            // command; the body itself is recursed separately in `hard_gate_reason`.
            ShellSyntaxToken::Substitution(_) => segment_has_substitution = true,
            // A heredoc (`sh <<EOF … EOF`) feeds its body to the command as input
            // — for an interpreter, that body IS the program. The body is stripped
            // before tokenizing, so it can't be inspected; treat it like a pipe.
            ShellSyntaxToken::HereDoc => segment_has_heredoc = true,
            ShellSyntaxToken::RedirectIn | ShellSyntaxToken::Expansion => {}
        }
    }
    destructive_segment_reason(
        &segment,
        preceded_by_pipe,
        segment_has_substitution,
        segment_has_heredoc,
    )
}

/// Reason a single command segment is a hard-gate hit, if any.
fn destructive_segment_reason(
    words: &[String],
    preceded_by_pipe: bool,
    has_substitution: bool,
    has_heredoc: bool,
) -> Option<&'static str> {
    let command_index = executable_word_index(words)?;
    let command = command_basename(&words[command_index]);
    let args = &words[command_index + 1..];

    // Raw block-device access (read or write) — never legitimate in workspace.
    if words.iter().any(|word| is_raw_block_device(word)) {
        return Some("raw block device access");
    }
    // Network device redirect (`/dev/tcp/host/port`, `/dev/udp/…`) — a bash-ism
    // for opening sockets, used to exfiltrate or pull a reverse shell.
    if words.iter().any(|word| is_network_device(word)) {
        return Some("network device redirect");
    }
    // A shell interpreter consuming dynamic content — by pipe (`… | sh`), by
    // process/command substitution (`bash <(curl …)`, `sh -c "$(curl …)"`), or by
    // heredoc (`sh <<EOF … EOF`, whose body is the program). Heredoc parity
    // closes the `sh <<EOF … /dev/tcp … EOF` exfil path the body-strip would hide.
    if matches!(command, "sh" | "bash" | "zsh" | "dash")
        && (preceded_by_pipe || has_substitution || has_heredoc)
    {
        return Some("executing dynamic content in a shell");
    }
    // A script interpreter reading its PROGRAM from piped/heredoc'd stdin
    // (`curl … | python3 -`, `wget -O- … | perl`, `node <<EOF`). This is the
    // fetch-and-execute pattern for non-shell interpreters, the analogue of
    // `… | sh`. Only fires when stdin is the program, not mere data — so
    // `data | python3 process.py` and `data | python3 -c "..."` are untouched.
    if (preceded_by_pipe || has_heredoc) && interpreter_reads_stdin_program(command, args) {
        return Some("piping dynamic content into an interpreter");
    }
    // Interpreter inline code that shells out (`python -c "os.system(...)"`,
    // `node -e "require('child_process')…"`). The static design doc lists this as
    // a motivating block case.
    if let Some(reason) = interpreter_inline_shellout_reason(command, args) {
        return Some(reason);
    }

    if command == "mkfs" || command.starts_with("mkfs.") {
        return Some("filesystem creation");
    }
    match command {
        "rm" => destructive_rm(args).then_some("recursive removal of a root path"),
        "chmod" => destructive_chmod(args).then_some("recursive 777 on a root path"),
        _ => None,
    }
}

/// True when `command` is a script interpreter that would read its PROGRAM from
/// stdin given `args` — i.e. no script file and no inline-code flag, or an
/// explicit `-` stdin marker. Used to block `curl … | python3 -` style
/// fetch-and-execute (the non-shell analogue of `… | sh`). A pipeline that
/// merely feeds DATA to a named script (`… | python3 process.py`) or to inline
/// code (`… | python3 -c "..."`) is left alone — stdin there is input, not code.
fn interpreter_reads_stdin_program(command: &str, args: &[String]) -> bool {
    let is_interpreter = matches!(
        command,
        "python" | "python2" | "python3" | "perl" | "ruby" | "node" | "nodejs" | "php"
    );
    if !is_interpreter {
        return false;
    }
    for arg in args {
        let arg = arg.as_str();
        // Explicit stdin marker: `python3 -` reads the program from stdin.
        if arg == "-" {
            return true;
        }
        // Inline-code flags consume the program from an argument, not stdin.
        if matches!(arg, "-c" | "-e" | "-E" | "-r" | "-f") {
            return false;
        }
        // Fused inline-code form (`-cCODE`, `-eCODE`).
        if arg.starts_with("-c") || arg.starts_with("-e") {
            return false;
        }
        // A non-option token is the script file path → program comes from the
        // file, not stdin.
        if !arg.starts_with('-') {
            return false;
        }
        // Otherwise a plain flag (`-u`, `-tt`, …); keep scanning.
    }
    // No script file and no inline-code flag: the interpreter reads stdin.
    true
}

/// Detects an interpreter invoked with inline code (`-c` / `-e` / `-E`) whose
/// code string contains a shell-out primitive. The inline code is in the
/// interpreter's own language, so we look for the well-known escape hatches
/// rather than re-tokenizing it as shell.
fn interpreter_inline_shellout_reason(command: &str, args: &[String]) -> Option<&'static str> {
    let is_interpreter = matches!(
        command,
        "python" | "python2" | "python3" | "perl" | "ruby" | "node" | "nodejs"
    );
    if !is_interpreter {
        return None;
    }
    // Find an inline-code flag and take the following argument as the code.
    let mut iter = args.iter();
    while let Some(arg) = iter.next() {
        let code = if matches!(arg.as_str(), "-c" | "-e" | "-E") {
            iter.next().map(String::as_str)
        } else {
            // `-cCODE` fused form.
            arg.strip_prefix("-c").filter(|rest| !rest.is_empty())
        };
        if code.is_some_and(code_shells_out) {
            return Some("interpreter inline code shells out to a subprocess");
        }
    }
    None
}

/// True when interpreter inline code reaches a subprocess / OS-command primitive.
fn code_shells_out(code: &str) -> bool {
    const SHELLOUT_PRIMITIVES: &[&str] = &[
        "os.system",
        "os.popen",
        "subprocess",
        "popen",         // perl/ruby/python
        "child_process", // node
        "execsync",      // node execSync (lowercased match)
        "system(",       // perl/ruby system(...)
        "`",             // perl/ruby backtick exec, or shell-style in any
        "exec(",
        "eval(",
    ];
    let lower = code.to_ascii_lowercase();
    SHELLOUT_PRIMITIVES
        .iter()
        .any(|primitive| lower.contains(primitive))
}

fn destructive_rm(args: &[String]) -> bool {
    let mut recursive = false;
    let mut root_target = false;
    for arg in args {
        if arg == "--recursive" {
            recursive = true;
        } else if arg.starts_with('-') && !arg.starts_with("--") {
            if arg.contains(['r', 'R']) {
                recursive = true;
            }
        } else if is_root_path_target(arg) {
            root_target = true;
        }
    }
    recursive && root_target
}

/// True when an `rm` target resolves to the filesystem root (or its glob),
/// covering literal and equivalent spellings: `/`, `//`, `/*`, `/.`, `/..`,
/// `/.*`, `~`, `~/`, trailing-slash forms. Variable forms like `$HOME` cannot be
/// resolved statically (the lexer splits them into `Expansion` tokens); those
/// fall through to the approval mode rather than the hard gate, by design.
fn is_root_path_target(arg: &str) -> bool {
    // Home-directory shorthand.
    if arg == "~" || arg == "~/" {
        return true;
    }
    // Collapse repeated slashes, then compare against the root spellings.
    let mut collapsed = String::with_capacity(arg.len());
    let mut prev_slash = false;
    for c in arg.chars() {
        if c == '/' {
            if !prev_slash {
                collapsed.push('/');
            }
            prev_slash = true;
        } else {
            collapsed.push(c);
            prev_slash = false;
        }
    }
    // Drop a single trailing slash (`/foo/` == `/foo`), but keep bare `/`.
    let normalized = match collapsed.strip_suffix('/') {
        Some("") => "/",
        Some(rest) => rest,
        None => &collapsed,
    };
    matches!(normalized, "/" | "/*" | "/." | "/.." | "/.*")
}

fn destructive_chmod(args: &[String]) -> bool {
    let mut recursive = false;
    let mut mode_777 = false;
    let mut root_target = false;
    for arg in args {
        if arg == "-R" || arg == "-r" || arg == "--recursive" {
            recursive = true;
        } else if arg == "777" || arg == "0777" {
            mode_777 = true;
        } else if arg == "/" {
            root_target = true;
        }
    }
    recursive && mode_777 && root_target
}

fn is_raw_block_device(word: &str) -> bool {
    // Strip a leading redirect marker like `>` or `>>` if fused to the path.
    let path = word.trim_start_matches('>');
    [
        "/dev/sd",
        "/dev/hd",
        "/dev/nvme",
        "/dev/disk",
        "/dev/mapper/",
    ]
    .iter()
    .any(|prefix| path.starts_with(prefix))
}

/// Bash pseudo-device for opening a TCP/UDP socket (`/dev/tcp/host/port`,
/// `/dev/udp/host/port`) — used to exfiltrate data or pull a reverse shell.
/// Network exfiltration, not a block device, so it is detected separately.
fn is_network_device(word: &str) -> bool {
    let path = word.trim_start_matches(['>', '<']);
    path.starts_with("/dev/tcp/") || path.starts_with("/dev/udp/")
}

fn has_remote_fetch_substitution(command: &str) -> bool {
    let lower = command.to_ascii_lowercase();
    lower.contains("$(curl")
        || lower.contains("$(wget")
        || (lower.contains('`') && (lower.contains("curl") || lower.contains("wget")))
}

fn blocked_long_running_service_reason(command: &str) -> Option<&'static str> {
    let command = strip_heredoc_bodies(command);
    let mut segment = Vec::new();
    for token in shell_syntax_tokens(&command) {
        match token {
            ShellSyntaxToken::Word(word) => segment.push(word),
            ShellSyntaxToken::Pipe | ShellSyntaxToken::Segment => {
                if segment_starts_long_running_service(&segment) {
                    return Some(LONG_RUNNING_SERVICE_REASON);
                }
                segment.clear();
            }
            ShellSyntaxToken::RedirectIn
            | ShellSyntaxToken::HereDoc
            | ShellSyntaxToken::Substitution(_)
            | ShellSyntaxToken::Expansion => {}
        }
    }
    if segment_starts_long_running_service(&segment) {
        return Some(LONG_RUNNING_SERVICE_REASON);
    }
    None
}

fn segment_starts_long_running_service(words: &[String]) -> bool {
    let Some(command_index) = executable_word_index(words) else {
        return false;
    };
    let command = command_basename(&words[command_index]);
    let args = &words[command_index + 1..];
    match command {
        "python" | "python2" | "python3" => {
            args_have_module(args, "http.server") || args_have_module(args, "simplehttpserver")
        }
        "busybox" => args
            .first()
            .is_some_and(|arg| arg.eq_ignore_ascii_case("httpd")),
        "php" => args.iter().any(|arg| arg == "-S" || arg == "-s"),
        "npx" => args.iter().any(|arg| {
            matches!(
                command_basename(arg),
                "vite" | "serve" | "next" | "astro" | "http-server"
            )
        }),
        "vite" => args.iter().any(|arg| arg == "--host"),
        "npm" => args.len() >= 2 && args[0].eq_ignore_ascii_case("run") && is_dev_script(&args[1]),
        "pnpm" | "yarn" => {
            args.first().is_some_and(|arg| is_dev_script(arg))
                || (args.len() >= 2
                    && args[0].eq_ignore_ascii_case("run")
                    && is_dev_script(&args[1]))
        }
        "next" | "astro" => args
            .first()
            .is_some_and(|arg| arg.eq_ignore_ascii_case("dev")),
        "serve" | "http-server" => true,
        _ => false,
    }
}

fn executable_word_index(words: &[String]) -> Option<usize> {
    let mut index = 0;
    while index < words.len() {
        let word = words[index].as_str();
        let lower = word.to_ascii_lowercase();
        if is_shell_assignment_prefix(word) || lower == "command" || lower == "env" {
            index += 1;
            continue;
        }
        if lower == "timeout" {
            index += 1;
            while index < words.len() && words[index].starts_with('-') {
                index += 1;
            }
            if index < words.len() {
                index += 1;
            }
            continue;
        }
        return Some(index);
    }
    None
}

fn args_have_module(args: &[String], module: &str) -> bool {
    args.windows(2)
        .any(|pair| pair[0] == "-m" && pair[1].eq_ignore_ascii_case(module))
}

fn is_dev_script(value: &str) -> bool {
    matches!(
        value.to_ascii_lowercase().as_str(),
        "dev" | "start" | "serve" | "preview"
    )
}

const LONG_RUNNING_SERVICE_REASON: &str = "long-running local service is not supported in foreground shell; do not start a server to preview local HTML. Use generated file attachment or a future local preview tool.";
