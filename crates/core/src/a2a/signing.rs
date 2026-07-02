//! Signing helpers for trusted mobile A2A peer envelopes.

use base64::{Engine as _, engine::general_purpose::STANDARD_NO_PAD};
use rand::RngCore;
use ring::aead;
use serde_json::Value;
use sha2::{Digest, Sha256};

use super::types::{A2ADeepLinkEnvelope, A2APeerMessage, SIGNATURE_ALGORITHM_HMAC_SHA256_V1};
use crate::crypto::{
    canonical_json, constant_time_eq, hmac_sha256_base64_no_pad, sha256_base64_no_pad,
};

#[allow(dead_code)]
pub(super) fn sign_envelope(envelope: &mut A2ADeepLinkEnvelope, shared_secret: &str) {
    envelope.signature_algorithm = SIGNATURE_ALGORITHM_HMAC_SHA256_V1.to_string();
    envelope.signature = Some(hmac_sha256_base64_no_pad(
        shared_secret.as_bytes(),
        envelope_signature_payload(envelope).as_bytes(),
    ));
}

pub(super) fn verify_envelope(envelope: &A2ADeepLinkEnvelope, shared_secret: &str) -> bool {
    if envelope.signature_algorithm != SIGNATURE_ALGORITHM_HMAC_SHA256_V1 {
        return false;
    }
    let Some(signature) = envelope.signature.as_deref() else {
        return false;
    };
    constant_time_eq(
        signature,
        &hmac_sha256_base64_no_pad(
            shared_secret.as_bytes(),
            envelope_signature_payload(envelope).as_bytes(),
        ),
    )
}

pub(super) fn sign_peer_message(message: &mut A2APeerMessage, shared_secret: &str) {
    if shared_secret.trim().is_empty() {
        return;
    }
    message.signature_algorithm = SIGNATURE_ALGORITHM_HMAC_SHA256_V1.to_string();
    message.signature = Some(hmac_sha256_base64_no_pad(
        shared_secret.as_bytes(),
        peer_message_signature_payload(message).as_bytes(),
    ));
}

pub(super) fn encrypt_peer_message_payload(message: &mut A2APeerMessage, shared_secret: &str) {
    if shared_secret.trim().is_empty() || peer_message_encrypted_payload(&message.payload) {
        return;
    }
    let plaintext = canonical_json(&message.payload).into_bytes();
    let mut nonce = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce);
    let aad = peer_message_encryption_aad(message);
    let Some(ciphertext) = aes_256_gcm_seal(shared_secret, &nonce, aad.as_bytes(), &plaintext)
    else {
        return;
    };
    message.payload = serde_json::json!({
        "encrypted": {
            "algorithm": "a2a-aes-256-gcm-v1",
            "nonce": STANDARD_NO_PAD.encode(nonce),
            "payload": STANDARD_NO_PAD.encode(ciphertext),
            "aadSha256": sha256_base64_no_pad(aad.as_bytes()),
        }
    });
}

pub(super) fn decrypt_peer_message_payload(
    message: &mut A2APeerMessage,
    shared_secret: &str,
) -> bool {
    if shared_secret.trim().is_empty() {
        return false;
    }
    let Some(encrypted) = message.payload.get("encrypted").and_then(Value::as_object) else {
        return true;
    };
    let expected_aad = sha256_base64_no_pad(peer_message_encryption_aad(message).as_bytes());
    if encrypted.get("aadSha256").and_then(Value::as_str) != Some(expected_aad.as_str()) {
        return false;
    }
    let algorithm = encrypted.get("algorithm").and_then(Value::as_str);
    let Some(nonce) = encrypted
        .get("nonce")
        .and_then(Value::as_str)
        .and_then(|value| STANDARD_NO_PAD.decode(value).ok())
    else {
        return false;
    };
    let Some(ciphertext) = encrypted
        .get("payload")
        .and_then(Value::as_str)
        .and_then(|value| STANDARD_NO_PAD.decode(value).ok())
    else {
        return false;
    };
    let plaintext = match algorithm {
        Some("a2a-aes-256-gcm-v1") => {
            let Some(plaintext) = aes_256_gcm_open(
                shared_secret,
                &nonce,
                peer_message_encryption_aad(message).as_bytes(),
                &ciphertext,
            ) else {
                return false;
            };
            plaintext
        }
        Some("a2a-xor-sha256-v1") => xor_keystream(&ciphertext, shared_secret.as_bytes(), &nonce),
        _ => return false,
    };
    let Ok(value) = serde_json::from_slice::<Value>(&plaintext) else {
        return false;
    };
    message.payload = value;
    true
}

pub(super) fn peer_message_encrypted_payload(payload: &Value) -> bool {
    payload
        .get("encrypted")
        .and_then(Value::as_object)
        .is_some()
}

pub(super) fn verify_peer_message(message: &A2APeerMessage, shared_secret: &str) -> bool {
    if shared_secret.trim().is_empty() {
        return false;
    }
    if message.signature_algorithm != SIGNATURE_ALGORITHM_HMAC_SHA256_V1 {
        return false;
    }
    let Some(signature) = message.signature.as_deref() else {
        return false;
    };
    constant_time_eq(
        signature,
        &hmac_sha256_base64_no_pad(
            shared_secret.as_bytes(),
            peer_message_signature_payload(message).as_bytes(),
        ),
    )
}

