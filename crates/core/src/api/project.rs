//! Project and session-placement API.

use crate::project::WorkspacePolicy;

fn files_dir(handle: i64) -> Result<String, String> {
    crate::runtime::files_dir_from_handle(handle).ok_or_else(|| "invalid engine handle".to_string())
}

fn json_result<T: serde::Serialize>(result: Result<T, String>) -> String {
    match result {
        Ok(value) => serde_json::to_string(&value)
            .unwrap_or_else(|error| serde_json::json!({ "error": error.to_string() }).to_string()),
        Err(error) => serde_json::json!({ "error": error }).to_string(),
    }
}

/// Register or update a project and ensure its default workspace exists.
pub async fn register_project_handle(
    handle: i64,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
    name: &str,
) -> String {
    let result = match files_dir(handle) {
        Ok(files_dir) => {
            crate::project::register_project(&files_dir, project_id, account_id, agent_id, name)
                .await
        }
        Err(error) => Err(error),
    };
    json_result(result)
}

/// List active projects for an account and agent.
pub async fn list_projects_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let result = match files_dir(handle) {
        Ok(files_dir) => crate::project::list_projects(&files_dir, account_id, agent_id).await,
        Err(error) => Err(error),
    };
    json_result(result)
}

/// Archive a project without deleting its workspace files.
pub async fn archive_project_handle(
    handle: i64,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
) -> String {
    let result = match files_dir(handle) {
        Ok(files_dir) => {
            crate::project::archive_project(&files_dir, project_id, account_id, agent_id).await
        }
        Err(error) => Err(error),
    };
    json_result(result)
}

/// Return one session's display project and runtime-workspace placement.
pub async fn get_session_placement_handle(handle: i64, session_key_json: &str) -> String {
    let result = match files_dir(handle) {
        Ok(files_dir) => crate::project::get_session_placement(&files_dir, session_key_json).await,
        Err(error) => Err(error),
    };
    json_result(result)
}

/// List persisted session placements for an account and agent.
pub async fn list_session_placements_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
) -> String {
    let result = match files_dir(handle) {
        Ok(files_dir) => {
            crate::project::list_session_placements(&files_dir, account_id, agent_id).await
        }
        Err(error) => Err(error),
    };
    json_result(result)
}

/// Move a session's single display membership and optionally its runtime workspace.
///
/// `workspace_policy` accepts `use_project_default`, `keep_current`, or
/// `use_personal_default`. Workspace-changing moves are rejected while the
/// session has an active run; display-only moves remain available.
pub async fn move_session_to_project_handle(
    handle: i64,
    session_key_json: &str,
    project_id: Option<&str>,
    workspace_policy: &str,
    expected_revision: Option<i64>,
) -> String {
    let result = match (files_dir(handle), WorkspacePolicy::parse(workspace_policy)) {
        (Ok(files_dir), Ok(policy)) => {
            let active = session_is_active(&files_dir, session_key_json);
            crate::project::move_session_to_project(
                &files_dir,
                session_key_json,
                project_id,
                policy,
                expected_revision,
                active,
            )
            .await
        }
        (Err(error), _) | (_, Err(error)) => Err(error),
    };
    json_result(result)
}

/// List all files in a project's default workspace using `/workspace` paths.
pub async fn list_project_files_handle(
    handle: i64,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
    subdir: Option<&str>,
    recursive: bool,
) -> String {
    let files_dir = match files_dir(handle) {
        Ok(files_dir) => files_dir,
        Err(error) => return json_result::<Vec<serde_json::Value>>(Err(error)),
    };
    let workspace =
        match crate::project::project_workspace(&files_dir, project_id, account_id, agent_id).await
        {
            Ok(workspace) => workspace,
            Err(error) => return json_result::<Vec<serde_json::Value>>(Err(error)),
        };
    let bridge = crate::storage::FileBridge::new_with_workspace_files_dir(
        &files_dir,
        &workspace.physical_root,
    );
    crate::storage::list_workspace_filesystem_json_with_bridge(&bridge, subdir, recursive)
}

fn session_is_active(files_dir: &str, session_key_json: &str) -> bool {
    let Ok(key) = serde_json::from_str::<crate::session::SessionKey>(session_key_json) else {
        return false;
    };
    let raw = crate::agent_runtime::runs::active_session_runs_handle(files_dir);
    serde_json::from_str::<Vec<serde_json::Value>>(&raw)
        .unwrap_or_default()
        .iter()
        .any(|run| run.get("threadId").and_then(serde_json::Value::as_str) == Some(&key.thread_id))
}

/// Project record exposed to typed adapter code.
pub use crate::project::ProjectRecord;
/// Session placement exposed to typed adapter code.
pub use crate::project::SessionPlacement;
/// Workspace kind exposed to typed adapter code.
pub use crate::project::WorkspaceKind;
/// Workspace record exposed to typed adapter code.
pub use crate::project::WorkspaceRecord;

#[cfg(test)]
mod tests {
    use super::*;

