//! Pending request tables and global request-id routing.

use std::collections::HashMap;
use std::sync::atomic::AtomicU64;
use std::sync::{Arc, Mutex, Weak};

use std::sync::LazyLock;
use tokio::sync::oneshot;

pub(super) static REQUEST_ID_COUNTER: AtomicU64 = AtomicU64::new(1);
pub(super) static PENDING_REQUEST_ROUTES: LazyLock<Mutex<HashMap<u64, Weak<PendingToolRequests>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
pub(super) static PROCESS_PENDING_REQUESTS: LazyLock<Arc<PendingToolRequests>> =
    LazyLock::new(|| Arc::new(PendingToolRequests::default()));

#[derive(Default)]
pub(crate) struct PendingToolRequests {
    pending: Mutex<HashMap<u64, oneshot::Sender<Result<String, String>>>>,
}

impl PendingToolRequests {
    pub(super) fn insert(
        &self,
        request_id: u64,
        tx: oneshot::Sender<Result<String, String>>,
    ) -> Result<(), String> {
        let mut pending = self
            .pending
            .lock()
            .map_err(|e| format!("Lock poisoned: {e}"))?;
        pending.insert(request_id, tx);
        Ok(())
    }

    pub(super) fn remove(&self, request_id: u64) {
        if let Ok(mut pending) = self.pending.lock() {
            pending.remove(&request_id);
        }
    }

    pub(super) fn resolve(&self, request_id: u64, result: String, is_error: bool) -> bool {
        let tx = {
            let Ok(mut pending) = self.pending.lock() else {
                return false;
            };
            pending.remove(&request_id)
        };

        if let Some(tx) = tx {
            let payload = if is_error { Err(result) } else { Ok(result) };
            tx.send(payload).is_ok()
        } else {
            false
        }
    }

    #[cfg(test)]
    pub(super) fn len(&self) -> usize {
        self.pending
            .lock()
            .map(|pending| pending.len())
            .unwrap_or(0)
    }
}

pub(super) fn register_pending_request_route(
    request_id: u64,
    pending_requests: &Arc<PendingToolRequests>,
) -> Result<(), String> {
    let mut routes = PENDING_REQUEST_ROUTES
        .lock()
        .map_err(|e| format!("Lock poisoned: {e}"))?;
    routes.insert(request_id, Arc::downgrade(pending_requests));
    Ok(())
}

pub(super) fn remove_pending_request_route(request_id: u64) {
    if let Ok(mut routes) = PENDING_REQUEST_ROUTES.lock() {
        routes.remove(&request_id);
    }
}

pub fn resolve_tool_execution(request_id: u64, result: String, is_error: bool) -> bool {
    let pending_requests = {
        let Ok(mut routes) = PENDING_REQUEST_ROUTES.lock() else {
            return false;
        };
        routes.remove(&request_id).and_then(|route| route.upgrade())
    };

    if let Some(pending_requests) = pending_requests {
        pending_requests.resolve(request_id, result, is_error)
    } else {
        false
    }
}
