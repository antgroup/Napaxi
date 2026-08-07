//! Project membership and runtime-workspace placement.
//!
//! A session keeps its immutable [`SessionKey`](crate::session::SessionKey).
//! Its sidebar placement (`project_id`) and execution location
//! (`runtime_workspace_id`) are mutable, independent state stored here.

use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const DB_FILE: &str = "napaxi_projects.db";
const WORKSPACE_ROOT: &str = "environment-workspace/projects";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkspaceKind {
    Personal,
    Project,
    External,
}

impl WorkspaceKind {
    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "personal" => Ok(Self::Personal),
            "project" => Ok(Self::Project),
            "external" => Ok(Self::External),
            _ => Err(format!("Unknown workspace kind: {value}")),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectRecord {
    pub id: String,
    pub account_id: String,
    pub agent_id: String,
    pub name: String,
    pub default_workspace_id: String,
    pub state: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceRecord {
    pub id: String,
    pub account_id: String,
    pub agent_id: String,
    pub kind: WorkspaceKind,
    pub owner_project_id: Option<String>,
    pub physical_root: String,
    pub state: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionPlacement {
    pub thread_id: String,
    pub project_id: Option<String>,
    pub runtime_workspace_id: String,
    pub working_directory: Option<String>,
    pub revision: i64,
    pub project_entered_at: Option<String>,
    pub workspace_updated_at: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorkspacePolicy {
    UseProjectDefault,
    KeepCurrent,
    UsePersonalDefault,
}

impl WorkspacePolicy {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value.trim() {
            "use_project_default" => Ok(Self::UseProjectDefault),
            "keep_current" => Ok(Self::KeepCurrent),
            "use_personal_default" => Ok(Self::UsePersonalDefault),
            other => Err(format!("Unknown workspace policy: {other}")),
        }
    }
}

fn now() -> String {
    Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

fn db_path(files_dir: &str) -> PathBuf {
    Path::new(files_dir).join(DB_FILE)
}

fn validate_id(value: &str, label: &str) -> Result<String, String> {
    let value = value.trim();
    if value.is_empty()
        || value.len() > 120
        || !value
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
    {
        return Err(format!("Invalid {label}"));
    }
    Ok(value.to_string())
}

fn deterministic_workspace_id(kind: &str, account_id: &str, agent_id: &str, seed: &str) -> String {
    let name = format!("{kind}\u{0}{account_id}\u{0}{agent_id}\u{0}{seed}");
    format!(
        "{kind}-{}",
        Uuid::new_v5(&Uuid::NAMESPACE_URL, name.as_bytes())
    )
}

fn workspace_root(files_dir: &str, workspace_id: &str) -> String {
    Path::new(files_dir)
        .join(WORKSPACE_ROOT)
        .join(workspace_id)
        .display()
        .to_string()
}

#[cfg(feature = "libsql")]
async fn connection(files_dir: &str) -> Result<libsql::Connection, String> {
    std::fs::create_dir_all(files_dir).map_err(|error| error.to_string())?;
    let db = libsql::Builder::new_local(db_path(files_dir))
        .build()
        .await
        .map_err(|error| error.to_string())?;
    let conn = db.connect().map_err(|error| error.to_string())?;
    conn.execute_batch(
        r#"
        PRAGMA busy_timeout = 5000;
        PRAGMA foreign_keys = ON;
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            agent_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            owner_project_id TEXT,
            physical_root TEXT NOT NULL,
            state TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            agent_id TEXT NOT NULL,
            name TEXT NOT NULL,
            default_workspace_id TEXT NOT NULL REFERENCES workspaces(id),
            state TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session_placements (
            thread_id TEXT PRIMARY KEY,
            project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
            runtime_workspace_id TEXT NOT NULL REFERENCES workspaces(id),
            working_directory TEXT,
            revision INTEGER NOT NULL DEFAULT 1,
            project_entered_at TEXT,
            workspace_updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_projects_owner
            ON projects(account_id, agent_id, state);
        CREATE INDEX IF NOT EXISTS idx_session_placements_project
            ON session_placements(project_id);
        "#,
    )
    .await
    .map_err(|error| error.to_string())?;
    Ok(conn)
}

#[cfg(not(feature = "libsql"))]
async fn connection(_files_dir: &str) -> Result<(), String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
async fn ensure_personal_workspace(
    conn: &libsql::Connection,
    files_dir: &str,
    account_id: &str,
    agent_id: &str,
) -> Result<WorkspaceRecord, String> {
    let id = deterministic_workspace_id("personal", account_id, agent_id, "default");
    let timestamp = now();
    let physical_root = crate::workspace::scoped_files_dir(files_dir, account_id, agent_id);
    conn.execute(
        r#"INSERT INTO workspaces
           (id, account_id, agent_id, kind, owner_project_id, physical_root, state, created_at, updated_at)
           VALUES (?1, ?2, ?3, 'personal', NULL, ?4, 'active', ?5, ?5)
           ON CONFLICT(id) DO NOTHING"#,
        libsql::params![
            id.as_str(),
            account_id,
            agent_id,
            physical_root.as_str(),
            timestamp.as_str()
        ],
    )
    .await
    .map_err(|error| error.to_string())?;
    std::fs::create_dir_all(&physical_root).map_err(|error| error.to_string())?;
    Ok(WorkspaceRecord {
        id,
        account_id: account_id.to_string(),
        agent_id: agent_id.to_string(),
        kind: WorkspaceKind::Personal,
        owner_project_id: None,
        physical_root,
        state: "active".to_string(),
        created_at: timestamp.clone(),
        updated_at: timestamp,
    })
}

#[cfg(feature = "libsql")]
fn project_from_row(row: &libsql::Row) -> Result<ProjectRecord, String> {
    Ok(ProjectRecord {
        id: row.get(0).map_err(|error| error.to_string())?,
        account_id: row.get(1).map_err(|error| error.to_string())?,
        agent_id: row.get(2).map_err(|error| error.to_string())?,
        name: row.get(3).map_err(|error| error.to_string())?,
        default_workspace_id: row.get(4).map_err(|error| error.to_string())?,
        state: row.get(5).map_err(|error| error.to_string())?,
        created_at: row.get(6).map_err(|error| error.to_string())?,
        updated_at: row.get(7).map_err(|error| error.to_string())?,
    })
}

#[cfg(feature = "libsql")]
fn workspace_from_row(row: &libsql::Row) -> Result<WorkspaceRecord, String> {
    let kind: String = row.get(3).map_err(|error| error.to_string())?;
    Ok(WorkspaceRecord {
        id: row.get(0).map_err(|error| error.to_string())?,
        account_id: row.get(1).map_err(|error| error.to_string())?,
        agent_id: row.get(2).map_err(|error| error.to_string())?,
        kind: WorkspaceKind::from_str(&kind)?,
        owner_project_id: row.get(4).map_err(|error| error.to_string())?,
        physical_root: row.get(5).map_err(|error| error.to_string())?,
        state: row.get(6).map_err(|error| error.to_string())?,
        created_at: row.get(7).map_err(|error| error.to_string())?,
        updated_at: row.get(8).map_err(|error| error.to_string())?,
    })
}

#[cfg(feature = "libsql")]
fn placement_from_row(row: &libsql::Row) -> Result<SessionPlacement, String> {
    Ok(SessionPlacement {
        thread_id: row.get(0).map_err(|error| error.to_string())?,
        project_id: row.get(1).map_err(|error| error.to_string())?,
        runtime_workspace_id: row.get(2).map_err(|error| error.to_string())?,
        working_directory: row.get(3).map_err(|error| error.to_string())?,
        revision: row.get(4).map_err(|error| error.to_string())?,
        project_entered_at: row.get(5).map_err(|error| error.to_string())?,
        workspace_updated_at: row.get(6).map_err(|error| error.to_string())?,
    })
}

#[cfg(feature = "libsql")]
async fn get_project_on_conn(
    conn: &libsql::Connection,
    project_id: &str,
) -> Result<Option<ProjectRecord>, String> {
    let mut rows = conn
        .query(
            "SELECT id, account_id, agent_id, name, default_workspace_id, state, created_at, updated_at FROM projects WHERE id = ?1",
            libsql::params![project_id],
        )
        .await
        .map_err(|error| error.to_string())?;
    rows.next()
        .await
        .map_err(|error| error.to_string())?
        .map(|row| project_from_row(&row))
        .transpose()
}

#[cfg(feature = "libsql")]
async fn get_workspace_on_conn(
    conn: &libsql::Connection,
    workspace_id: &str,
) -> Result<Option<WorkspaceRecord>, String> {
    let mut rows = conn
        .query(
            "SELECT id, account_id, agent_id, kind, owner_project_id, physical_root, state, created_at, updated_at FROM workspaces WHERE id = ?1",
            libsql::params![workspace_id],
        )
        .await
        .map_err(|error| error.to_string())?;
    rows.next()
        .await
        .map_err(|error| error.to_string())?
        .map(|row| workspace_from_row(&row))
        .transpose()
}

#[cfg(feature = "libsql")]
async fn get_placement_on_conn(
    conn: &libsql::Connection,
    thread_id: &str,
) -> Result<Option<SessionPlacement>, String> {
    let mut rows = conn
        .query(
            "SELECT thread_id, project_id, runtime_workspace_id, working_directory, revision, project_entered_at, workspace_updated_at FROM session_placements WHERE thread_id = ?1",
            libsql::params![thread_id],
        )
        .await
        .map_err(|error| error.to_string())?;
    rows.next()
        .await
        .map_err(|error| error.to_string())?
        .map(|row| placement_from_row(&row))
        .transpose()
}

#[cfg(feature = "libsql")]
pub async fn register_project(
    files_dir: &str,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
    name: &str,
) -> Result<ProjectRecord, String> {
    let project_id = validate_id(project_id, "project id")?;
    let account_id = account_id.trim();
    let agent_id = agent_id.trim();
    let name = name.trim();
    if account_id.is_empty() || agent_id.is_empty() || name.is_empty() {
        return Err("Project account, agent, and name are required".to_string());
    }
    let conn = connection(files_dir).await?;
    if let Some(existing) = get_project_on_conn(&conn, &project_id).await?
        && (existing.account_id != account_id || existing.agent_id != agent_id)
    {
        return Err("Project id belongs to a different owner".to_string());
    }
    let workspace_id = deterministic_workspace_id("project", account_id, agent_id, &project_id);
    let physical_root = workspace_root(files_dir, &workspace_id);
    let timestamp = now();
    conn.execute("BEGIN IMMEDIATE", ())
        .await
        .map_err(|error| error.to_string())?;
    let result = async {
        conn.execute(
            r#"INSERT INTO workspaces
               (id, account_id, agent_id, kind, owner_project_id, physical_root, state, created_at, updated_at)
               VALUES (?1, ?2, ?3, 'project', ?4, ?5, 'active', ?6, ?6)
               ON CONFLICT(id) DO UPDATE SET
                 owner_project_id = excluded.owner_project_id,
                 physical_root = excluded.physical_root,
                 state = 'active',
                 updated_at = excluded.updated_at"#,
            libsql::params![workspace_id.as_str(), account_id, agent_id, project_id.as_str(), physical_root.as_str(), timestamp.as_str()],
        ).await.map_err(|error| error.to_string())?;
        conn.execute(
            r#"INSERT INTO projects
               (id, account_id, agent_id, name, default_workspace_id, state, created_at, updated_at)
               VALUES (?1, ?2, ?3, ?4, ?5, 'active', ?6, ?6)
               ON CONFLICT(id) DO UPDATE SET
                 name = excluded.name,
                 state = 'active',
                 updated_at = excluded.updated_at"#,
            libsql::params![project_id.as_str(), account_id, agent_id, name, workspace_id.as_str(), timestamp.as_str()],
        ).await.map_err(|error| error.to_string())?;
        get_project_on_conn(&conn, &project_id).await?.ok_or_else(|| "Project registration did not persist".to_string())
    }.await;
    match result {
        Ok(project) => {
            conn.execute("COMMIT", ())
                .await
                .map_err(|error| error.to_string())?;
            std::fs::create_dir_all(&physical_root).map_err(|error| error.to_string())?;
            Ok(project)
        }
        Err(error) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(error)
        }
    }
}

#[cfg(not(feature = "libsql"))]
pub async fn register_project(
    _files_dir: &str,
    _project_id: &str,
    _account_id: &str,
    _agent_id: &str,
    _name: &str,
) -> Result<ProjectRecord, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn list_projects(
    files_dir: &str,
    account_id: &str,
    agent_id: &str,
) -> Result<Vec<ProjectRecord>, String> {
    let conn = connection(files_dir).await?;
    let mut rows = conn.query(
        "SELECT id, account_id, agent_id, name, default_workspace_id, state, created_at, updated_at FROM projects WHERE account_id = ?1 AND agent_id = ?2 AND state = 'active' ORDER BY updated_at DESC",
        libsql::params![account_id.trim(), agent_id.trim()],
    ).await.map_err(|error| error.to_string())?;
    let mut projects = Vec::new();
    while let Some(row) = rows.next().await.map_err(|error| error.to_string())? {
        projects.push(project_from_row(&row)?);
    }
    Ok(projects)
}

#[cfg(not(feature = "libsql"))]
pub async fn list_projects(
    _files_dir: &str,
    _account_id: &str,
    _agent_id: &str,
) -> Result<Vec<ProjectRecord>, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn archive_project(
    files_dir: &str,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
) -> Result<bool, String> {
    let conn = connection(files_dir).await?;
    let timestamp = now();
    conn.execute("BEGIN IMMEDIATE", ())
        .await
        .map_err(|error| error.to_string())?;
    let result = async {
        let changed = conn.execute(
            "UPDATE projects SET state = 'archived', updated_at = ?4 WHERE id = ?1 AND account_id = ?2 AND agent_id = ?3 AND state = 'active'",
            libsql::params![project_id.trim(), account_id.trim(), agent_id.trim(), timestamp.as_str()],
        ).await.map_err(|error| error.to_string())?;
        if changed > 0 {
            conn.execute(
                "UPDATE session_placements SET project_id = NULL, revision = revision + 1, project_entered_at = NULL WHERE project_id = ?1",
                libsql::params![project_id.trim()],
            ).await.map_err(|error| error.to_string())?;
        }
        Ok(changed > 0)
    }.await;
    match result {
        Ok(changed) => {
            conn.execute("COMMIT", ())
                .await
                .map_err(|error| error.to_string())?;
            Ok(changed)
        }
        Err(error) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(error)
        }
    }
}

#[cfg(not(feature = "libsql"))]
pub async fn archive_project(
    _files_dir: &str,
    _project_id: &str,
    _account_id: &str,
    _agent_id: &str,
) -> Result<bool, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
async fn session_identity(
    files_dir: &str,
    session_key_json: &str,
) -> Result<(crate::session::SessionKey, String), String> {
    let key: crate::session::SessionKey = serde_json::from_str(session_key_json)
        .map_err(|error| format!("Invalid session key: {error}"))?;
    let Some((stored_account_id, stored_agent_id)) =
        crate::session::session_owner(files_dir, &key.thread_id)
    else {
        return Err("Session not found".to_string());
    };
    if key.account_id != stored_account_id {
        return Err("Session account does not match persisted session".to_string());
    }
    Ok((key, stored_agent_id))
}

#[cfg(feature = "libsql")]
async fn ensure_placement_on_conn(
    conn: &libsql::Connection,
    files_dir: &str,
    key: &crate::session::SessionKey,
    agent_id: &str,
) -> Result<SessionPlacement, String> {
    if let Some(placement) = get_placement_on_conn(conn, &key.thread_id).await? {
        let workspace_owned = get_workspace_on_conn(conn, &placement.runtime_workspace_id)
            .await?
            .is_some_and(|workspace| {
                workspace.account_id == key.account_id && workspace.agent_id == agent_id
            });
        let project_owned = match placement.project_id.as_deref() {
            Some(project_id) => {
                get_project_on_conn(conn, project_id)
                    .await?
                    .is_some_and(|project| {
                        project.account_id == key.account_id && project.agent_id == agent_id
                    })
            }
            None => true,
        };
        if workspace_owned && project_owned {
            return Ok(placement);
        }
        conn.execute(
            "DELETE FROM session_placements WHERE thread_id = ?1",
            libsql::params![key.thread_id.as_str()],
        )
        .await
        .map_err(|error| error.to_string())?;
    }
    let personal = ensure_personal_workspace(conn, files_dir, &key.account_id, agent_id).await?;
    let timestamp = now();
    conn.execute(
        r#"INSERT INTO session_placements
           (thread_id, project_id, runtime_workspace_id, working_directory, revision, project_entered_at, workspace_updated_at)
           VALUES (?1, NULL, ?2, NULL, 1, NULL, ?3)
           ON CONFLICT(thread_id) DO NOTHING"#,
        libsql::params![key.thread_id.as_str(), personal.id.as_str(), timestamp.as_str()],
    ).await.map_err(|error| error.to_string())?;
    get_placement_on_conn(conn, &key.thread_id)
        .await?
        .ok_or_else(|| "Session placement was not persisted".to_string())
}

#[cfg(feature = "libsql")]
pub async fn get_session_placement(
    files_dir: &str,
    session_key_json: &str,
) -> Result<SessionPlacement, String> {
    let (key, agent_id) = session_identity(files_dir, session_key_json).await?;
    let conn = connection(files_dir).await?;
    ensure_placement_on_conn(&conn, files_dir, &key, &agent_id).await
}

#[cfg(not(feature = "libsql"))]
pub async fn get_session_placement(
    _files_dir: &str,
    _session_key_json: &str,
) -> Result<SessionPlacement, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn list_session_placements(
    files_dir: &str,
    account_id: &str,
    agent_id: &str,
) -> Result<Vec<SessionPlacement>, String> {
    let conn = connection(files_dir).await?;
    let mut rows = conn
        .query(
            r#"SELECT sp.thread_id, sp.project_id, sp.runtime_workspace_id, sp.working_directory,
                  sp.revision, sp.project_entered_at, sp.workspace_updated_at
           FROM session_placements sp
           JOIN workspaces w ON w.id = sp.runtime_workspace_id
           WHERE w.account_id = ?1 AND w.agent_id = ?2
           ORDER BY sp.workspace_updated_at DESC"#,
            libsql::params![account_id.trim(), agent_id.trim()],
        )
        .await
        .map_err(|error| error.to_string())?;
    let mut placements = Vec::new();
    while let Some(row) = rows.next().await.map_err(|error| error.to_string())? {
        let thread_id = row.get::<String>(0).map_err(|error| error.to_string())?;
        if crate::session::session_owner(files_dir, &thread_id).is_some_and(
            |(stored_account_id, stored_agent_id)| {
                stored_account_id == account_id.trim() && stored_agent_id == agent_id.trim()
            },
        ) {
            placements.push(placement_from_row(&row)?);
        }
    }
    Ok(placements)
}

#[cfg(not(feature = "libsql"))]
pub async fn list_session_placements(
    _files_dir: &str,
    _account_id: &str,
    _agent_id: &str,
) -> Result<Vec<SessionPlacement>, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn move_session_to_project(
    files_dir: &str,
    session_key_json: &str,
    project_id: Option<&str>,
    workspace_policy: WorkspacePolicy,
    expected_revision: Option<i64>,
    reject_workspace_change: bool,
) -> Result<SessionPlacement, String> {
    let (key, agent_id) = session_identity(files_dir, session_key_json).await?;
    let conn = connection(files_dir).await?;
    conn.execute("BEGIN IMMEDIATE", ())
        .await
        .map_err(|error| error.to_string())?;
    let result = async {
        let current = ensure_placement_on_conn(&conn, files_dir, &key, &agent_id).await?;
        if expected_revision.is_some_and(|revision| revision != current.revision) {
            return Err("Session placement revision conflict".to_string());
        }
        let normalized_project_id = project_id.map(str::trim).filter(|id| !id.is_empty());
        let target_project = match normalized_project_id {
            Some(id) => {
                let project = get_project_on_conn(&conn, id)
                    .await?
                    .ok_or_else(|| "Project not found".to_string())?;
                if project.account_id != key.account_id || project.agent_id != agent_id || project.state != "active" {
                    return Err("Project does not belong to this session owner".to_string());
                }
                Some(project)
            }
            None => None,
        };
        let target_workspace_id = match workspace_policy {
            WorkspacePolicy::KeepCurrent => current.runtime_workspace_id.clone(),
            WorkspacePolicy::UseProjectDefault => target_project
                .as_ref()
                .map(|project| project.default_workspace_id.clone())
                .ok_or_else(|| "Project-default policy requires a project".to_string())?,
            WorkspacePolicy::UsePersonalDefault => ensure_personal_workspace(
                &conn,
                files_dir,
                &key.account_id,
                &agent_id,
            )
            .await?
            .id,
        };
        if reject_workspace_change && target_workspace_id != current.runtime_workspace_id {
            return Err("session_busy: runtime workspace cannot change during an active turn".to_string());
        }
        let timestamp = now();
        let project_entered_at = target_project.as_ref().map(|_| timestamp.clone());
        conn.execute(
            r#"UPDATE session_placements SET
                 project_id = ?2,
                 runtime_workspace_id = ?3,
                 revision = revision + 1,
                 project_entered_at = ?4,
                 workspace_updated_at = CASE WHEN runtime_workspace_id = ?3 THEN workspace_updated_at ELSE ?5 END
               WHERE thread_id = ?1"#,
            libsql::params![
                key.thread_id.as_str(),
                target_project.as_ref().map(|project| project.id.as_str()),
                target_workspace_id.as_str(),
                project_entered_at.as_deref(),
                timestamp.as_str()
            ],
        ).await.map_err(|error| error.to_string())?;
        get_placement_on_conn(&conn, &key.thread_id).await?.ok_or_else(|| "Session placement disappeared".to_string())
    }.await;
    match result {
        Ok(placement) => {
            conn.execute("COMMIT", ())
                .await
                .map_err(|error| error.to_string())?;
            Ok(placement)
        }
        Err(error) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(error)
        }
    }
}

#[cfg(not(feature = "libsql"))]
pub async fn move_session_to_project(
    _files_dir: &str,
    _session_key_json: &str,
    _project_id: Option<&str>,
    _workspace_policy: WorkspacePolicy,
    _expected_revision: Option<i64>,
    _reject_workspace_change: bool,
) -> Result<SessionPlacement, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn resolve_session_workspace(
    files_dir: &str,
    session_key_json: &str,
) -> Result<WorkspaceRecord, String> {
    let placement = get_session_placement(files_dir, session_key_json).await?;
    let conn = connection(files_dir).await?;
    let workspace = get_workspace_on_conn(&conn, &placement.runtime_workspace_id)
        .await?
        .ok_or_else(|| "Runtime workspace not found".to_string())?;
    std::fs::create_dir_all(&workspace.physical_root).map_err(|error| error.to_string())?;
    Ok(workspace)
}

#[cfg(not(feature = "libsql"))]
pub async fn resolve_session_workspace(
    _files_dir: &str,
    _session_key_json: &str,
) -> Result<WorkspaceRecord, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(feature = "libsql")]
pub async fn project_workspace(
    files_dir: &str,
    project_id: &str,
    account_id: &str,
    agent_id: &str,
) -> Result<WorkspaceRecord, String> {
    let conn = connection(files_dir).await?;
    let project = get_project_on_conn(&conn, project_id.trim())
        .await?
        .ok_or_else(|| "Project not found".to_string())?;
    if project.account_id != account_id.trim()
        || project.agent_id != agent_id.trim()
        || project.state != "active"
    {
        return Err("Project does not belong to this owner".to_string());
    }
    get_workspace_on_conn(&conn, &project.default_workspace_id)
        .await?
        .ok_or_else(|| "Project workspace not found".to_string())
}

#[cfg(not(feature = "libsql"))]
pub async fn project_workspace(
    _files_dir: &str,
    _project_id: &str,
    _account_id: &str,
    _agent_id: &str,
) -> Result<WorkspaceRecord, String> {
    Err("Project placement requires the libsql feature".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn display_project_and_runtime_workspace_can_move_together_or_independently() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let key_json = crate::session::create_session(files_dir, "agent-a", "app", "acct-a", None);
        let project_a = register_project(files_dir, "project-a", "acct-a", "agent-a", "A")
            .await
            .unwrap();
        let project_b = register_project(files_dir, "project-b", "acct-a", "agent-a", "B")
            .await
            .unwrap();

        let in_a = move_session_to_project(
            files_dir,
            &key_json,
            Some(&project_a.id),
            WorkspacePolicy::UseProjectDefault,
            None,
            false,
        )
        .await
        .unwrap();
        assert_eq!(in_a.project_id.as_deref(), Some("project-a"));
        assert_eq!(in_a.runtime_workspace_id, project_a.default_workspace_id);

        let busy_error = move_session_to_project(
            files_dir,
            &key_json,
            Some(&project_b.id),
            WorkspacePolicy::UseProjectDefault,
            Some(in_a.revision),
            true,
        )
        .await
        .unwrap_err();
        assert!(busy_error.contains("session_busy"));

        let displayed_in_b = move_session_to_project(
            files_dir,
            &key_json,
            Some(&project_b.id),
            WorkspacePolicy::KeepCurrent,
            Some(in_a.revision),
            true,
        )
        .await
        .unwrap();
        assert_eq!(displayed_in_b.project_id.as_deref(), Some("project-b"));
        assert_eq!(
            displayed_in_b.runtime_workspace_id,
            project_a.default_workspace_id
        );

        let moved_out = move_session_to_project(
            files_dir,
            &key_json,
            None,
            WorkspacePolicy::UsePersonalDefault,
            Some(displayed_in_b.revision),
            false,
        )
        .await
        .unwrap();
        assert_eq!(moved_out.project_id, None);
        assert_ne!(
            moved_out.runtime_workspace_id,
            project_a.default_workspace_id
        );
    }

    #[tokio::test]
    async fn placement_revision_is_compare_and_swap_guard() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let key_json = crate::session::create_session(files_dir, "agent-a", "app", "acct-a", None);
        let project = register_project(files_dir, "project-a", "acct-a", "agent-a", "A")
            .await
            .unwrap();
        let initial = get_session_placement(files_dir, &key_json).await.unwrap();
        let moved = move_session_to_project(
            files_dir,
            &key_json,
            Some(&project.id),
            WorkspacePolicy::UseProjectDefault,
            Some(initial.revision),
            false,
        )
        .await
        .unwrap();
        assert!(moved.revision > initial.revision);
        let error = move_session_to_project(
            files_dir,
            &key_json,
            None,
            WorkspacePolicy::KeepCurrent,
            Some(initial.revision),
            false,
        )
        .await
        .unwrap_err();
        assert!(error.contains("revision conflict"));
    }

