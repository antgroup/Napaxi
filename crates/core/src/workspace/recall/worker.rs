//! Background recall-index worker.
//!
//! Curated-memory and journal updates are queued through this worker so the
//! synchronous public API (`upsert_memory_path_best_effort`,
//! `upsert_journal_record_best_effort`, `delete_path_best_effort`) never
//! blocks the caller on libsql I/O. The worker drains a bounded MPSC channel
//! on a dedicated thread that owns a single-threaded tokio runtime.

use std::sync::OnceLock;
use std::sync::mpsc::{self, SyncSender, TrySendError};

use super::index::{delete_path_async, refresh_journal_async, upsert_memory_path_async};

const RECALL_WORKER_QUEUE_BOUND: usize = 256;

#[derive(Debug)]
pub(super) enum RecallIndexEvent {
    UpsertMemoryPath {
        files_dir: String,
        path: String,
    },
    RefreshJournal {
        files_dir: String,
    },
    DeletePath {
        files_dir: String,
        path: String,
        is_prefix: bool,
    },
}

pub(super) fn dispatch_recall_event(event: RecallIndexEvent) {
    let Some(sender) = recall_worker_sender() else {
        tracing::warn!("recall index worker is unavailable");
        return;
    };
    match sender.try_send(event) {
        Ok(()) => {}
        Err(TrySendError::Full(event)) => {
            tracing::warn!("recall index worker queue is full; dropping {:?}", event);
        }
        Err(TrySendError::Disconnected(event)) => {
            tracing::warn!("recall index worker is disconnected; dropping {:?}", event);
        }
    }
}

fn recall_worker_sender() -> Option<&'static SyncSender<RecallIndexEvent>> {
    static WORKER: OnceLock<Option<SyncSender<RecallIndexEvent>>> = OnceLock::new();
    WORKER.get_or_init(start_recall_worker).as_ref()
}

fn start_recall_worker() -> Option<SyncSender<RecallIndexEvent>> {
    let (sender, receiver) = mpsc::sync_channel::<RecallIndexEvent>(RECALL_WORKER_QUEUE_BOUND);
    match std::thread::Builder::new()
        .name("napaxi-recall-index".to_string())
        .spawn(move || {
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(error) => {
                    tracing::warn!("failed to start recall index runtime: {}", error);
                    return;
                }
            };
            while let Ok(event) = receiver.recv() {
                if let Err(error) = runtime.block_on(handle_recall_event(event)) {
                    tracing::warn!("recall index worker event failed: {}", error);
                }
            }
        }) {
        Ok(_) => Some(sender),
        Err(error) => {
            tracing::warn!("failed to start recall index worker: {}", error);
            None
        }
    }
}

async fn handle_recall_event(event: RecallIndexEvent) -> Result<(), String> {
    match event {
        RecallIndexEvent::UpsertMemoryPath { files_dir, path } => {
            upsert_memory_path_async(&files_dir, &path).await
        }
        RecallIndexEvent::RefreshJournal { files_dir } => refresh_journal_async(&files_dir).await,
        RecallIndexEvent::DeletePath {
            files_dir,
            path,
            is_prefix,
        } => delete_path_async(&files_dir, &path, is_prefix).await,
    }
}

pub(super) fn run_blocking<F, T>(future: F) -> Result<T, String>
where
    F: std::future::Future<Output = Result<T, String>> + Send + 'static,
    T: Send + 'static,
{
    std::thread::spawn(move || {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| e.to_string())?
            .block_on(future)
    })
    .join()
    .map_err(|_| "recall worker panicked".to_string())?
}
