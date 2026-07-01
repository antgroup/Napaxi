//! Term-frequency search over workspace memory files and journal records.

use super::files::read_workspace_file_content;
use super::journal::{journal_record_search_text, journal_records, legacy_daily_contents};
use super::meta::{error_json, invalid_handle_json, modified_rfc3339};
use super::paths::{
    ASSISTANT_DIRECTIVES, HEARTBEAT, MEMORY, PROFILE, PROJECT, USER, workspace_path,
};
use super::types::MemorySearchResult;

pub fn search_memory(files_dir: &str, query: &str, limit: usize) -> String {
    match search_memory_results(files_dir, query, limit) {
        Ok(results) => {
            serde_json::to_string(&results).unwrap_or_else(|e| error_json(&e.to_string()))
        }
        Err(error) => error_json(&error),
    }
}

pub fn search_memory_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    query: &str,
    limit: u32,
) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    search_memory(&files_dir, query, limit.clamp(1, 20) as usize)
}

pub fn search_memory_results(
    files_dir: &str,
    query: &str,
    limit: usize,
) -> Result<Vec<MemorySearchResult>, String> {
    match super::recall::search_memory_results(files_dir, query, limit.clamp(1, 20)) {
        Ok(results) => return Ok(results),
        Err(error) => {
            tracing::warn!(
                "recall index search failed, falling back to scan: {}",
                error
            );
        }
    }
    search_memory_results_fallback(files_dir, query, limit)
}

pub(crate) fn search_memory_results_fallback(
    files_dir: &str,
    query: &str,
    limit: usize,
) -> Result<Vec<MemorySearchResult>, String> {
    let terms = search_terms(query);
    if terms.is_empty() {
        return Err("query cannot be empty".to_string());
    }

    let mut results = Vec::new();
    for path in [
        USER,
        MEMORY,
        PROJECT,
        PROFILE,
        ASSISTANT_DIRECTIVES,
        HEARTBEAT,
    ] {
        let Ok(Some(content)) = read_workspace_file_content(files_dir, path) else {
            continue;
        };
        if let Some(result) = score_search_content(
            "memory",
            path,
            &content,
            modified_workspace_path(files_dir, path),
            &terms,
        ) {
            results.push(result);
        }
    }

    for (path, record) in journal_records(files_dir) {
        let content = journal_record_search_text(&record);
        if let Some(result) = score_search_content(
            "journal",
            &format!("{path}#{}", record.turn_id),
            &content,
            None,
            &terms,
        ) {
            results.push(result);
        }
    }

    for (date, path, content) in legacy_daily_contents(files_dir) {
        if let Some(result) = score_search_content(
            "legacy_daily",
            &format!("daily/{date}.md"),
            &content,
            modified_rfc3339(&path),
            &terms,
        ) {
            results.push(result);
        }
    }

    results.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.path.cmp(&b.path))
    });
    results.truncate(limit.clamp(1, 20));
    Ok(results)
}

fn score_search_content(
    source: &str,
    path: &str,
    content: &str,
    updated_at: Option<String>,
    terms: &[String],
) -> Option<MemorySearchResult> {
    let haystack = content.to_ascii_lowercase();
    let score = terms
        .iter()
        .map(|term| haystack.matches(term).count())
        .sum::<usize>();
    if score == 0 {
        return None;
    }
    let hybrid = is_hybrid_match(&haystack, terms);
    Some(MemorySearchResult {
        source: source.to_string(),
        path: path.to_string(),
        content: snippet(content, terms),
        score: score as f64 + if hybrid { HYBRID_MATCH_BONUS } else { 0.0 },
        is_hybrid_match: hybrid,
        updated_at,
        thread_id: None,
        turn_id: None,
        created_at: None,
    })
}

/// Score bonus applied to a result that covers every query term, so that
/// full-coverage ("hybrid") matches outrank single-term hits.
pub(super) const HYBRID_MATCH_BONUS: f64 = 1000.0;

/// A result is a hybrid match when the query has more than one term and the
/// haystack (already lowercased) contains every one of them. Single-term
/// queries can never be hybrid matches.
pub(super) fn is_hybrid_match(haystack_lower: &str, terms: &[String]) -> bool {
    terms.len() > 1 && terms.iter().all(|term| haystack_lower.contains(term))
}

pub(super) fn search_terms(query: &str) -> Vec<String> {
    query
        .to_ascii_lowercase()
        .split(|ch: char| !ch.is_alphanumeric())
        .filter(|term| term.len() >= 2)
        .map(str::to_string)
        .collect()
}

pub(super) fn snippet(content: &str, terms: &[String]) -> String {
    let lowered = content.to_ascii_lowercase();
    let first_match = terms
        .iter()
        .filter_map(|term| lowered.find(term))
        .min()
        .unwrap_or(0);
    let start_hint = content
        .char_indices()
        .map(|(idx, _)| idx)
        .take_while(|idx| *idx <= first_match)
        .last()
        .unwrap_or(0)
        .saturating_sub(120);
    let start = content
        .char_indices()
        .map(|(idx, _)| idx)
        .take_while(|idx| *idx <= start_hint)
        .last()
        .unwrap_or(0);
    let end = content
        .char_indices()
        .map(|(idx, _)| idx)
        .find(|idx| *idx >= (first_match + 280).min(content.len()))
        .unwrap_or(content.len());
    content[start..end].replace('\n', " ")
}

pub(super) fn modified_workspace_path(files_dir: &str, path: &str) -> Option<String> {
    workspace_path(files_dir, path)
        .ok()
        .and_then(|path| modified_rfc3339(&path))
}
