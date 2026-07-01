//! Apply parsed apply_patch commands against the sandboxed filesystem.

use std::fs;
use std::path::Path;

use crate::file_tools::FileToolExecutionResult;
use crate::storage::FileBridge;
use crate::tool_loop::InternalToolProgressSender;

use super::super::paths::{existing_regular_file, resolve_write_path};
use super::super::progress::{
    PatchApplyResult, build_patch_result, count_lines, emit_patch_progress,
};
use super::errors::PatchError;
use super::parser::{Command, Hunk, HunkLine, parse};
use super::seek::seek_sequence;

/// Maximum bytes any single file may grow to via an apply_patch command.
pub(super) const MAX_WRITE_BYTES: usize = 1024 * 1024;

/// Entry point invoked by the file tool dispatcher.
pub(super) fn execute(
    bridge: &FileBridge,
    patch: &str,
    create_parent_dirs: bool,
    progress: Option<InternalToolProgressSender>,
) -> Result<FileToolExecutionResult, PatchError> {
    let commands = parse(patch)?;
    ensure_unique_paths(&commands)?;

    let mut results = Vec::with_capacity(commands.len());
    for command in commands {
        let result = apply_command(bridge, command, create_parent_dirs)?;
        emit_patch_progress(progress.as_ref(), &result);
        results.push(result);
    }

    let files: Vec<_> = results.iter().map(|r| r.to_json()).collect();
    Ok(FileToolExecutionResult {
        output: serde_json::json!({
            "status": "patched",
            "file_count": files.len(),
            "files": files,
        })
        .to_string(),
    })
}

fn ensure_unique_paths(commands: &[Command]) -> Result<(), PatchError> {
    use std::collections::HashMap;

    // Allow the codex-style "rewrite" pattern: Delete File followed by Add
    // File for the same path. Anything else that touches the same path twice
    // is rejected.
    let mut seen: HashMap<String, &'static str> = HashMap::new();
    for command in commands {
        let path = command.path().to_string();
        let kind = match command {
            Command::Add { .. } => "add",
            Command::Delete { .. } => "delete",
            Command::Update { .. } => "update",
        };
        match seen.get(path.as_str()).copied() {
            None => {
                seen.insert(path, kind);
            }
            Some(prev) if prev == "delete" && kind == "add" => {
                seen.insert(path, "rewrite");
            }
            _ => return Err(PatchError::DuplicatePath { path }),
        }
    }
    Ok(())
}

fn apply_command(
    bridge: &FileBridge,
    command: Command,
    create_parent_dirs: bool,
) -> Result<PatchApplyResult, PatchError> {
    match command {
        Command::Add { path, lines, .. } => add_file(bridge, &path, lines, create_parent_dirs),
        Command::Delete { path, .. } => delete_file(bridge, &path),
        Command::Update { path, hunks, .. } => update_file(bridge, &path, hunks),
    }
}

fn add_file(
    bridge: &FileBridge,
    sandbox_path: &str,
    lines: Vec<String>,
    create_parent_dirs: bool,
) -> Result<PatchApplyResult, PatchError> {
    let (real_path, base_dir) = resolve_path(bridge, sandbox_path)?;
    let existing = existing_regular_file_text(&real_path, &base_dir, sandbox_path)?;
    if existing.is_some() {
        return Err(PatchError::AddFileExists {
            path: sandbox_path.to_string(),
        });
    }
    let line_count = lines.len();
    let content = join_lines(lines);
    enforce_size_limit(sandbox_path, content.len())?;
    if let Some(parent) = real_path.parent() {
        ensure_parent(parent, sandbox_path, create_parent_dirs)?;
    }
    fs::write(&real_path, content.as_bytes()).map_err(|error| PatchError::Io {
        path: sandbox_path.to_string(),
        source: error.to_string(),
    })?;
    build_result(
        bridge,
        &real_path,
        sandbox_path,
        "added",
        &content,
        line_count,
        0,
    )
}

