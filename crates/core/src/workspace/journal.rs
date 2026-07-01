//! Journal turn append, listing, and read for the workspace memory layer.
//!
//! Journal records live as JSONL under `napaxi/journal/turns/{date}.jsonl`.
//! Pre-existing daily notes under `memory/daily/{date}.md` are surfaced as
//! legacy entries for back-compat but no longer written to.

use std::fs;
use std::io::Write;
use std::path::PathBuf;

use chrono::{DateTime, Utc};

use super::meta::{error_json, invalid_handle_json, modified_rfc3339, newest_rfc3339};
use super::paths::{JOURNAL_TURNS_DIR, memory_dir};
use super::types::{JournalDay, JournalTurnRecord};

pub fn append_journal_turn(
    files_dir: &str,
    agent_id: &str,
    thread_id: &str,
    user_message: &str,
    assistant_message: &str,
) -> Result<String, String> {
    let now = Utc::now();
    let record = JournalTurnRecord {
        turn_id: turn_id("turn", &now),
        created_at: now.to_rfc3339(),
        agent_id: agent_id.trim().to_string(),
        thread_id: thread_id.trim().to_string(),
        user: user_message.trim().to_string(),
        assistant: assistant_message.trim().to_string(),
        kind: "turn".to_string(),
    };
    let path = append_journal_record(files_dir, record.clone())?;
    super::recall::upsert_journal_record_best_effort(files_dir, &path, &record);
    Ok(path)
}

pub fn append_journal_note(files_dir: &str, content: &str) -> Result<String, String> {
    let now = Utc::now();
    append_journal_record(
        files_dir,
        JournalTurnRecord {
            turn_id: turn_id("note", &now),
            created_at: now.to_rfc3339(),
            agent_id: String::new(),
            thread_id: String::new(),
            user: content.trim().to_string(),
            assistant: String::new(),
            kind: "note".to_string(),
        },
    )
}

pub fn list_journal_days(files_dir: &str) -> String {
    serde_json::to_string(&list_journal_day_entries(files_dir))
        .unwrap_or_else(|e| error_json(&e.to_string()))
}

pub fn list_journal_days_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    list_journal_days(&files_dir)
}

pub fn read_journal_day(files_dir: &str, date: &str) -> String {
    match read_journal_day_records(files_dir, date) {
        Ok(records) => {
            serde_json::to_string(&records).unwrap_or_else(|e| error_json(&e.to_string()))
        }
        Err(error) => error_json(&error),
    }
}

pub fn read_journal_day_handle(
    handle: i64,
    account_id: &str,
    agent_id: &str,
    date: &str,
) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    read_journal_day(&files_dir, date)
}

pub(super) fn journal_records(files_dir: &str) -> Vec<(String, JournalTurnRecord)> {
    let mut records = Vec::new();
    let Ok(entries) = fs::read_dir(journal_turns_dir(files_dir)) else {
        return records;
    };
    for entry in entries.flatten() {
        let disk_path = entry.path();
        if disk_path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
            continue;
        }
        let Some(date) = disk_path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        if !is_valid_journal_date(date) {
            continue;
        }
        let logical_path = format!("{JOURNAL_TURNS_DIR}/{date}.jsonl");
        let Ok(content) = fs::read_to_string(disk_path) else {
            continue;
        };
        for line in content
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
        {
            if let Ok(record) = serde_json::from_str::<JournalTurnRecord>(line) {
                records.push((logical_path.clone(), record));
            }
        }
    }
    records
}

pub(super) fn legacy_daily_contents(files_dir: &str) -> Vec<(String, PathBuf, String)> {
    let daily_dir = memory_dir(files_dir).join("daily");
    let Ok(entries) = fs::read_dir(daily_dir) else {
        return Vec::new();
    };
    let mut items = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("md") {
            continue;
        }
        let Some(date) = path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        if !is_valid_journal_date(date) {
            continue;
        }
        if let Ok(content) = fs::read_to_string(&path) {
            items.push((date.to_string(), path, content));
        }
    }
    items
}

pub(super) fn journal_record_search_text(record: &JournalTurnRecord) -> String {
    match record.kind.as_str() {
        "legacy_daily" | "note" => record.user.clone(),
        _ => format!("{}\n{}", record.user, record.assistant),
    }
}

