//! Typed errors produced while parsing or applying an apply_patch envelope.
//!
//! Each variant carries enough context for the LLM to repair its next call:
//! - a stable `error_kind` discriminator,
//! - the offending hunk/header line number when known,
//! - a short pattern excerpt for context-not-found failures.

use serde_json::json;

#[derive(Debug, Clone, PartialEq)]
pub(super) enum PatchError {
    EnvelopeMissingBegin,
    EnvelopeMissingEnd,
    EnvelopeEmpty,
    UnknownHeader {
        line: usize,
        header: String,
    },
    AddFileInvalidLine {
        line: usize,
        text: String,
    },
    UpdateFileMissingHunks {
        path: String,
    },
    UpdateFileNoChanges {
        path: String,
    },
    UpdateFileMissing {
        path: String,
    },
    UpdateFileEmpty {
        path: String,
    },
    AddFileExists {
        path: String,
    },
    DeleteFileMissing {
        path: String,
    },
    DuplicatePath {
        path: String,
    },
    HunkContextNotFound {
        path: String,
        hunk_line: usize,
        pattern_excerpt: Vec<String>,
    },
    HunkContextAmbiguous {
        path: String,
        hunk_line: usize,
        matches: usize,
    },
    InvalidPath {
        path: String,
        reason: String,
    },
    TooLarge {
        path: String,
        max_bytes: usize,
    },
    Io {
        path: String,
        source: String,
    },
}