fn peer_message_encryption_aad(message: &A2APeerMessage) -> String {
    [
        ("message_id", message.message_id.clone()),
        ("session_id", message.session_id.clone()),
        ("from_peer_id", message.from_peer_id.clone()),
        ("to_peer_id", message.to_peer_id.clone()),
        ("kind", format!("{:?}", message.kind)),
        ("created_at", message.created_at.clone()),
        ("expires_at", message.expires_at.clone()),
        ("nonce", message.nonce.clone()),
        ("idempotency_key", message.idempotency_key.clone()),
    ]
    .into_iter()
    .map(|(key, value)| format!("{key}={value}"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn xor_keystream(input: &[u8], secret: &[u8], nonce: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len());
    let mut counter = 0u64;
    while output.len() < input.len() {
        let mut hasher = Sha256::new();
        hasher.update(secret);
        hasher.update(nonce);
        hasher.update(counter.to_be_bytes());
        let block = hasher.finalize();
        for byte in block {
            if output.len() == input.len() {
                break;
            }
            output.push(input[output.len()] ^ byte);
        }
        counter = counter.wrapping_add(1);
    }
    output
}

fn aes_256_gcm_seal(
    shared_secret: &str,
    nonce: &[u8],
    aad: &[u8],
    plaintext: &[u8],
) -> Option<Vec<u8>> {
    let nonce = aead::Nonce::try_assume_unique_for_key(nonce).ok()?;
    let key = aead_key(shared_secret)?;
    let mut in_out = plaintext.to_vec();
    key.seal_in_place_append_tag(nonce, aead::Aad::from(aad), &mut in_out)
        .ok()?;
    Some(in_out)
}

fn aes_256_gcm_open(
    shared_secret: &str,
    nonce: &[u8],
    aad: &[u8],
    ciphertext: &[u8],
) -> Option<Vec<u8>> {
    let nonce = aead::Nonce::try_assume_unique_for_key(nonce).ok()?;
    let key = aead_key(shared_secret)?;
    let mut in_out = ciphertext.to_vec();
    let plaintext = key
        .open_in_place(nonce, aead::Aad::from(aad), &mut in_out)
        .ok()?;
    Some(plaintext.to_vec())
}

fn aead_key(shared_secret: &str) -> Option<aead::LessSafeKey> {
    let mut hasher = Sha256::new();
    hasher.update(b"agent-a2a-local-aead-v1");
    hasher.update(shared_secret.as_bytes());
    let digest = hasher.finalize();
    let unbound = aead::UnboundKey::new(&aead::AES_256_GCM, digest.as_slice()).ok()?;
    Some(aead::LessSafeKey::new(unbound))
}

pub(super) fn envelope_signature_payload(envelope: &A2ADeepLinkEnvelope) -> String {
    let task_hash = sha256_base64_no_pad(
        canonical_json(&serde_json::to_value(&envelope.task).unwrap_or(Value::Null)).as_bytes(),
    );
    let result_hash = sha256_base64_no_pad(
        canonical_json(&serde_json::to_value(&envelope.result).unwrap_or(Value::Null)).as_bytes(),
    );
    [
        ("protocol_version", envelope.protocol_version.to_string()),
        ("envelope_id", envelope.envelope_id.clone()),
        ("kind", format!("{:?}", envelope.kind)),
        ("sender_agent_id", envelope.sender.agent_id.clone()),
        ("sender_peer_id", envelope.sender.peer_id.clone()),
        ("recipient_agent_id", recipient_agent_id(envelope)),
        ("task_sha256", task_hash),
        ("result_sha256", result_hash),
        ("created_at", envelope.created_at.clone()),
        ("expires_at", envelope.expires_at.clone()),
        ("nonce", envelope.nonce.clone()),
        ("idempotency_key", envelope.idempotency_key.clone()),
    ]
    .into_iter()
    .map(|(key, value)| format!("{key}={value}"))
    .collect::<Vec<_>>()
    .join("\n")
}

pub(super) fn peer_message_signature_payload(message: &A2APeerMessage) -> String {
    let payload_hash = sha256_base64_no_pad(canonical_json(&message.payload).as_bytes());
    [
        ("message_id", message.message_id.clone()),
        ("session_id", message.session_id.clone()),
        ("from_peer_id", message.from_peer_id.clone()),
        ("to_peer_id", message.to_peer_id.clone()),
        ("kind", format!("{:?}", message.kind)),
        ("created_at", message.created_at.clone()),
        ("expires_at", message.expires_at.clone()),
        ("nonce", message.nonce.clone()),
        ("idempotency_key", message.idempotency_key.clone()),
        ("payload_sha256", payload_hash),
    ]
    .into_iter()
    .map(|(key, value)| format!("{key}={value}"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn recipient_agent_id(envelope: &A2ADeepLinkEnvelope) -> String {
    envelope
        .recipient
        .as_ref()
        .map(|party| party.agent_id.clone())
        .unwrap_or_default()
}
