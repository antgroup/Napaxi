//! Parse an apply_patch envelope into structured commands.
//!
//! Grammar (codex-compatible, napaxi subset — `Move to:` and `Environment ID:`
//! are intentionally not yet supported):
//!
//! ```text
//! patch        := "*** Begin Patch" LF command+ "*** End Patch" LF?
//! command      := add | delete | update
//! add          := "*** Add File: " filename LF ("+" rest LF)+
//! delete       := "*** Delete File: " filename LF
//! update       := "*** Update File: " filename LF hunk+
//! hunk         := ("@@" | "@@ " context)? LF change_line+ ("*** End of File" LF)?
//! change_line  := (" " | "+" | "-") rest LF
//! ```
//!
//! Returned [`HunkLine`] entries carry the 1-based source line numbers so that
//! errors raised later can point the model at the right place.

use super::errors::PatchError;

#[derive(Debug, PartialEq)]
pub(super) enum Command {
    Add {
        path: String,
        /// 1-based source line where `*** Add File:` appears.
        header_line: usize,
        lines: Vec<String>,
    },
    Delete {
        path: String,
        header_line: usize,
    },
    Update {
        path: String,
        header_line: usize,
        hunks: Vec<Hunk>,
    },
}

impl Command {
    pub(super) fn path(&self) -> &str {
        match self {
            Command::Add { path, .. }
            | Command::Delete { path, .. }
            | Command::Update { path, .. } => path,
        }
    }
}

#[derive(Debug, PartialEq)]
pub(super) struct Hunk {
    /// 1-based source line where this hunk starts (the `@@` marker, or the
    /// first change line when no marker is present).
    pub(super) start_line: usize,
    /// `true` when the hunk is terminated by `*** End of File`.
    pub(super) anchored_to_eof: bool,
    pub(super) lines: Vec<HunkLine>,
}

#[derive(Debug, PartialEq)]
pub(super) enum HunkLine {
    Context(String),
    Add(String),
    Remove(String),
}

const BEGIN: &str = "*** Begin Patch";
const END: &str = "*** End Patch";
const ADD_FILE: &str = "*** Add File: ";
const DELETE_FILE: &str = "*** Delete File: ";
const UPDATE_FILE: &str = "*** Update File: ";
const END_OF_FILE: &str = "*** End of File";

