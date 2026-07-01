//! Pure helpers used by the recall index pipeline: document collection
//! from journal/legacy-daily/memory sources, term scoring, and text
//! sanitation / truncation.
//!
//! All functions here are side-effect-free in the workspace sense — they
//! read from filesystem helpers in `workspace::*` but do not touch the
//! recall DB. Keep DB ops in `mod.rs` so the lifecycle of the libsql
//! connection stays in one file.

use std::collections::HashMap;
use std::path::Path;

use chrono::Utc;
use sha2::{Digest, Sha256};

use super::super::JournalTurnRecord;
use super::{MAX_SESSION_CHARS, MAX_SUMMARY_CHARS, RecallDoc};

pub(super) fn collect_memory_docs(files_dir: &str) -> Vec<RecallDoc> {
    curated_paths()
        .iter()
        .filter_map(|path| memory_doc(files_dir, path))
        .collect()
}

pub(super) fn collect_journal_docs(files_dir: &str) -> Vec<RecallDoc> {
    super::super::journal_records(files_dir)
        .into_iter()
        .map(|(path, record)| journal_doc(&path, &record))
        .collect()
}

pub(super) fn collect_legacy_daily_docs(files_dir: &str) -> Vec<RecallDoc> {
    super::super::legacy_daily_contents(files_dir)
        .into_iter()
        .map(|(date, path, content)| legacy_daily_doc(&date, &path, &content))
        .collect()
}

pub(super) fn memory_doc(files_dir: &str, path: &str) -> Option<RecallDoc> {
    if !is_curated_memory_path(path) {
        return None;
    }
    let content = super::super::read_workspace_file_content(files_dir, path)
        .ok()
        .flatten()?;
    if content.trim().is_empty() {
        return None;
    }
    let body = sanitize_recall_text(&content);
    Some(RecallDoc {
        doc_id: format!("memory:{path}"),
        source: "memory".to_string(),
        path: path.to_string(),
        thread_id: None,
        turn_id: None,
        created_at: None,
        updated_at: super::super::modified_workspace_path(files_dir, path),
        content_hash: stable_hash(&body),
        title: path.to_string(),
        body,
        score: 0.0,
    })
}

fn journal_doc(path: &str, record: &JournalTurnRecord) -> RecallDoc {
    let body = sanitize_recall_text(&super::super::journal_record_search_text(record));
    RecallDoc {
        doc_id: format!("journal:{path}#{}", record.turn_id),
        source: "journal".to_string(),
        path: path.to_string(),
        thread_id: Some(record.thread_id.clone()).filter(|value| !value.trim().is_empty()),
        turn_id: Some(record.turn_id.clone()).filter(|value| !value.trim().is_empty()),
        created_at: Some(record.created_at.clone()).filter(|value| !value.trim().is_empty()),
        updated_at: Some(record.created_at.clone()).filter(|value| !value.trim().is_empty()),
        content_hash: stable_hash(&body),
        title: journal_title(record),
        body,
        score: 0.0,
    }
}

fn legacy_daily_doc(date: &str, path: &Path, content: &str) -> RecallDoc {
    let body = sanitize_recall_text(content);
    RecallDoc {
        doc_id: format!("legacy_daily:{date}"),
        source: "legacy_daily".to_string(),
        path: format!("daily/{date}.md"),
        thread_id: None,
        turn_id: Some(format!("legacy-daily-{date}")),
        created_at: super::super::modified_rfc3339(path)
            .or_else(|| Some(format!("{date}T00:00:00Z"))),
        updated_at: super::super::modified_rfc3339(path),
        content_hash: stable_hash(&body),
        title: format!("Legacy daily log {date}"),
        body,
        score: 0.0,
    }
}

pub(super) fn session_text_for_group(
    journal_records: Option<&[JournalTurnRecord]>,
    source: &str,
    docs: &[RecallDoc],
    terms: &[String],
) -> String {
    if source == "journal"
        && let Some(records) = journal_records
        && !records.is_empty()
    {
        return records
            .iter()
            .map(format_record_for_recall)
            .collect::<Vec<_>>()
            .join("\n\n");
    }
    let joined = docs
        .iter()
        .map(|doc| doc.body.as_str())
        .collect::<Vec<_>>()
        .join("\n\n");
    truncate_around_terms(&joined, terms, MAX_SESSION_CHARS)
}

pub(super) fn journal_records_by_thread(
    files_dir: &str,
) -> HashMap<String, Vec<JournalTurnRecord>> {
    let mut records_by_thread = HashMap::<String, Vec<JournalTurnRecord>>::new();
    for (_, record) in super::super::journal_records(files_dir) {
        if record.thread_id.trim().is_empty() {
            continue;
        }
        records_by_thread
            .entry(record.thread_id.clone())
            .or_default()
            .push(record);
    }
    for records in records_by_thread.values_mut() {
        records.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    }
    records_by_thread
}

