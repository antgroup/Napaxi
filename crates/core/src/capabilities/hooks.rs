//! Capability admission policy hook chain.
//!
//! Hooks are registered into a process-global `Mutex<Vec<RegisteredHook>>`
//! and consulted from [`super::admission::admit_typed`]. Tests install
//! scoped hooks via the RAII [`PolicyHookGuard`]; the chain is shared
//! across the process, so adapter code installs at most one chain-wide
//! hook per integration.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use super::types::{CapabilityAdmission, CapabilityAdmissionDecision};

pub type CapabilityPolicyHook =
    Arc<dyn Fn(&CapabilityAdmission) -> CapabilityAdmissionDecision + Send + Sync + 'static>;

#[derive(Clone)]
pub(super) struct RegisteredHook {
    pub(super) id: u64,
    pub(super) hook: CapabilityPolicyHook,
}

pub(super) fn policy_hooks() -> &'static Mutex<Vec<RegisteredHook>> {
    static HOOKS: OnceLock<Mutex<Vec<RegisteredHook>>> = OnceLock::new();
    HOOKS.get_or_init(|| Mutex::new(Vec::new()))
}

fn next_hook_id() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    NEXT.fetch_add(1, Ordering::Relaxed)
}

/// RAII handle returned by [`register_policy_hook`]. The hook is removed from
/// the global policy chain when this guard is dropped, so tests and adapter
/// code can install scoped hooks without polluting other call sites.
///
/// Drop is a no-op if the hook was already removed manually via
/// [`PolicyHookGuard::deregister`].
#[must_use = "policy hooks are removed when the guard is dropped; bind it"]
pub struct PolicyHookGuard {
    id: u64,
    armed: bool,
}

impl PolicyHookGuard {
    /// Remove the hook explicitly. Idempotent. The guard's `Drop` impl is a
    /// no-op after this call.
    pub fn deregister(mut self) {
        deregister_policy_hook(self.id);
        self.armed = false;
    }
}

impl Drop for PolicyHookGuard {
    fn drop(&mut self) {
        if self.armed {
            deregister_policy_hook(self.id);
        }
    }
}

/// Register a capability admission policy hook. The hook is called for every
/// `admit_*` decision (tool descriptor, tool invocation, LLM provider) and can
/// `Deny` to short-circuit the chain.
///
/// Returns a [`PolicyHookGuard`] that removes the hook when dropped — bind it
/// to a variable (or call [`PolicyHookGuard::deregister`]) to control lifetime.
/// Multiple hooks are evaluated in registration order; the first `Deny` wins.
///
/// ```no_run
/// use std::sync::Arc;
/// use napaxi_core::api::capability::{
///     register_policy_hook, CapabilityAdmissionDecision, CapabilityAdmissionKind,
/// };
///
/// // Deny any provider whose subject starts with `external_`; allow everything else.
/// let guard = register_policy_hook(Arc::new(|admission| {
///     if matches!(admission.kind, CapabilityAdmissionKind::Provider)
///         && admission.subject.starts_with("external_")
///     {
///         CapabilityAdmissionDecision::Deny("external providers blocked".into())
///     } else {
///         CapabilityAdmissionDecision::Allow
///     }
/// }));
///
/// // The hook is active until `guard` is dropped; drop early to remove it.
/// guard.deregister();
/// ```
pub fn register_policy_hook(hook: CapabilityPolicyHook) -> PolicyHookGuard {
    let id = next_hook_id();
    if let Ok(mut hooks) = policy_hooks().lock() {
        hooks.push(RegisteredHook { id, hook });
    }
    PolicyHookGuard { id, armed: true }
}

fn deregister_policy_hook(id: u64) {
    if let Ok(mut hooks) = policy_hooks().lock() {
        hooks.retain(|h| h.id != id);
    }
}

#[cfg(test)]
pub(crate) fn set_policy_hooks_for_tests(hooks: Vec<CapabilityPolicyHook>) {
    let mut guard = policy_hooks().lock().expect("policy hook lock");
    *guard = hooks
        .into_iter()
        .map(|hook| RegisteredHook {
            id: next_hook_id(),
            hook,
        })
        .collect();
}
