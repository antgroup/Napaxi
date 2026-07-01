//! Tool descriptor JSON schemas for `read_file` and `apply_patch`.

use crate::tool_registry::{ToolDescriptor, ToolEffect};

pub use super::apply_patch::APPLY_PATCH_TOOL_NAME;

pub const READ_FILE_TOOL_NAME: &str = "read_file";

pub(super) const MAX_MAX_BYTES: usize = 512 * 1024;

pub fn descriptors() -> Vec<ToolDescriptor> {
    vec![read_file_descriptor(), apply_patch_descriptor()]
}

pub fn is_file_tool(name: &str) -> bool {
    matches!(name, READ_FILE_TOOL_NAME | APPLY_PATCH_TOOL_NAME)
}

pub fn read_file_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: READ_FILE_TOOL_NAME.to_string(),
        description: "Read a file from the mobile sandbox. Use /workspace for persistent files, /skills for installed skill files, or Linux rootfs paths such as /tmp, /home, or /etc.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Sandbox file path to read, such as /workspace/notes.md or /tmp/output.txt."
                },
                "max_bytes": {
                    "type": "integer",
                    "description": "Maximum bytes to read. Defaults to 65536, maximum 524288.",
                    "minimum": 1,
                    "maximum": MAX_MAX_BYTES
                }
            },
            "required": ["path"]
        }),
        effect: ToolEffect::Read,
    }
}

pub fn apply_patch_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: APPLY_PATCH_TOOL_NAME.to_string(),
        description: APPLY_PATCH_DESCRIPTION.to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "patch": {
                    "type": "string",
                    "description": "Codex envelope. Must start with '*** Begin Patch' and end with '*** End Patch'. See this tool's description for the full grammar, hard rules, and worked examples. Common failure: using unified-diff style ('--- a/file', '+++ b/file', '@@ -1,3 +1,3 @@'). That format is REJECTED."
                },
                "create_parent_dirs": {
                    "type": "boolean",
                    "description": "Create missing parent directories for added files. Defaults to true."
                }
            },
            "required": ["patch"]
        }),
        effect: ToolEffect::Write,
    }
}

const APPLY_PATCH_DESCRIPTION: &str = r#"The ONLY tool for creating, editing, or deleting files in the sandbox. It accepts a single `patch` string in the codex envelope format described below. Read this carefully — a malformed envelope is the most common cause of tool failures.

### Envelope structure

Every call must look like:

```
*** Begin Patch
<one or more file operations>
*** End Patch
```

Three file operations are supported. Pick one per file:

```
*** Add File: /workspace/path/new.txt
+first line of the new file
+second line
```

```
*** Update File: /workspace/path/existing.txt
@@
 context line above (1-3 lines)
-line to remove
+line to add
 context line below (1-3 lines)
```

```
*** Delete File: /workspace/path/old.txt
```

To fully rewrite an existing file, place a `*** Delete File:` and a `*** Add File:` for the same path inside the same envelope.

### Hard rules (every call MUST follow)

1. Start with `*** Begin Patch` and end with `*** End Patch`. No surrounding markdown fences. No leading explanation text inside the patch.
2. Every body line in an `*** Add File:` block MUST start with `+`. Blank lines included.
3. Inside an `*** Update File:` hunk every line MUST start with one of: a single space (` `) for context, `+` for additions, `-` for removals. No other prefixes.
4. Each `@@` introduces one hunk. Include at least 1-3 unchanged context lines above and below the change so the hunk matches uniquely.
5. Paths MUST be absolute sandbox paths starting with `/workspace/`, `/tmp/`, `/home/`, `/var/`, `/etc/`, `/opt/`, `/srv/`, `/run/`, `/usr/`, `/root/`. Relative paths like `src/main.rs` are rejected.
6. Do NOT touch `/skills/...` — that tree is read-only.

### Do NOT (common mistakes that all fail)

- Do NOT use unified-diff style (`--- a/file`, `+++ b/file`, `@@ -1,3 +1,3 @@`). That is git format, not codex format.
- Do NOT omit the `+` on Add File body lines.
- Do NOT omit the leading space on context lines inside an Update File hunk.
- Do NOT wrap the patch in triple backticks or any other markdown.
- Do NOT pass partial files via Update File when you want to replace the whole file — use Delete File + Add File.
- Do NOT include `--- a/x`, `+++ b/x`, file mode lines, or line-range counts.
- Do NOT use shell `cat > file`, heredocs, `tee`, or `sed` to write files.

### Worked example

To rename a function in `/workspace/src/util.py` from `greet()` to `hello()`:

```
*** Begin Patch
*** Update File: /workspace/src/util.py
@@
 import sys

-def greet():
-    print("hi")
+def hello():
+    print("hello, world")

 if __name__ == "__main__":
*** End Patch
```

To create a new file and delete an obsolete one in one call:

```
*** Begin Patch
*** Add File: /workspace/notes/today.md
+# Today
+- shipped patch
*** Delete File: /workspace/notes/old.md
*** End Patch
```

### When a patch fails

The tool returns a structured error with `error_kind` (e.g. `hunk_context_not_found`, `envelope_missing_begin`, `add_file_exists`), `path`, `line`, `hint`, and often `example_fix` (a corrected envelope you can adapt). Read these fields and produce a new envelope — do not retry the exact same patch."#;
