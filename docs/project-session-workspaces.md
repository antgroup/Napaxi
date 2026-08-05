# Project session workspaces

Napaxi follows the flexible Codex model: conversation identity, sidebar
organization, and execution location are separate concepts.

## Invariants

- `SessionKey(channelType, accountId, threadId)` is immutable.
- A session is displayed in zero or one project (`project_id`).
- A session executes in exactly one runtime workspace
  (`runtime_workspace_id`).
- A turn snapshots the resolved workspace before tools or an agent engine run.
- A runtime-workspace change is rejected while the session has an active turn;
  a display-only move remains safe.
- Project deletion archives metadata and clears display membership. It does not
  delete workspace files.

Core stores `projects`, `workspaces`, and `session_placements` in
`napaxi_projects.db`. Placement writes use `BEGIN IMMEDIATE`; `revision` is the
compare-and-swap token for concurrent UI/background updates.

## Move semantics

| Operation | `project_id` | Runtime workspace |
|---|---|---|
| New project session | project | project default |
| Move A to B (default) | B | B default |
| Move A to B (`keep_current`) | B | unchanged (possibly A) |
| Move out (default) | null | personal default |
| Move out (`keep_current`) | null | unchanged |

The UI must show a mismatch badge when a session is displayed in a project but
its runtime workspace is not that project's default.

## Files and engine routing

Project workspace scopes live under the host's persistent
`environment-workspace/projects/<workspace-id>` root; their sandbox-visible
files are in `linux-env/workspace` below that scope, matching the existing
`FileBridge` layout. Core tools, the built-in Codex engine, the external CC
bridge, and the project Files page all resolve that same workspace record. CC
keeps one stable HOME/history store and receives the matching sandbox path as a
per-turn `cwd`; moving a session does not fork its identity or history.

The project Files page is read-only in V1. Preview, download, and share use the
existing file browser, while deletion stays disabled until a project-scoped
mutation API can apply policy and audit checks.

## Migration and extension

Demo-local project metadata is registered into Core on restore. Existing local
session-to-project mappings are migrated once a Core session key is available;
afterward Core placements replace the local mapping for display. Unknown fields
on legacy session JSON (including the abandoned `workspace_scope` prototype)
are ignored, so session identity remains readable.

If a deleted thread ID is explicitly recreated under another owner, Core
discards any stale placement whose workspace/project owner no longer matches
the persisted session. This prevents an orphaned placement from crossing an
account or agent boundary.

Future external workspaces can add a `WorkspaceKind.external` record and a
host-resolved physical root without changing `SessionKey` or project
membership. Future “apply next turn” behavior can extend the placement update
with a pending workspace revision; it should not mutate an in-flight turn's
snapshot.
