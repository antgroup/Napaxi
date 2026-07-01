//! `ToolRegistry`: per-engine host tool registration and dispatch.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::RwLock;

use super::bridge::request_host_tool_execution_with_context;
use super::pending::PendingToolRequests;
use super::prepare::{prepare_tool_arguments, validate_tool_definition};
use super::types::{
    ToolDescriptor, ToolExecutionContext, ToolRequestBridge, ToolRequestDispatcher,
};

#[derive(Default)]
pub struct ToolRegistry {
    tools: RwLock<HashMap<String, ToolDescriptor>>,
    custom_tool_names: Mutex<HashSet<String>>,
    dispatcher: Mutex<Option<ToolRequestDispatcher>>,
    pending_requests: Arc<PendingToolRequests>,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_dispatcher(&self, dispatcher: ToolRequestDispatcher) -> bool {
        let Ok(mut guard) = self.dispatcher.lock() else {
            return false;
        };
        *guard = Some(dispatcher);
        true
    }

    #[allow(dead_code)] // Public introspection helper; reserved for adapter routing.
    pub fn dispatcher(&self) -> Option<ToolRequestDispatcher> {
        self.dispatcher.lock().ok().and_then(|guard| guard.clone())
    }

    pub(crate) fn request_bridge(&self) -> Option<ToolRequestBridge> {
        self.dispatcher
            .lock()
            .ok()
            .and_then(|guard| guard.clone())
            .map(|dispatcher| ToolRequestBridge {
                dispatcher,
                pending_requests: Arc::clone(&self.pending_requests),
            })
    }

    pub async fn replace_custom_tools(&self, tools_json: &str) -> Result<usize, String> {
        let defs: Vec<ToolDescriptor> =
            serde_json::from_str(tools_json).map_err(|e| format!("Invalid tools JSON: {e}"))?;

        for def in &defs {
            validate_tool_definition(def)?;
        }

        let mut next_names = HashSet::new();
        let mut tools = self.tools.write().await;

        {
            let names = self
                .custom_tool_names
                .lock()
                .map_err(|e| format!("Lock poisoned: {e}"))?;
            for name in names.iter() {
                tools.remove(name);
            }
        }

        for def in defs {
            next_names.insert(def.name.clone());
            tools.insert(def.name.clone(), def);
        }
        drop(tools);

        let count = next_names.len();
        let mut names = self
            .custom_tool_names
            .lock()
            .map_err(|e| format!("Lock poisoned: {e}"))?;
        *names = next_names;
        Ok(count)
    }

    pub async fn list_tools(&self) -> Vec<ToolDescriptor> {
        let mut tools: Vec<_> = self.tools.read().await.values().cloned().collect();
        tools.sort_by(|a, b| a.name.cmp(&b.name));
        tools
    }

    #[allow(dead_code)] // Public custom-tool entry kept for adapter parity with the context variant below.
    pub async fn execute_custom_tool(
        &self,
        tool_name: &str,
        params: serde_json::Value,
    ) -> Result<String, String> {
        self.execute_custom_tool_with_context(tool_name, params, None)
            .await
    }

    pub async fn execute_custom_tool_with_context(
        &self,
        tool_name: &str,
        params: serde_json::Value,
        context: Option<&ToolExecutionContext>,
    ) -> Result<String, String> {
        let descriptor = self
            .tools
            .read()
            .await
            .get(tool_name)
            .cloned()
            .ok_or_else(|| format!("Tool not found: {tool_name}"))?;
        let params = prepare_tool_arguments(&descriptor, params)?;
        let dispatcher = self
            .dispatcher
            .lock()
            .map_err(|e| format!("Lock poisoned: {e}"))?
            .clone()
            .ok_or_else(|| "No tool request dispatcher registered".to_string())?;

        request_host_tool_execution_with_context(
            ToolRequestBridge {
                dispatcher,
                pending_requests: Arc::clone(&self.pending_requests),
            },
            tool_name,
            params,
            Duration::from_secs(600),
            context,
        )
        .await
    }

    #[cfg(test)]
    pub(super) fn pending_request_count(&self) -> usize {
        self.pending_requests.len()
    }
}
