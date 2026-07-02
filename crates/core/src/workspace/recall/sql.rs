//! libsql backing store for the recall index: open the DB, enforce schema,
//! upsert/delete docs, run paginated queries, manage summary cache, and run
//! write-transaction lifecycles.
//!
//! All functions in this module are `#[cfg(feature = "libsql")]` — callers
//! must be similarly gated. The module is the only place that names
//! libsql types or SQL statements.

use chrono::Utc;

use super::{RecallDoc, corpus::source_weight, db_path, reset_db_file};

pub(super) async fn open_db(files_dir: &str) -> Result<libsql::Database, String> {
    let path = db_path(files_dir);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    match libsql::Builder::new_local(path.clone()).build().await {
        Ok(db) => Ok(db),
        Err(error) => {
            reset_db_file(files_dir);
            libsql::Builder::new_local(path)
                .build()
                .await
                .map_err(|e| format!("{error}; retry failed: {e}"))
        }
    }
}

pub(super) async fn ensure_schema(conn: &libsql::Connection) -> Result<(), String> {
    conn.execute_batch(
        r#"
        PRAGMA busy_timeout = 5000;
        CREATE TABLE IF NOT EXISTS recall_docs (
            doc_id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            path TEXT NOT NULL,
            thread_id TEXT,
            turn_id TEXT,
            created_at TEXT,
            updated_at TEXT,
            content_hash TEXT NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS recall_docs_fts
        USING fts5(doc_id UNINDEXED, title, body);
        CREATE TABLE IF NOT EXISTS recall_session_summaries (
            thread_id TEXT NOT NULL,
            query_hash TEXT NOT NULL,
            source_hash TEXT NOT NULL,
            query TEXT NOT NULL,
            summary TEXT NOT NULL,
            model TEXT NOT NULL,
            created_at TEXT NOT NULL,
            source_doc_ids TEXT NOT NULL,
            PRIMARY KEY (thread_id, query_hash, source_hash)
        );
        CREATE TABLE IF NOT EXISTS recall_index_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        "#,
    )
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub(super) async fn upsert_doc_on_conn(
    conn: &libsql::Connection,
    doc: &RecallDoc,
) -> Result<(), String> {
    conn.execute(
        r#"
        INSERT INTO recall_docs
            (doc_id, source, path, thread_id, turn_id, created_at, updated_at,
             content_hash, title, body)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        ON CONFLICT(doc_id) DO UPDATE SET
            source = excluded.source,
            path = excluded.path,
            thread_id = excluded.thread_id,
            turn_id = excluded.turn_id,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            content_hash = excluded.content_hash,
            title = excluded.title,
            body = excluded.body
        "#,
        libsql::params![
            doc.doc_id.as_str(),
            doc.source.as_str(),
            doc.path.as_str(),
            doc.thread_id.as_deref().unwrap_or(""),
            doc.turn_id.as_deref().unwrap_or(""),
            doc.created_at.as_deref().unwrap_or(""),
            doc.updated_at.as_deref().unwrap_or(""),
            doc.content_hash.as_str(),
            doc.title.as_str(),
            doc.body.as_str(),
        ],
    )
    .await
    .map_err(|e| e.to_string())?;
    conn.execute(
        "DELETE FROM recall_docs_fts WHERE doc_id = ?1",
        libsql::params![doc.doc_id.as_str()],
    )
    .await
    .map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO recall_docs_fts (doc_id, title, body) VALUES (?1, ?2, ?3)",
        libsql::params![doc.doc_id.as_str(), doc.title.as_str(), doc.body.as_str()],
    )
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub(super) async fn replace_docs_for_source_on_conn(
    conn: &libsql::Connection,
    source: &str,
    docs: &[RecallDoc],
) -> Result<(), String> {
    conn.execute(
        "DELETE FROM recall_docs_fts \
         WHERE doc_id IN (SELECT doc_id FROM recall_docs WHERE source = ?1)",
        libsql::params![source],
    )
    .await
    .map_err(|e| e.to_string())?;
    conn.execute(
        "DELETE FROM recall_docs WHERE source = ?1",
        libsql::params![source],
    )
    .await
    .map_err(|e| e.to_string())?;
    for doc in docs {
        if doc.source == source {
            upsert_doc_on_conn(conn, doc).await?;
        }
    }
    Ok(())
}

pub(super) async fn delete_path_on_conn(
    conn: &libsql::Connection,
    path: &str,
    is_prefix: bool,
) -> Result<(), String> {
    let normalized = path.trim().trim_matches('/');
    if normalized.is_empty() {
        return Ok(());
    }
    let prefix = format!("{normalized}/");
    let mut rows = conn
        .query("SELECT doc_id, path FROM recall_docs", ())
        .await
        .map_err(|e| e.to_string())?;
    let mut doc_ids = Vec::new();
    while let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        let doc_id = row.get::<String>(0).map_err(|e| e.to_string())?;
        let doc_path = row.get::<String>(1).map_err(|e| e.to_string())?;
        if doc_path == normalized || (is_prefix && doc_path.starts_with(&prefix)) {
            doc_ids.push(doc_id);
        }
    }
    drop(rows);
    for doc_id in doc_ids {
        conn.execute(
            "DELETE FROM recall_docs_fts WHERE doc_id = ?1",
            libsql::params![doc_id.as_str()],
        )
        .await
        .map_err(|e| e.to_string())?;
        conn.execute(
            "DELETE FROM recall_docs WHERE doc_id = ?1",
            libsql::params![doc_id.as_str()],
        )
        .await
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub(super) async fn begin_write_transaction(conn: &libsql::Connection) -> Result<(), String> {
    conn.execute("BEGIN IMMEDIATE", ())
        .await
        .map(|_| ())
        .map_err(|e| e.to_string())
}

pub(super) async fn finish_write_transaction(
    conn: &libsql::Connection,
    result: Result<(), String>,
) -> Result<(), String> {
    match result {
        Ok(()) => match conn.execute("COMMIT", ()).await {
            Ok(_) => Ok(()),
            Err(error) => {
                let _ = conn.execute("ROLLBACK", ()).await;
                Err(error.to_string())
            }
        },
        Err(error) => {
            let _ = conn.execute("ROLLBACK", ()).await;
            Err(error)
        }
    }
}

pub(super) async fn like_search_docs(
    conn: &libsql::Connection,
    terms: &[String],
    limit: i64,
) -> Result<Vec<RecallDoc>, String> {
    let mut rows = conn
        .query(
            "SELECT doc_id, source, path, thread_id, turn_id, created_at, updated_at, \
             content_hash, title, body FROM recall_docs",
            (),
        )
        .await
        .map_err(|e| e.to_string())?;
    let mut docs = Vec::new();
    while let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        let mut doc = row_to_doc(&row)?;
        let haystack = format!("{}\n{}", doc.title, doc.body).to_ascii_lowercase();
        let hits = terms
            .iter()
            .map(|term| haystack.matches(term).count())
            .sum::<usize>();
        if hits > 0 {
            doc.score = source_weight(&doc.source) + hits as f64;
            docs.push(doc);
        }
    }
    docs.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    docs.truncate(limit as usize);
    Ok(docs)
}

pub(super) fn row_to_doc(row: &libsql::Row) -> Result<RecallDoc, String> {
    Ok(RecallDoc {
        doc_id: row.get::<String>(0).map_err(|e| e.to_string())?,
        source: row.get::<String>(1).map_err(|e| e.to_string())?,
        path: row.get::<String>(2).map_err(|e| e.to_string())?,
        thread_id: optional_string(row, 3),
        turn_id: optional_string(row, 4),
        created_at: optional_string(row, 5),
        updated_at: optional_string(row, 6),
        content_hash: row.get::<String>(7).map_err(|e| e.to_string())?,
        title: row.get::<String>(8).map_err(|e| e.to_string())?,
        body: row.get::<String>(9).map_err(|e| e.to_string())?,
        score: 0.0,
    })
}

pub(super) fn optional_string(row: &libsql::Row, index: i32) -> Option<String> {
    row.get::<String>(index)
        .ok()
        .filter(|value| !value.trim().is_empty())
}

pub(super) async fn count_docs(conn: &libsql::Connection) -> Result<usize, String> {
    count_query(conn, "SELECT COUNT(*) FROM recall_docs", ()).await
}

pub(super) async fn count_docs_by_source(
    conn: &libsql::Connection,
    source: &str,
) -> Result<usize, String> {
    count_query(
        conn,
        "SELECT COUNT(*) FROM recall_docs WHERE source = ?1",
        libsql::params![source],
    )
    .await
}

pub(super) async fn count_summaries(conn: &libsql::Connection) -> Result<usize, String> {
    count_query(conn, "SELECT COUNT(*) FROM recall_session_summaries", ()).await
}

async fn count_query<P>(conn: &libsql::Connection, sql: &str, params: P) -> Result<usize, String>
where
    P: libsql::params::IntoParams,
{
    let mut rows = conn.query(sql, params).await.map_err(|e| e.to_string())?;
    let Some(row) = rows.next().await.map_err(|e| e.to_string())? else {
        return Ok(0);
    };
    let count = row.get::<i64>(0).map_err(|e| e.to_string())?;
    Ok(count.max(0) as usize)
}

pub(super) async fn meta_value(
    conn: &libsql::Connection,
    key: &str,
) -> Result<Option<String>, String> {
    let mut rows = conn
        .query(
            "SELECT value FROM recall_index_meta WHERE key = ?1",
            libsql::params![key],
        )
        .await
        .map_err(|e| e.to_string())?;
    if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        Ok(row.get::<String>(0).ok())
    } else {
        Ok(None)
    }
}

pub(super) async fn set_meta(
    conn: &libsql::Connection,
    key: &str,
    value: &str,
) -> Result<(), String> {
    conn.execute(
        "INSERT OR REPLACE INTO recall_index_meta (key, value) VALUES (?1, ?2)",
        libsql::params![key, value],
    )
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}

pub(super) async fn cached_summary(
    files_dir: &str,
    thread_id: &str,
    query_hash: &str,
    source_hash: &str,
) -> Result<Option<String>, String> {
    let db = open_db(files_dir).await?;
    let conn = db.connect().map_err(|e| e.to_string())?;
    ensure_schema(&conn).await?;
    let mut rows = conn
        .query(
            "SELECT summary FROM recall_session_summaries \
             WHERE thread_id = ?1 AND query_hash = ?2 AND source_hash = ?3",
            libsql::params![thread_id, query_hash, source_hash],
        )
        .await
        .map_err(|e| e.to_string())?;
    if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        Ok(row.get::<String>(0).ok())
    } else {
        Ok(None)
    }
}

pub(super) async fn save_summary_cache(
    files_dir: &str,
    thread_id: &str,
    query_hash: &str,
    source_hash: &str,
    query: &str,
    summary: &str,
    model: &str,
    source_doc_ids: &[String],
) -> Result<(), String> {
    let db = open_db(files_dir).await?;
    let conn = db.connect().map_err(|e| e.to_string())?;
    ensure_schema(&conn).await?;
    let source_doc_ids = serde_json::to_string(source_doc_ids).map_err(|e| e.to_string())?;
    conn.execute(
        r#"
        INSERT OR REPLACE INTO recall_session_summaries
            (thread_id, query_hash, source_hash, query, summary, model, created_at, source_doc_ids)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        "#,
        libsql::params![
            thread_id,
            query_hash,
            source_hash,
            query,
            summary,
            model,
            Utc::now().to_rfc3339(),
            source_doc_ids,
        ],
    )
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}