fn delete_file(bridge: &FileBridge, sandbox_path: &str) -> Result<PatchApplyResult, PatchError> {
    let (real_path, base_dir) = resolve_path(bridge, sandbox_path)?;
    existing_regular_file_text(&real_path, &base_dir, sandbox_path)?.ok_or_else(|| {
        PatchError::DeleteFileMissing {
            path: sandbox_path.to_string(),
        }
    })?;
    fs::remove_file(&real_path).map_err(|error| PatchError::Io {
        path: sandbox_path.to_string(),
        source: error.to_string(),
    })?;
    Ok(PatchApplyResult {
        action: "deleted",
        path: sandbox_path.to_string(),
        real_path: real_path.display().to_string(),
        size_bytes: 0,
        line_count: 0,
        added_lines: 0,
        removed_lines: 0,
    })
}

fn update_file(
    bridge: &FileBridge,
    sandbox_path: &str,
    hunks: Vec<Hunk>,
) -> Result<PatchApplyResult, PatchError> {
    let (real_path, base_dir) = resolve_path(bridge, sandbox_path)?;
    let existing =
        existing_regular_file_text(&real_path, &base_dir, sandbox_path)?.ok_or_else(|| {
            PatchError::UpdateFileMissing {
                path: sandbox_path.to_string(),
            }
        })?;
    let next_content = apply_hunks(&existing, &hunks, sandbox_path)?;
    let summary = summarize(&hunks);
    if summary.added_lines == 0 && summary.removed_lines == 0 {
        return Err(PatchError::UpdateFileNoChanges {
            path: sandbox_path.to_string(),
        });
    }
    enforce_size_limit(sandbox_path, next_content.len())?;
    fs::write(&real_path, next_content.as_bytes()).map_err(|error| PatchError::Io {
        path: sandbox_path.to_string(),
        source: error.to_string(),
    })?;
    build_result(
        bridge,
        &real_path,
        sandbox_path,
        "updated",
        &next_content,
        summary.added_lines,
        summary.removed_lines,
    )
}

/// Apply hunks in document order. We split the file into newline-preserving
/// segments so that we can match patterns line-by-line via [`seek_sequence`]
/// (codex-style fuzzy match) and then splice in the new content while keeping
/// the original line endings of the surrounding context.
fn apply_hunks(existing: &str, hunks: &[Hunk], sandbox_path: &str) -> Result<String, PatchError> {
    if existing.is_empty() {
        return Err(PatchError::UpdateFileEmpty {
            path: sandbox_path.to_string(),
        });
    }
    let trailing_newline = existing.ends_with('\n');
    let mut file_lines: Vec<String> = existing.lines().map(str::to_string).collect();
    let mut search_from = 0usize;

    for hunk in hunks {
        let pattern = pattern_lines(&hunk.lines);
        let replacement = replacement_lines(&hunk.lines);
        let occurrences = count_matches(&file_lines, &pattern, search_from);

        let location = if pattern.is_empty() {
            // Hunks that are purely additions need an explicit anchor; we
            // require the model to provide at least one context line.
            return Err(PatchError::HunkContextNotFound {
                path: sandbox_path.to_string(),
                hunk_line: hunk.start_line,
                pattern_excerpt: replacement_excerpt(&replacement),
            });
        } else {
            seek_sequence(&file_lines, &pattern, search_from, hunk.anchored_to_eof).ok_or_else(
                || PatchError::HunkContextNotFound {
                    path: sandbox_path.to_string(),
                    hunk_line: hunk.start_line,
                    pattern_excerpt: pattern_excerpt(&pattern),
                },
            )?
        };

        if occurrences > 1 {
            // Only escalate to ambiguity when the *exact* pattern matches
            // multiple times. Fuzzy fallbacks (trim/normalise) implicitly
            // prefer the earliest match.
            return Err(PatchError::HunkContextAmbiguous {
                path: sandbox_path.to_string(),
                hunk_line: hunk.start_line,
                matches: occurrences,
            });
        }

        let end = location + pattern.len();
        file_lines.splice(location..end, replacement.iter().cloned());
        search_from = location + replacement.len();
    }

    let mut joined = file_lines.join("\n");
    if trailing_newline {
        joined.push('\n');
    }
    Ok(joined)
}