impl PatchError {
    fn kind(&self) -> &'static str {
        match self {
            PatchError::EnvelopeMissingBegin => "envelope_missing_begin",
            PatchError::EnvelopeMissingEnd => "envelope_missing_end",
            PatchError::EnvelopeEmpty => "envelope_empty",
            PatchError::UnknownHeader { .. } => "unknown_header",
            PatchError::AddFileInvalidLine { .. } => "add_file_invalid_line",
            PatchError::UpdateFileMissingHunks { .. } => "update_file_missing_hunks",
            PatchError::UpdateFileNoChanges { .. } => "update_file_no_changes",
            PatchError::UpdateFileMissing { .. } => "update_file_missing",
            PatchError::UpdateFileEmpty { .. } => "update_file_empty",
            PatchError::AddFileExists { .. } => "add_file_exists",
            PatchError::DeleteFileMissing { .. } => "delete_file_missing",
            PatchError::DuplicatePath { .. } => "duplicate_path",
            PatchError::HunkContextNotFound { .. } => "hunk_context_not_found",
            PatchError::HunkContextAmbiguous { .. } => "hunk_context_ambiguous",
            PatchError::InvalidPath { .. } => "invalid_path",
            PatchError::TooLarge { .. } => "too_large",
            PatchError::Io { .. } => "io",
        }
    }

    fn message(&self) -> String {
        match self {
            PatchError::EnvelopeMissingBegin => {
                "apply_patch must start with '*** Begin Patch'".to_string()
            }
            PatchError::EnvelopeMissingEnd => {
                "apply_patch must end with '*** End Patch'".to_string()
            }
            PatchError::EnvelopeEmpty => "apply_patch envelope has no file commands".to_string(),
            PatchError::UnknownHeader { line, header } => {
                format!("unknown patch header at line {line}: {header}")
            }
            PatchError::AddFileInvalidLine { line, text } => {
                format!("*** Add File body at line {line} must start with '+': {text}")
            }
            PatchError::UpdateFileMissingHunks { path } => {
                format!("*** Update File {path} requires at least one hunk")
            }
            PatchError::UpdateFileNoChanges { path } => {
                format!("*** Update File {path} produced no additions or removals")
            }
            PatchError::UpdateFileMissing { path } => {
                format!("*** Update File requires an existing file: {path}")
            }
            PatchError::UpdateFileEmpty { path } => {
                format!("*** Update File cannot patch an empty file: {path}")
            }
            PatchError::AddFileExists { path } => format!(
                "*** Add File refused because file exists: {path} (use Update File or Delete File first)"
            ),
            PatchError::DeleteFileMissing { path } => {
                format!("*** Delete File requires an existing file: {path}")
            }
            PatchError::DuplicatePath { path } => {
                format!("patch edits the same file more than once: {path}")
            }
            PatchError::HunkContextNotFound {
                path, hunk_line, ..
            } => format!(
                "hunk at line {hunk_line} did not match any location in {path}; provide more context lines"
            ),
            PatchError::HunkContextAmbiguous {
                path,
                hunk_line,
                matches,
            } => format!(
                "hunk at line {hunk_line} matched {matches} locations in {path}; add more context lines"
            ),
            PatchError::InvalidPath { path, reason } => {
                format!("invalid sandbox path {path}: {reason}")
            }
            PatchError::TooLarge { path, max_bytes } => {
                format!("file {path} would exceed the {max_bytes}-byte write limit")
            }
            PatchError::Io { path, source } => format!("io error on {path}: {source}"),
        }
    }

    fn hint(&self) -> Option<String> {
        match self {
            PatchError::EnvelopeMissingBegin | PatchError::EnvelopeMissingEnd => {
                Some("wrap the patch in '*** Begin Patch' and '*** End Patch' markers".to_string())
            }
            PatchError::AddFileExists { .. } => Some(
                "rewrite the existing file via '*** Update File:' (or delete it first)".to_string(),
            ),
            PatchError::UpdateFileMissing { .. } => {
                Some("use '*** Add File:' for new files".to_string())
            }
            PatchError::DuplicatePath { .. } => {
                Some("combine the edits for that file into a single hunk block".to_string())
            }
            PatchError::HunkContextNotFound { .. } | PatchError::HunkContextAmbiguous { .. } => {
                Some(
                    "include a few unchanged lines immediately above and below the change"
                        .to_string(),
                )
            }
            _ => None,
        }
    }

    /// A small corrected envelope the model can adapt verbatim. Only set for
    /// the error kinds where format guidance is the actual issue (envelope
    /// shape, missing prefix, wrong action, etc.). Errors that require model
    /// reasoning about the file contents (ambiguous context, missing context)
    /// intentionally do not produce an example_fix.
    fn example_fix(&self) -> Option<String> {
        match self {
            PatchError::EnvelopeMissingBegin | PatchError::EnvelopeMissingEnd => Some(
                "*** Begin Patch\n*** Update File: /workspace/example.txt\n@@\n old line\n-remove me\n+add me\n keep me\n*** End Patch"
                    .to_string(),
            ),
            PatchError::EnvelopeEmpty => Some(
                "*** Begin Patch\n*** Add File: /workspace/new.txt\n+first line\n+second line\n*** End Patch"
                    .to_string(),
            ),
            PatchError::AddFileInvalidLine { .. } => Some(
                "*** Begin Patch\n*** Add File: /workspace/new.txt\n+first line\n+second line\n*** End Patch (prefix every body line with '+')"
                    .to_string(),
            ),
            PatchError::UnknownHeader { .. } => Some(
                "Inside an Update File hunk, every line must start with ' ' (context), '+' (add), or '-' (remove). Headers like '--- a/file' or '+++ b/file' are NOT supported — that is unified-diff format."
                    .to_string(),
            ),
            PatchError::AddFileExists { path } => Some(format!(
                "*** Begin Patch\n*** Update File: {path}\n@@\n unchanged context\n-old\n+new\n unchanged context\n*** End Patch"
            )),
            PatchError::UpdateFileMissing { path } => Some(format!(
                "*** Begin Patch\n*** Add File: {path}\n+first line\n+second line\n*** End Patch"
            )),
            PatchError::UpdateFileMissingHunks { path } | PatchError::UpdateFileNoChanges { path } => {
                Some(format!(
                    "*** Begin Patch\n*** Update File: {path}\n@@\n unchanged context\n-old line\n+new line\n unchanged context\n*** End Patch"
                ))
            }
            PatchError::DuplicatePath { path } => Some(format!(
                "*** Begin Patch\n*** Update File: {path}\n@@\n first change context\n-old A\n+new A\n@@\n second change context\n-old B\n+new B\n*** End Patch (combine into one Update File with multiple @@ hunks)"
            )),
            PatchError::InvalidPath { .. } => Some(
                "paths must be absolute sandbox paths starting with /workspace, /tmp, /home, /var, /etc, /opt, /srv, /run, /usr, or /root. /skills is read-only.".to_string(),
            ),
            _ => None,
        }
    }

    /// Render this error to the JSON envelope returned by the tool execution
    /// layer. Always sets `error`, `error_kind`; conditionally attaches
    /// `path`, `hunk_line`, `pattern_excerpt`, `hint`, `example_fix`, etc.
    pub(super) fn to_tool_payload(&self) -> String {
        let mut value = json!({
            "status": "error",
            "error": self.message(),
            "error_kind": self.kind(),
        });
        let map = value.as_object_mut().expect("object literal");
        if let Some(path) = self.path() {
            map.insert("path".to_string(), json!(path));
        }
        if let Some(line) = self.line() {
            map.insert("line".to_string(), json!(line));
        }
        if let PatchError::HunkContextNotFound {
            pattern_excerpt, ..
        } = self
        {
            map.insert("pattern_excerpt".to_string(), json!(pattern_excerpt));
        }
        if let PatchError::HunkContextAmbiguous { matches, .. } = self {
            map.insert("matches".to_string(), json!(matches));
        }
        if let Some(hint) = self.hint() {
            map.insert("hint".to_string(), json!(hint));
        }
        if let Some(example) = self.example_fix() {
            map.insert("example_fix".to_string(), json!(example));
        }
        value.to_string()
    }

    fn path(&self) -> Option<&str> {
        match self {
            PatchError::AddFileExists { path }
            | PatchError::DeleteFileMissing { path }
            | PatchError::UpdateFileMissing { path }
            | PatchError::UpdateFileMissingHunks { path }
            | PatchError::UpdateFileNoChanges { path }
            | PatchError::UpdateFileEmpty { path }
            | PatchError::DuplicatePath { path }
            | PatchError::HunkContextNotFound { path, .. }
            | PatchError::HunkContextAmbiguous { path, .. }
            | PatchError::InvalidPath { path, .. }
            | PatchError::TooLarge { path, .. }
            | PatchError::Io { path, .. } => Some(path.as_str()),
            _ => None,
        }
    }

    fn line(&self) -> Option<usize> {
        match self {
            PatchError::UnknownHeader { line, .. }
            | PatchError::AddFileInvalidLine { line, .. } => Some(*line),
            PatchError::HunkContextNotFound { hunk_line, .. }
            | PatchError::HunkContextAmbiguous { hunk_line, .. } => Some(*hunk_line),
            _ => None,
        }
    }
}
