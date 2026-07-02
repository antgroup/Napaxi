//! Per-tool sliding-window rate limiter shared by all registries.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use std::sync::LazyLock;

use super::types::ToolRateLimit;

pub(super) static MOBILE_TOOL_RATE_LIMITER: LazyLock<ToolRateLimiter> =
    LazyLock::new(ToolRateLimiter::default);

pub(super) const DEFAULT_TOOL_RATE_LIMIT: ToolRateLimit = ToolRateLimit {
    max_calls: 120,
    window: Duration::from_secs(300),
};
pub(super) const SHELL_TOOL_RATE_LIMIT: ToolRateLimit = ToolRateLimit {
    max_calls: 300,
    window: Duration::from_secs(300),
};
pub(super) const MUTATING_TOOL_RATE_LIMIT: ToolRateLimit = ToolRateLimit {
    max_calls: 40,
    window: Duration::from_secs(300),
};

#[derive(Default)]
pub(super) struct ToolRateLimiter {
    calls: Mutex<HashMap<String, VecDeque<Instant>>>,
}

impl ToolRateLimiter {
    pub(super) fn check(&self, tool_name: &str, limit: ToolRateLimit) -> Result<(), String> {
        self.check_at(tool_name, limit, Instant::now())
    }

    pub(super) fn check_at(
        &self,
        tool_name: &str,
        limit: ToolRateLimit,
        now: Instant,
    ) -> Result<(), String> {
        if limit.max_calls == 0 {
            return Err(format!("Tool '{tool_name}' is disabled by rate limit"));
        }

        let mut calls = self
            .calls
            .lock()
            .map_err(|e| format!("Lock poisoned: {e}"))?;
        let entries = calls.entry(tool_name.to_string()).or_default();
        while let Some(oldest) = entries.front().copied() {
            if now.duration_since(oldest) <= limit.window {
                break;
            }
            entries.pop_front();
        }
        if entries.len() >= limit.max_calls {
            return Err(format!(
                "Tool '{tool_name}' rate limit exceeded: max {} calls per {}s",
                limit.max_calls,
                limit.window.as_secs()
            ));
        }
        entries.push_back(now);
        Ok(())
    }
}

pub(super) fn rate_limit_for_tool(tool_name: &str) -> ToolRateLimit {
    match tool_name {
        "shell" => SHELL_TOOL_RATE_LIMIT,
        "memory_write"
        | "memory_append"
        | "profile_write"
        | "skill_install"
        | "skill_remove"
        | "skill_apply_evolution"
        | "group_create"
        | "group_update"
        | "group_delete" => MUTATING_TOOL_RATE_LIMIT,
        _ => DEFAULT_TOOL_RATE_LIMIT,
    }
}

pub fn check_tool_rate_limit(tool_name: &str) -> Result<(), String> {
    MOBILE_TOOL_RATE_LIMITER.check(tool_name, rate_limit_for_tool(tool_name))
}