fn append_journal_record(files_dir: &str, record: JournalTurnRecord) -> Result<String, String> {
    let date = record
        .created_at
        .get(..10)
        .filter(|date| is_valid_journal_date(date))
        .ok_or_else(|| "Invalid journal record timestamp".to_string())?
        .to_string();
    let dir = journal_turns_dir(files_dir);
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join(format!("{date}.jsonl"));
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| e.to_string())?;
    let line = serde_json::to_string(&record).map_err(|e| e.to_string())?;
    file.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
    file.write_all(b"\n").map_err(|e| e.to_string())?;
    Ok(format!("{JOURNAL_TURNS_DIR}/{date}.jsonl"))
}

fn list_journal_day_entries(files_dir: &str) -> Vec<JournalDay> {
    #[derive(Default)]
    struct DayBuilder {
        turn_count: usize,
        updated_at: Option<String>,
        has_journal: bool,
        has_legacy: bool,
    }

    let mut days = std::collections::BTreeMap::<String, DayBuilder>::new();
    if let Ok(entries) = fs::read_dir(journal_turns_dir(files_dir)) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
                continue;
            }
            let Some(date) = path.file_stem().and_then(|stem| stem.to_str()) else {
                continue;
            };
            if !is_valid_journal_date(date) {
                continue;
            }
            let turn_count = fs::read_to_string(&path)
                .map(|content| {
                    content
                        .lines()
                        .filter(|line| !line.trim().is_empty())
                        .count()
                })
                .unwrap_or(0);
            let day = days.entry(date.to_string()).or_default();
            day.turn_count += turn_count;
            day.updated_at = newest_rfc3339(day.updated_at.take(), modified_rfc3339(&path));
            day.has_journal = true;
        }
    }

    for (date, path, _content) in legacy_daily_contents(files_dir) {
        let day = days.entry(date).or_default();
        day.turn_count += 1;
        day.updated_at = newest_rfc3339(day.updated_at.take(), modified_rfc3339(&path));
        day.has_legacy = true;
    }

    days.into_iter()
        .rev()
        .map(|(date, day)| JournalDay {
            path: if day.has_journal {
                format!("{JOURNAL_TURNS_DIR}/{date}.jsonl")
            } else {
                format!("daily/{date}.md")
            },
            date,
            turn_count: day.turn_count,
            updated_at: day.updated_at,
            legacy: day.has_legacy && !day.has_journal,
        })
        .collect()
}

fn read_journal_day_records(files_dir: &str, date: &str) -> Result<Vec<JournalTurnRecord>, String> {
    let date = date.trim();
    if !is_valid_journal_date(date) {
        return Err("Invalid journal date".to_string());
    }

    let mut records = Vec::new();
    let path = journal_turns_dir(files_dir).join(format!("{date}.jsonl"));
    if let Ok(content) = fs::read_to_string(path) {
        for line in content
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
        {
            if let Ok(record) = serde_json::from_str::<JournalTurnRecord>(line) {
                records.push(record);
            }
        }
    }

    let legacy_path = memory_dir(files_dir)
        .join("daily")
        .join(format!("{date}.md"));
    if let Ok(content) = fs::read_to_string(&legacy_path)
        && !content.trim().is_empty()
    {
        records.push(JournalTurnRecord {
            turn_id: format!("legacy-daily-{date}"),
            created_at: modified_rfc3339(&legacy_path)
                .unwrap_or_else(|| format!("{date}T00:00:00Z")),
            agent_id: String::new(),
            thread_id: String::new(),
            user: content,
            assistant: String::new(),
            kind: "legacy_daily".to_string(),
        });
    }
    Ok(records)
}

fn journal_turns_dir(files_dir: &str) -> PathBuf {
    std::path::Path::new(files_dir).join(JOURNAL_TURNS_DIR)
}

fn is_valid_journal_date(date: &str) -> bool {
    date.len() == 10 && chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d").is_ok()
}

fn turn_id(prefix: &str, now: &DateTime<Utc>) -> String {
    let nanos = now
        .timestamp_nanos_opt()
        .unwrap_or_else(|| now.timestamp_micros() * 1_000);
    format!("{prefix}-{nanos}")
}