pub(super) fn parse(input: &str) -> Result<Vec<Command>, PatchError> {
    let raw_lines: Vec<&str> = input.lines().collect();
    // Find the begin marker (allow blank lines before it).
    let begin_idx = raw_lines
        .iter()
        .position(|line| line.trim() == BEGIN)
        .ok_or(PatchError::EnvelopeMissingBegin)?;
    let end_idx = raw_lines
        .iter()
        .rposition(|line| line.trim() == END)
        .ok_or(PatchError::EnvelopeMissingEnd)?;
    if end_idx <= begin_idx {
        return Err(PatchError::EnvelopeMissingEnd);
    }

    let mut commands = Vec::new();
    let mut i = begin_idx + 1;
    while i < end_idx {
        let line = raw_lines[i];
        if line.trim().is_empty() {
            i += 1;
            continue;
        }
        let line_no = i + 1; // 1-based
        if let Some(path) = line.strip_prefix(ADD_FILE) {
            let path = path.trim().to_string();
            i += 1;
            let mut body = Vec::new();
            while i < end_idx && !(raw_lines[i].starts_with("*** ") && raw_lines[i] != END_OF_FILE)
            {
                let inner = raw_lines[i];
                if inner.is_empty() {
                    body.push(String::new());
                    i += 1;
                    continue;
                }
                let added =
                    inner
                        .strip_prefix('+')
                        .ok_or_else(|| PatchError::AddFileInvalidLine {
                            line: i + 1,
                            text: inner.to_string(),
                        })?;
                body.push(added.to_string());
                i += 1;
            }
            commands.push(Command::Add {
                path,
                header_line: line_no,
                lines: body,
            });
            continue;
        }
        if let Some(path) = line.strip_prefix(DELETE_FILE) {
            commands.push(Command::Delete {
                path: path.trim().to_string(),
                header_line: line_no,
            });
            i += 1;
            continue;
        }
        if let Some(path) = line.strip_prefix(UPDATE_FILE) {
            let path = path.trim().to_string();
            i += 1;
            let mut hunks: Vec<Hunk> = Vec::new();
            let mut current_lines: Vec<HunkLine> = Vec::new();
            let mut current_start = i + 1;
            let mut current_eof = false;
            let mut had_marker = false;

            let flush = |hunks: &mut Vec<Hunk>,
                         current_lines: &mut Vec<HunkLine>,
                         current_start: &mut usize,
                         current_eof: &mut bool| {
                if !current_lines.is_empty() {
                    hunks.push(Hunk {
                        start_line: *current_start,
                        anchored_to_eof: *current_eof,
                        lines: std::mem::take(current_lines),
                    });
                    *current_eof = false;
                }
            };

            while i < end_idx && !(raw_lines[i].starts_with("*** ") && raw_lines[i] != END_OF_FILE)
            {
                let inner = raw_lines[i];
                if inner == "@@" || inner.starts_with("@@ ") {
                    flush(
                        &mut hunks,
                        &mut current_lines,
                        &mut current_start,
                        &mut current_eof,
                    );
                    current_start = i + 1;
                    had_marker = true;
                    i += 1;
                    continue;
                }
                if inner == END_OF_FILE {
                    current_eof = true;
                    i += 1;
                    continue;
                }
                if inner.is_empty() {
                    // Treat a bare blank line as a context line for an empty
                    // source line, matching codex behaviour for empty lines.
                    current_lines.push(HunkLine::Context(String::new()));
                    i += 1;
                    continue;
                }
                let (prefix, rest) = inner.split_at(1);
                let entry = match prefix {
                    " " => HunkLine::Context(rest.to_string()),
                    "+" => HunkLine::Add(rest.to_string()),
                    "-" => HunkLine::Remove(rest.to_string()),
                    _ => {
                        return Err(PatchError::UnknownHeader {
                            line: i + 1,
                            header: inner.to_string(),
                        });
                    }
                };
                current_lines.push(entry);
                if !had_marker {
                    // Anchor the implicit hunk to the first line we saw.
                    current_start = current_start.min(i + 1);
                }
                i += 1;
            }
            flush(
                &mut hunks,
                &mut current_lines,
                &mut current_start,
                &mut current_eof,
            );

            if hunks.is_empty() {
                return Err(PatchError::UpdateFileMissingHunks { path });
            }
            commands.push(Command::Update {
                path,
                header_line: line_no,
                hunks,
            });
            continue;
        }
        return Err(PatchError::UnknownHeader {
            line: line_no,
            header: line.to_string(),
        });
    }

    if commands.is_empty() {
        return Err(PatchError::EnvelopeEmpty);
    }
    Ok(commands)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_add_file() {
        let cmds =
            parse("*** Begin Patch\n*** Add File: /workspace/a.md\n+hi\n+there\n*** End Patch")
                .unwrap();
        assert_eq!(cmds.len(), 1);
        match &cmds[0] {
            Command::Add { path, lines, .. } => {
                assert_eq!(path, "/workspace/a.md");
                assert_eq!(lines, &vec!["hi".to_string(), "there".to_string()]);
            }
            other => panic!("expected Add, got {other:?}"),
        }
    }

    #[test]
    fn parses_delete_file() {
        let cmds =
            parse("*** Begin Patch\n*** Delete File: /workspace/a.md\n*** End Patch").unwrap();
        assert!(matches!(&cmds[0], Command::Delete { path, .. } if path == "/workspace/a.md"));
    }

    #[test]
    fn parses_update_with_multiple_hunks_and_eof() {
        let patch = "*** Begin Patch\n\
                     *** Update File: /workspace/a.md\n\
                     @@\n alpha\n-beta\n+bravo\n@@ ctx\n-gone\n+kept\n*** End of File\n\
                     *** End Patch";
        let cmds = parse(patch).unwrap();
        match &cmds[0] {
            Command::Update { hunks, .. } => {
                assert_eq!(hunks.len(), 2);
                assert!(hunks[1].anchored_to_eof);
                assert!(matches!(hunks[0].lines[0], HunkLine::Context(ref s) if s == "alpha"));
                assert!(matches!(hunks[0].lines[1], HunkLine::Remove(ref s) if s == "beta"));
                assert!(matches!(hunks[0].lines[2], HunkLine::Add(ref s) if s == "bravo"));
            }
            other => panic!("expected Update, got {other:?}"),
        }
    }

    #[test]
    fn missing_begin_envelope_is_typed_error() {
        let err =
            parse("*** Update File: /workspace/a.md\n@@\n-foo\n+bar\n*** End Patch").unwrap_err();
        assert!(matches!(err, PatchError::EnvelopeMissingBegin));
    }

    #[test]
    fn add_file_without_plus_prefix_reports_line() {
        let err = parse("*** Begin Patch\n*** Add File: /workspace/a.md\nbad line\n*** End Patch")
            .unwrap_err();
        match err {
            PatchError::AddFileInvalidLine { line, .. } => assert_eq!(line, 3),
            other => panic!("expected AddFileInvalidLine, got {other:?}"),
        }
    }

    #[test]
    fn unknown_change_prefix_reports_line() {
        let err =
            parse("*** Begin Patch\n*** Update File: /workspace/a.md\n@@\n?invalid\n*** End Patch")
                .unwrap_err();
        match err {
            PatchError::UnknownHeader { line, .. } => assert_eq!(line, 4),
            other => panic!("expected UnknownHeader, got {other:?}"),
        }
    }

    #[test]
    fn empty_envelope_is_typed_error() {
        let err = parse("*** Begin Patch\n*** End Patch").unwrap_err();
        assert!(matches!(err, PatchError::EnvelopeEmpty));
    }
}