    #[tokio::test]
    async fn project_owner_files_and_archive_boundaries_are_preserved() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let key_json = crate::session::create_session(files_dir, "agent-a", "app", "acct-a", None);
        let project = register_project(files_dir, "project-a", "acct-a", "agent-a", "A")
            .await
            .unwrap();
        let duplicate_owner_error =
            register_project(files_dir, "project-a", "acct-b", "agent-b", "B")
                .await
                .unwrap_err();
        assert!(duplicate_owner_error.contains("different owner"));
        assert!(
            project_workspace(files_dir, &project.id, "acct-b", "agent-b")
                .await
                .is_err()
        );

        let placed = move_session_to_project(
            files_dir,
            &key_json,
            Some(&project.id),
            WorkspacePolicy::UseProjectDefault,
            None,
            false,
        )
        .await
        .unwrap();
        let workspace = project_workspace(files_dir, &project.id, "acct-a", "agent-a")
            .await
            .unwrap();
        let bridge = crate::storage::FileBridge::new_with_workspace_files_dir(
            files_dir,
            &workspace.physical_root,
        );
        bridge.ensure_workspace_inner().unwrap();
        std::fs::write(bridge.workspace_dir().join("note.txt"), "hello").unwrap();
        let listing =
            crate::storage::list_workspace_filesystem_json_with_bridge(&bridge, None, true);
        assert!(listing.contains("/workspace/note.txt"));

