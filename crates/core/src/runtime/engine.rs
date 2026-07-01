//! `Engine` — runtime-owned state for one napaxi engine instance.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use serde::Deserialize;

use crate::capabilities::{CapabilityProfile, CapabilitySelection};
use crate::types::PlatformLlmConfig;

use super::session_runtime::{SessionRuntime, SessionTurnRuntime};

pub(super) const DEFAULT_AGENT_ID: &str = super::DEFAULT_AGENT_ID;
pub(super) const DEFAULT_ACCOUNT_ID: &str = super::DEFAULT_ACCOUNT_ID;

#[derive(Deserialize)]
pub(super) struct PlatformContext {
    #[allow(dead_code)]
    pub(super) platform: Option<String>,
    pub(super) files_dir: String,
    #[cfg_attr(not(target_os = "android"), allow(dead_code))]
    pub(super) native_library_dir: Option<String>,
    #[serde(default)]
    pub(super) capability_profile: CapabilityProfile,
    #[serde(default)]
    pub(super) capability_selection: CapabilitySelection,
    #[serde(default)]
    pub(super) skill_readiness: napaxi_skills::SkillReadinessContext,
}

pub struct Engine {
    files_dir: String,
    platform: String,
    native_library_dir: Option<String>,
    config: Mutex<PlatformLlmConfig>,
    capability_profile: Mutex<CapabilityProfile>,
    capability_selection: Mutex<CapabilitySelection>,
    skill_readiness: Mutex<napaxi_skills::SkillReadinessContext>,
    tools: Arc<crate::tool_registry::ToolRegistry>,
    agents: Mutex<HashSet<String>>,
    session_runtime: SessionRuntime,
    /// This engine's own admission-decision trace. Capability admissions that
    /// run inside this engine's operations (via `capabilities::with_admission_sink`)
    /// record here instead of the process-global fallback, so
    /// `admission_trace()` is scoped to this engine.
    admission_sink: crate::capabilities::AdmissionSink,
}

impl Engine {
    pub(super) fn new(
        files_dir: String,
        platform: Option<String>,
        native_library_dir: Option<String>,
        config: PlatformLlmConfig,
        capability_profile: CapabilityProfile,
        capability_selection: CapabilitySelection,
        skill_readiness: napaxi_skills::SkillReadinessContext,
    ) -> Self {
        crate::mcp::update_dynamic_headers(
            &files_dir,
            parse_extra_headers(config.extra_headers.as_deref()),
        );
        Self {
            files_dir,
            platform: platform.unwrap_or_else(default_platform),
            native_library_dir,
            config: Mutex::new(config),
            capability_profile: Mutex::new(capability_profile),
            capability_selection: Mutex::new(capability_selection),
            skill_readiness: Mutex::new(skill_readiness),
            tools: Arc::new(crate::tool_registry::ToolRegistry::new()),
            agents: Mutex::new(HashSet::new()),
            session_runtime: SessionRuntime::new(),
            admission_sink: crate::capabilities::new_admission_sink(),
        }
    }

    pub fn files_dir(&self) -> &str {
        &self.files_dir
    }

    /// This engine's admission sink — pass to
    /// `capabilities::with_admission_sink` when running an operation so its
    /// admissions are attributed to this engine rather than the global buffer.
    pub(crate) fn admission_sink(&self) -> crate::capabilities::AdmissionSink {
        self.admission_sink.clone()
    }

    /// Snapshot of this engine's admission-decision trace (most recent last).
    pub(crate) fn admission_trace(&self) -> Vec<crate::capabilities::AdmissionDecisionRecord> {
        crate::capabilities::sink_snapshot(&self.admission_sink)
    }

    pub fn platform(&self) -> &str {
        &self.platform
    }

    pub fn native_library_dir(&self) -> Option<&str> {
        self.native_library_dir.as_deref()
    }

    pub fn update_config(&self, config: PlatformLlmConfig) -> bool {
        let dynamic_headers = parse_extra_headers(config.extra_headers.as_deref());
        let Ok(mut guard) = self.config.lock() else {
            return false;
        };
        *guard = config;
        drop(guard);
        crate::mcp::update_dynamic_headers(&self.files_dir, dynamic_headers);
        true
    }

    pub fn config_json(&self) -> String {
        let Ok(guard) = self.config.lock() else {
            return config_error_json();
        };
        serde_json::to_string(&*guard).unwrap_or_else(|_| config_error_json())
    }

    pub fn config(&self) -> PlatformLlmConfig {
        let Ok(guard) = self.config.lock() else {
            return default_error_config();
        };
        guard.clone()
    }

    pub fn capability_profile(&self) -> CapabilityProfile {
        self.capability_profile
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default()
    }

