//! Provider-side trigger acceptance: parse a v2 [`AgentTriggerRequest`],
//! verify its HMAC signature against the trusted install binding, and
//! persist the consumed-trigger record.
//!
//! Split out of [`super`] (the agent_app runtime) so that the agent_app
//! module stays under the workspace's per-file line budget enforced by the
//! `check-boundary` gate. The acceptance contract is unchanged; only its
//! physical location moved. The signature payload is computed via
//! [`super::signing::trigger_signature_payload`], which dispatches on the
//! trigger's `signature_protocol_version` (`canonical-json-minv1` / v2 by
//! default, legacy v1 retained for re-verifying stored records).

use super::persistence::{load_package, load_trigger_record, save_trigger_record};
use super::signing::trigger_signature_payload;
use super::types::{AgentTriggerRecord, AgentTriggerRequest, now};
use super::{SIGNATURE_ALGORITHM_HMAC_SHA256_V1, error_json};
use crate::crypto::{constant_time_eq, hmac_sha256_base64_no_pad};
use chrono::{DateTime, Utc};

pub fn accept_trigger(files_dir: &str, trigger_json: &str) -> String {
    let trigger = match serde_json::from_str::<AgentTriggerRequest>(trigger_json) {
        Ok(trigger) => trigger,
        Err(error) => return error_json(format!("Invalid agent app trigger: {error}")),
    };
    if trigger.protocol_version < 2 {
        return error_json("agent app trigger protocol v2 is required");
    }
    if trigger.request_id.trim().is_empty()
        || trigger.provider_id.trim().is_empty()
        || trigger.agent_id.trim().is_empty()
        || trigger.message.trim().is_empty()
        || trigger.nonce.trim().is_empty()
        || trigger.idempotency_key.trim().is_empty()
    {
        return error_json("agent app trigger missing required fields");
    }
    if trigger_is_expired(&trigger) {
        return error_json("agent app trigger expired");
    }
    if load_trigger_record(files_dir, &trigger.request_id).is_some() {
        return error_json("agent app trigger already consumed");
    }
    let Some(package) = load_package(files_dir, &trigger.provider_id)
        .or_else(|| load_package(files_dir, &trigger.agent_id))
    else {
        return error_json("triggered agent app package not found");
    };
    if package.provider_id != trigger.provider_id {
        return error_json("agent app trigger provider mismatch");
    }
    let Some(binding) = package.install_binding.as_ref() else {
        return error_json("agent app trigger package has no trusted binding");
    };
    if binding.host_instance_id.trim().is_empty()
        || binding.host_shared_secret.trim().is_empty()
        || binding.host_instance_id != trigger.host_instance_id
    {
        return error_json("agent app trigger is not bound to this host");
    }
    if trigger.signature_algorithm != SIGNATURE_ALGORITHM_HMAC_SHA256_V1
        || trigger
            .signature
            .as_ref()
            .map(|value| value.trim().is_empty())
            .unwrap_or(true)
    {
        return error_json("agent app trigger missing trusted signature fields");
    }
    let expected = hmac_sha256_base64_no_pad(
        binding.host_shared_secret.as_bytes(),
        trigger_signature_payload(&trigger).as_bytes(),
    );
    if !trigger
        .signature
        .as_deref()
        .is_some_and(|sig| constant_time_eq(sig, &expected))
    {
        return error_json("agent app trigger signature is invalid");
    }
    let timestamp = now();
    let record = AgentTriggerRecord {
        trigger,
        status: "accepted".to_string(),
        created_at: timestamp.clone(),
        updated_at: timestamp,
    };
    if !save_trigger_record(files_dir, &record) {
        return error_json("Failed to save agent app trigger");
    }
    serde_json::to_string(&record).unwrap_or_else(|_| error_json("Failed to serialize trigger"))
}

pub fn accept_trigger_handle(handle: i64, trigger_json: &str) -> String {
    let Some(files_dir) = crate::runtime::files_dir_from_handle(handle) else {
        return error_json("invalid engine handle");
    };
    accept_trigger(&files_dir, trigger_json)
}

/// A trigger whose `expires_at` cannot be parsed, or whose expiry is in the
/// past, is rejected. Fail-closed: a malformed timestamp is treated as
/// expired so a trigger cannot bypass the freshness check by emitting a
/// non-RFC-3339 string.
fn trigger_is_expired(trigger: &AgentTriggerRequest) -> bool {
    DateTime::parse_from_rfc3339(&trigger.expires_at)
        .map(|expires_at| Utc::now() > expires_at.with_timezone(&Utc))
        .unwrap_or(true)
}