        assert!(
            !archive_project(files_dir, &project.id, "acct-b", "agent-b")
                .await
                .unwrap()
        );
        assert_eq!(
            get_session_placement(files_dir, &key_json)
                .await
                .unwrap()
                .project_id
                .as_deref(),
            Some("project-a")
        );
        assert!(
            archive_project(files_dir, &project.id, "acct-a", "agent-a")
                .await
                .unwrap()
        );
        let after_archive = get_session_placement(files_dir, &key_json).await.unwrap();
        assert_eq!(after_archive.project_id, None);
        assert_eq!(
            after_archive.runtime_workspace_id,
            placed.runtime_workspace_id
        );
        assert!(bridge.workspace_dir().join("note.txt").exists());
    }

    #[tokio::test]
    async fn stale_placement_cannot_cross_a_recreated_session_owner() {
        let temp = tempfile::tempdir().unwrap();
        let files_dir = temp.path().to_str().unwrap();
        let original_json =
            crate::session::create_session(files_dir, "agent-a", "app", "acct-a", None);
        let original: crate::session::SessionKey = serde_json::from_str(&original_json).unwrap();
        let project = register_project(files_dir, "project-a", "acct-a", "agent-a", "A")
            .await
            .unwrap();
        move_session_to_project(
            files_dir,
            &original_json,
            Some(&project.id),
            WorkspacePolicy::UseProjectDefault,
            None,
            false,
        )
        .await
        .unwrap();
        assert!(crate::session::delete_session(files_dir, &original_json));

        let recreated_json = crate::session::create_session(
            files_dir,
            "agent-b",
            "app",
            "acct-b",
            Some(&original.thread_id),
        );
        let recreated = get_session_placement(files_dir, &recreated_json)
            .await
            .unwrap();
        assert_eq!(recreated.project_id, None);
        assert_ne!(recreated.runtime_workspace_id, project.default_workspace_id);
        assert!(
            list_session_placements(files_dir, "acct-a", "agent-a")
                .await
                .unwrap()
                .is_empty()
        );
    }
}
