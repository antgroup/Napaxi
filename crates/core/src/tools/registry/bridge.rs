//! Host tool dispatch over a bridge.

use std::sync::atomic::Ordering;
use std::time::Duration;

use serde_json::Value;
use tokio::sync::oneshot;

use super::pending::{
    REQUEST_ID_COUNTER, register_pending_request_route, remove_pending_request_route,
};
use super::types::{ToolExecutionContext, ToolRequestBridge};

pub async fn request_host_tool_execution(
    bridge: ToolRequestBridge,
    tool_name: &str,
    params: Value,
    timeout: Duration,
) -> Result<String, String> {
    request_host_tool_execution_with_context(bridge, tool_name, params, timeout, None).await
}

pub(crate) async fn request_host_tool_execution_with_context(
    bridge: ToolRequestBridge,
    tool_name: &str,
    params: Value,
    timeout: Duration,
    context: Option<&ToolExecutionContext>,
) -> Result<String, String> {
    let request_id = REQUEST_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = oneshot::channel();
    bridge.pending_requests.insert(request_id, tx)?;
    register_pending_request_route(request_id, &bridge.pending_requests)?;

    let params_json = serde_json::to_string(&params).unwrap_or_else(|_| "{}".to_string());
    (bridge.dispatcher)(request_id, tool_name, &params_json, context);

    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => {
            remove_pending_request_route(request_id);
            bridge.pending_requests.remove(request_id);
            Err("Tool request was dropped without a response".to_string())
        }
        Err(_) => {
            remove_pending_request_route(request_id);
            bridge.pending_requests.remove(request_id);
            Err(format!(
                "Tool request timed out after {}s",
                timeout.as_secs()
            ))
        }
    }
}
