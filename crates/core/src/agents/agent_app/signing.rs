//! HMAC-SHA256 signing of action proposals and agent triggers.
//!
//! Proposals and triggers are signed with the host shared secret bound
//! into the agent app install binding. Verification on the provider side
//! re-derives the same canonical payload, so the host and provider must
//! agree on the exact field-order rules below. The HMAC, SHA-256, and
//! canonical-JSON primitives are shared with the A2A signing path; they live
//! in [`crate::crypto`].

use crate::crypto::{canonical_json, hmac_sha256_base64_no_pad, sha256_base64_no_pad};

use super::SIGNATURE_ALGORITHM_HMAC_SHA256_V1;
use super::types::{ActionProposal, AgentAppInstallBinding, AgentTriggerRequest};

pub(super) fn sign_proposal_if_possible(
    proposal: &mut ActionProposal,
    binding: Option<&AgentAppInstallBinding>,
) {
    let Some(binding) = binding else {
        return;
    };
    if binding.host_shared_secret.trim().is_empty() || binding.host_instance_id.trim().is_empty() {
        return;
    }
    proposal.host_instance_id = binding.host_instance_id.clone();
    proposal.signature_algorithm = SIGNATURE_ALGORITHM_HMAC_SHA256_V1.to_string();
    proposal.signature = Some(hmac_sha256_base64_no_pad(
        binding.host_shared_secret.as_bytes(),
        proposal_signature_payload(proposal).as_bytes(),
    ));
}

pub(super) fn proposal_signature_payload(proposal: &ActionProposal) -> String {
    let arguments_canonical = canonical_json(&proposal.arguments);
    let arguments_hash = sha256_base64_no_pad(arguments_canonical.as_bytes());
    [
        ("request_id", proposal.request_id.as_str()),
        ("provider_id", proposal.provider_id.as_str()),
        ("agent_id", proposal.agent_id.as_str()),
        ("action_id", proposal.action_id.as_str()),
        ("tool_name", proposal.tool_name.as_str()),
        ("arguments_sha256", arguments_hash.as_str()),
        ("created_at", proposal.created_at.as_str()),
        ("expires_at", proposal.expires_at.as_str()),
        ("nonce", proposal.nonce.as_str()),
        ("idempotency_key", proposal.idempotency_key.as_str()),
        ("risk", proposal.risk.as_str()),
        ("confirmation_policy", proposal.confirmation_policy.as_str()),
        ("host_instance_id", proposal.host_instance_id.as_str()),
    ]
    .into_iter()
    .map(|(key, value)| format!("{key}={value}"))
    .collect::<Vec<_>>()
    .join("\n")
}

pub(super) fn trigger_signature_payload(trigger: &AgentTriggerRequest) -> String {
    let payload_canonical = canonical_json(&trigger.payload);
    let payload_hash = sha256_base64_no_pad(payload_canonical.as_bytes());
    [
        ("request_id", trigger.request_id.as_str()),
        ("provider_id", trigger.provider_id.as_str()),
        ("agent_id", trigger.agent_id.as_str()),
        ("message", trigger.message.as_str()),
        ("source", trigger.source.as_str()),
        ("event_type", trigger.event_type.as_str()),
        ("payload_sha256", payload_hash.as_str()),
        ("created_at", trigger.created_at.as_str()),
        ("expires_at", trigger.expires_at.as_str()),
        ("nonce", trigger.nonce.as_str()),
        ("idempotency_key", trigger.idempotency_key.as_str()),
        ("host_instance_id", trigger.host_instance_id.as_str()),
    ]
    .into_iter()
    .map(|(key, value)| format!("{key}={value}"))
    .collect::<Vec<_>>()
    .join("\n")
}