fn pattern_lines(lines: &[HunkLine]) -> Vec<String> {
    lines
        .iter()
        .filter_map(|line| match line {
            HunkLine::Context(text) | HunkLine::Remove(text) => Some(text.clone()),
            HunkLine::Add(_) => None,
        })
        .collect()
}

fn replacement_lines(lines: &[HunkLine]) -> Vec<String> {
    lines
        .iter()
        .filter_map(|line| match line {
            HunkLine::Context(text) | HunkLine::Add(text) => Some(text.clone()),
            HunkLine::Remove(_) => None,
        })
        .collect()
}

fn count_matches(lines: &[String], pattern: &[String], from: usize) -> usize {
    if pattern.is_empty() || pattern.len() > lines.len() {
        return 0;
    }
    let last = lines.len().saturating_sub(pattern.len());
    let mut count = 0;
    let mut i = from;
    while i <= last {
        if lines[i..i + pattern.len()] == *pattern {
            count += 1;
            i += pattern.len();
        } else {
            i += 1;
        }
    }
    count
}

fn pattern_excerpt(pattern: &[String]) -> Vec<String> {
    pattern.iter().take(3).cloned().collect()
}

fn replacement_excerpt(replacement: &[String]) -> Vec<String> {
    replacement.iter().take(3).cloned().collect()
}

struct DiffSummary {
    added_lines: usize,
    removed_lines: usize,
}

fn summarize(hunks: &[Hunk]) -> DiffSummary {
    let mut added = 0;
    let mut removed = 0;
    for hunk in hunks {
        for line in &hunk.lines {
            match line {
                HunkLine::Add(_) => added += 1,
                HunkLine::Remove(_) => removed += 1,
                HunkLine::Context(_) => {}
            }
        }
    }
    DiffSummary {
        added_lines: added,
        removed_lines: removed,
    }
}

fn join_lines(lines: Vec<String>) -> String {
    if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")
    }
}

fn enforce_size_limit(path: &str, size: usize) -> Result<(), PatchError> {
    if size > MAX_WRITE_BYTES {
        return Err(PatchError::TooLarge {
            path: path.to_string(),
            max_bytes: MAX_WRITE_BYTES,
        });
    }
    Ok(())
}

fn ensure_parent(parent: &Path, sandbox_path: &str, create: bool) -> Result<(), PatchError> {
    if parent.as_os_str().is_empty() {
        return Ok(());
    }
    if create {
        fs::create_dir_all(parent).map_err(|error| PatchError::Io {
            path: sandbox_path.to_string(),
            source: error.to_string(),
        })
    } else if parent.exists() {
        Ok(())
    } else {
        Err(PatchError::Io {
            path: sandbox_path.to_string(),
            source: format!("parent directory does not exist: {}", parent.display()),
        })
    }
}

fn resolve_path(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<(std::path::PathBuf, std::path::PathBuf), PatchError> {
    resolve_write_path(bridge, sandbox_path).map_err(|reason| PatchError::InvalidPath {
        path: sandbox_path.to_string(),
        reason,
    })
}

fn existing_regular_file_text(
    real_path: &Path,
    base_dir: &Path,
    sandbox_path: &str,
) -> Result<Option<String>, PatchError> {
    existing_regular_file(real_path, base_dir, sandbox_path).map_err(|reason| PatchError::Io {
        path: sandbox_path.to_string(),
        source: reason,
    })
}

fn build_result(
    bridge: &FileBridge,
    real_path: &Path,
    sandbox_path: &str,
    action: &'static str,
    content: &str,
    added_lines: usize,
    removed_lines: usize,
) -> Result<PatchApplyResult, PatchError> {
    let _ = count_lines; // silence "unused import" if helper rotates
    build_patch_result(
        bridge,
        real_path,
        sandbox_path,
        action,
        content,
        added_lines,
        removed_lines,
    )
    .map_err(|reason| PatchError::Io {
        path: sandbox_path.to_string(),
        source: reason,
    })
}