    fn make_handle() -> (i64, tempfile::TempDir) {
        let temp = tempfile::tempdir().unwrap();
        let config_json = serde_json::json!({
            "provider": "openai",
            "api_key": "test",
            "base_url": null,
            "model": "test-model",
            "system_prompt": "",
            "max_tokens": 128
        })
        .to_string();
        let context_json = serde_json::json!({
            "platform": "test",
            "files_dir": temp.path().to_str().unwrap(),
            "native_library_dir": null
        })
        .to_string();
        let handle = crate::runtime::create_engine_handle(&config_json, &context_json).unwrap();
        (handle, temp)
    }

    fn assert_error_json(value: &str, expected: &str) {
        let parsed: serde_json::Value = serde_json::from_str(value).unwrap();
        assert_eq!(
            parsed.get("error").and_then(serde_json::Value::as_str),
            Some(expected)
        );
    }

    #[tokio::test]
    async fn invalid_handle_returns_error_for_project_api() {
        assert_error_json(
            &register_project_handle(0, "project-a", "acct-a", "agent-a", "Project A").await,
            "invalid engine handle",
        );
        assert_error_json(
            &list_projects_handle(0, "acct-a", "agent-a").await,
            "invalid engine handle",
        );
        assert_error_json(
            &archive_project_handle(0, "project-a", "acct-a", "agent-a").await,
            "invalid engine handle",
        );
        assert_error_json(
            &get_session_placement_handle(0, "{}").await,
            "invalid engine handle",
        );
        assert_error_json(
            &list_session_placements_handle(0, "acct-a", "agent-a").await,
            "invalid engine handle",
        );
        assert_error_json(
            &move_session_to_project_handle(0, "{}", None, "keep_current", None).await,
            "invalid engine handle",
        );
        assert_error_json(
            &list_project_files_handle(0, "project-a", "acct-a", "agent-a", None, false).await,
            "invalid engine handle",
        );
    }

    #[tokio::test]
    async fn handle_project_lifecycle_returns_json_contracts() {
        let (handle, temp) = make_handle();
        let files_dir = temp.path().to_str().unwrap();
        let key_json = crate::session::create_session(files_dir, "agent-a", "app", "acct-a", None);

        let registered =
            register_project_handle(handle, "project-a", "acct-a", "agent-a", "Project A").await;
        let project: ProjectRecord = serde_json::from_str(&registered).unwrap();
        assert_eq!(project.id, "project-a");

        let projects_json = list_projects_handle(handle, "acct-a", "agent-a").await;
        let projects: Vec<ProjectRecord> = serde_json::from_str(&projects_json).unwrap();
        assert_eq!(projects.len(), 1);

        let initial_json = get_session_placement_handle(handle, &key_json).await;
        let initial: SessionPlacement = serde_json::from_str(&initial_json).unwrap();
        assert_eq!(initial.project_id, None);

        let moved_json = move_session_to_project_handle(
            handle,
            &key_json,
            Some("project-a"),
            "use_project_default",
            Some(initial.revision),
        )
        .await;
        let moved: SessionPlacement = serde_json::from_str(&moved_json).unwrap();
        assert_eq!(moved.project_id.as_deref(), Some("project-a"));
        assert_eq!(moved.runtime_workspace_id, project.default_workspace_id);

        let placements_json = list_session_placements_handle(handle, "acct-a", "agent-a").await;
        let placements: Vec<SessionPlacement> = serde_json::from_str(&placements_json).unwrap();
        assert_eq!(placements.len(), 1);

        let workspace =
            crate::project::project_workspace(files_dir, "project-a", "acct-a", "agent-a")
                .await
                .unwrap();
        let bridge = crate::storage::FileBridge::new_with_workspace_files_dir(
            files_dir,
            &workspace.physical_root,
        );
        bridge.ensure_workspace_inner().unwrap();
        std::fs::create_dir_all(bridge.workspace_dir().join("notes")).unwrap();
        std::fs::write(bridge.workspace_dir().join("notes/todo.txt"), "hello").unwrap();
        let files = list_project_files_handle(
            handle,
            "project-a",
            "acct-a",
            "agent-a",
            Some("notes"),
            true,
        )
        .await;
        assert!(
            files.contains("/workspace/notes/todo.txt"),
            "files: {files}"
        );

        let archived_json = archive_project_handle(handle, "project-a", "acct-a", "agent-a").await;
        assert!(serde_json::from_str::<bool>(&archived_json).unwrap());
        let projects_after: Vec<ProjectRecord> =
            serde_json::from_str(&list_projects_handle(handle, "acct-a", "agent-a").await).unwrap();
        assert!(projects_after.is_empty());

        crate::runtime::dispose_engine_handle(handle);
    }

    #[tokio::test]
    async fn handle_move_rejects_unknown_workspace_policy() {
        let (handle, _temp) = make_handle();
        let json = move_session_to_project_handle(handle, "{}", None, "unknown_policy", None).await;
        assert_error_json(&json, "Unknown workspace policy: unknown_policy");
        crate::runtime::dispose_engine_handle(handle);
    }
}