    pub fn capability_selection(&self) -> CapabilitySelection {
        let mut selection = self
            .capability_selection
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default();
        let from_config = crate::capabilities::selection_from_llm_config(&self.config());
        selection
            .enabled_capabilities
            .extend(from_config.enabled_capabilities);
        selection
            .disabled_capabilities
            .extend(from_config.disabled_capabilities);
        selection.enabled_capabilities.sort();
        selection.enabled_capabilities.dedup();
        selection.disabled_capabilities.sort();
        selection.disabled_capabilities.dedup();
        selection
    }

    pub fn skill_readiness_context(&self) -> napaxi_skills::SkillReadinessContext {
        let mut readiness = self
            .skill_readiness
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default();
        if readiness
            .platform
            .as_deref()
            .unwrap_or("")
            .trim()
            .is_empty()
        {
            readiness.platform = Some(self.platform().to_string());
        }
        let profile = self.capability_profile();
        let selection = self.capability_selection();
        readiness
            .capabilities
            .extend(profile.supported_capabilities);
        readiness
            .capabilities
            .extend(selection.enabled_capabilities);
        readiness.capabilities.sort();
        readiness.capabilities.dedup();
        readiness
    }

    pub fn config_with_capabilities(&self, mut config: PlatformLlmConfig) -> PlatformLlmConfig {
        config.capability_profile = self.capability_profile();
        let mut selection = self.capability_selection();
        let from_config = crate::capabilities::selection_from_llm_config(&config);
        selection
            .enabled_capabilities
            .extend(from_config.enabled_capabilities);
        selection
            .disabled_capabilities
            .extend(from_config.disabled_capabilities);
        selection.enabled_capabilities.sort();
        selection.enabled_capabilities.dedup();
        selection.disabled_capabilities.sort();
        selection.disabled_capabilities.dedup();
        config.capability_selection = selection;
        config
    }

    pub fn tools(&self) -> Arc<crate::tool_registry::ToolRegistry> {
        Arc::clone(&self.tools)
    }

    pub fn ensure_agent(&self, agent_id: &str) -> bool {
        let Ok(mut agents) = self.agents.lock() else {
            return false;
        };
        agents.insert(normalize_agent_id(agent_id))
    }

    pub fn list_agents_json(&self) -> String {
        let Ok(agents) = self.agents.lock() else {
            return "[]".to_string();
        };
        let mut ids: Vec<_> = agents.iter().cloned().collect();
        ids.sort();
        serde_json::to_string(&ids).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn delete_agent(&self, agent_id: &str) -> bool {
        let Ok(mut agents) = self.agents.lock() else {
            return false;
        };
        agents.remove(&normalize_agent_id(agent_id))
    }

    pub fn cancel_session_key(&self, session_key_json: &str) -> bool {
        self.session_runtime.cancel_session_key(session_key_json)
    }

    pub fn clear_session_cancellation(&self, session_key_json: &str) {
        self.session_runtime
            .clear_session_cancellation(session_key_json);
    }

    pub fn is_session_cancelled(&self, session_key_json: &str) -> bool {
        self.session_runtime.is_session_cancelled(session_key_json)
    }

    pub(super) fn begin_session_turn(&self, session_key_json: &str) -> SessionTurnRuntime {
        self.session_runtime.begin_turn(session_key_json)
    }

    pub(super) fn is_turn_cancelled(&self, turn: &SessionTurnRuntime) -> bool {
        turn.is_cancelled(&self.session_runtime)
    }
}

pub fn normalize_agent_id(agent_id: &str) -> String {
    let trimmed = agent_id.trim();
    if trimmed.is_empty() {
        DEFAULT_AGENT_ID.to_string()
    } else {
        trimmed.to_string()
    }
}

pub(super) fn default_platform() -> String {
    if cfg!(target_os = "android") {
        "android".to_string()
    } else if cfg!(target_os = "ios") {
        "ios".to_string()
    } else {
        "unknown".to_string()
    }
}

pub(super) fn config_error_json() -> String {
    r#"{"error":"mobile runtime config error"}"#.to_string()
}

pub(super) fn default_error_config() -> PlatformLlmConfig {
    PlatformLlmConfig::default()
}

pub(super) fn parse_extra_headers(raw: Option<&str>) -> HashMap<String, String> {
    raw.unwrap_or("")
        .split(',')
        .filter_map(|pair| {
            let (key, value) = pair.split_once(':')?;
            let key = key.trim();
            let value = value.trim();
            if key.is_empty() || value.is_empty() {
                None
            } else {
                Some((key.to_string(), value.to_string()))
            }
        })
        .collect()
}