fn format_record_for_recall(record: &JournalTurnRecord) -> String {
    match record.kind.as_str() {
        "note" => format!("[NOTE {}]\n{}", record.created_at, record.user),
        _ => format!(
            "[TURN {}]\n[USER]\n{}\n\n[ASSISTANT]\n{}",
            record.created_at, record.user, record.assistant
        ),
    }
}

fn journal_title(record: &JournalTurnRecord) -> String {
    let first_line = record
        .user
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("Journal turn");
    truncate_chars(first_line, 80)
}

fn curated_paths() -> &'static [&'static str] {
    &[
        super::super::USER,
        super::super::MEMORY,
        super::super::PROJECT,
        super::super::PROFILE,
        super::super::ASSISTANT_DIRECTIVES,
        super::super::HEARTBEAT,
    ]
}

pub(super) fn is_curated_memory_path(path: &str) -> bool {
    curated_paths().contains(&path)
}

pub(super) fn fts_query(terms: &[String]) -> String {
    terms
        .iter()
        .map(|term| format!("\"{}\"", term.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(" OR ")
}

pub(super) fn weighted_score(doc: &RecallDoc, rank: f64) -> f64 {
    source_weight(&doc.source) + (1.0 / (1.0 + rank.abs())) + recency_weight(doc)
}

pub(super) fn source_weight(source: &str) -> f64 {
    match source {
        "memory" => 100.0,
        "journal" => 50.0,
        "legacy_daily" => 10.0,
        _ => 0.0,
    }
}

fn recency_weight(doc: &RecallDoc) -> f64 {
    let Some(created_at) = doc.created_at.as_deref() else {
        return 0.0;
    };
    let Ok(parsed) = chrono::DateTime::parse_from_rfc3339(created_at) else {
        return 0.0;
    };
    let age_days = (Utc::now() - parsed.with_timezone(&Utc)).num_days().max(0);
    (30_i64.saturating_sub(age_days).max(0) as f64) / 30.0
}

pub(super) fn group_score(docs: &[RecallDoc]) -> f64 {
    docs.iter().map(|doc| doc.score).fold(0.0, f64::max) + docs.len() as f64 / 10.0
}

pub(super) fn source_hash(docs: &[RecallDoc]) -> String {
    let mut parts = docs
        .iter()
        .map(|doc| format!("{}:{}", doc.doc_id, doc.content_hash))
        .collect::<Vec<_>>();
    parts.sort();
    stable_hash(&parts.join("\n"))
}

pub(super) fn source_fingerprint_meta_key(source: &str) -> String {
    format!("source_fingerprint:{source}")
}

pub(super) fn session_cache_source_hash(thread_id: &str, source: &str, window: &str) -> String {
    stable_hash(&format!(
        "thread:{thread_id}\nsource:{source}\nwindow:{}",
        stable_hash(window)
    ))
}

pub(super) fn stable_hash(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    format!("{:x}", hasher.finalize())
}

pub(super) fn fallback_preview(text: &str) -> String {
    format!(
        "[Raw preview - summarization unavailable]\n{}",
        truncate_chars(text.trim(), MAX_SUMMARY_CHARS)
    )
}

pub(super) fn sanitize_recall_text(text: &str) -> String {
    let mut out = text
        .replace("<memory-context>", "&lt;memory-context&gt;")
        .replace("</memory-context>", "&lt;/memory-context&gt;")
        .replace("[System note:", "[Historical note:");
    out.retain(|ch| !matches!(ch, '\u{200B}' | '\u{200C}' | '\u{200D}' | '\u{FEFF}'));
    out
}

pub(super) fn truncate_around_terms(text: &str, terms: &[String], max_chars: usize) -> String {
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let lower = text.to_ascii_lowercase();
    let first_byte = terms
        .iter()
        .filter_map(|term| lower.find(term))
        .min()
        .unwrap_or(0);
    let first = text
        .get(..first_byte)
        .map(|prefix| prefix.chars().count())
        .unwrap_or(0);
    let start = first.saturating_sub(max_chars / 4);
    let end = start + max_chars;
    let chars = text.chars().collect::<Vec<_>>();
    let start = start.min(chars.len());
    let end = end.min(chars.len());
    let mut out = String::new();
    if start > 0 {
        out.push_str("...[earlier conversation truncated]...\n\n");
    }
    out.extend(chars[start..end].iter());
    if end < chars.len() {
        out.push_str("\n\n...[later conversation truncated]...");
    }
    out
}

pub(super) fn truncate_chars(text: &str, max_chars: usize) -> String {
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let mut out = text
        .chars()
        .take(max_chars.saturating_sub(1))
        .collect::<String>();
    out.push('…');
    out
}
