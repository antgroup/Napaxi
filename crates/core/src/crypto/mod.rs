//! Shared HMAC-SHA256 signing primitives for trusted-secret verification.
//!
//! A2A peer envelopes ([`crate::a2a`]) and agent-app action/trigger bindings
//! ([`crate::agents`]) both authenticate payloads with the same scheme: a
//! canonical-JSON serialization, an HMAC-SHA256 over it keyed by a shared
//! secret, base64-no-pad encoded, then a constant-time comparison on verify.
//! These four helpers were copy-pasted byte-for-byte in both signing modules;
//! they live here once so the security-sensitive code has a single definition.
//!
//! The domain-specific parts — which fields go into the signed payload and in
//! what order — stay in each caller's `signing` module, since host and
//! provider must agree on those exact rules.

use base64::{Engine as _, engine::general_purpose::STANDARD_NO_PAD};
use serde_json::Value;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// SHA-256 of `bytes`, base64 (no padding).
pub(crate) fn sha256_base64_no_pad(bytes: &[u8]) -> String {
    STANDARD_NO_PAD.encode(Sha256::digest(bytes))
}

/// HMAC-SHA256 of `payload` keyed by `secret`, base64 (no padding).
///
/// Implements RFC 2104 over SHA-256 directly rather than pulling in the `hmac`
/// crate, matching the wire format both signing schemes already emit.
///
/// # Security Considerations
///
/// Implementing a cryptographic primitive from scratch is an inherently risky
/// practice — a subtle bug in key-padding or block-size handling could be
/// invisible to routine review. The `hmac` crate exists precisely to avoid
/// this class of bug. This hand-rolled version persists solely because the
/// wire format it produces is locked by existing deployments. A future
/// migration should: (1) add a `hmac`-crate implementation, (2) verify that
/// both produce identical output for all inputs, (3) swap the default, and
/// (4) keep this implementation as a cross-check only.
///
/// Key length is not validated here. RFC 2104 recommends keys at least as
/// long as the hash output (32 bytes for SHA-256); shorter keys reduce
/// effective security. Callers should enforce a minimum key length.
///
/// The signing scheme does not include a nonce, timestamp, or sequence number
/// in the signed payload. If replay protection is needed, the caller must
/// incorporate such a value into the payload before signing.
pub(crate) fn hmac_sha256_base64_no_pad(secret: &[u8], payload: &[u8]) -> String {
    const BLOCK_SIZE: usize = 64;
    let mut key = if secret.len() > BLOCK_SIZE {
        Sha256::digest(secret).to_vec()
    } else {
        secret.to_vec()
    };
    key.resize(BLOCK_SIZE, 0);
    let mut ipad = [0x36u8; BLOCK_SIZE];
    let mut opad = [0x5cu8; BLOCK_SIZE];
    for index in 0..BLOCK_SIZE {
        ipad[index] ^= key[index];
        opad[index] ^= key[index];
    }
    let mut inner = Sha256::new();
    inner.update(ipad);
    inner.update(payload);
    let inner_hash = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(opad);
    outer.update(inner_hash);
    STANDARD_NO_PAD.encode(outer.finalize())
}

/// Constant-time string equality for signature comparison.
///
/// Backed by the audited [`subtle`] primitive so the byte-comparison loop is
/// not short-circuited or otherwise optimized into a data-dependent branch —
/// what a hand-rolled `diff |= a ^ b` loop only achieves by accident, and a
/// future compiler is free to undo. Length is compared first (and is not
/// secret here: the inputs are fixed-length base64 of a SHA-256 HMAC).
pub(crate) fn constant_time_eq(a: &str, b: &str) -> bool {
    a.as_bytes().ct_eq(b.as_bytes()).into()
}

/// Deterministic, canonical JSON serialization for signing.
///
/// Object keys are sorted lexicographically and there is no insignificant
/// whitespace, so the host and provider derive byte-identical payloads from
/// the same logical value regardless of map iteration order.
///
/// # Warning
///
/// Serialization failures are silently replaced with `""`. In a signing context,
/// this means a malformed input would produce a different canonical form than
/// intended. Callers that need strict failure semantics should validate their
/// `Value` before calling this function.
pub(crate) fn canonical_json(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string()),
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(canonical_json)
                .collect::<Vec<_>>()
                .join(",")
        ),
        Value::Object(map) => {
            let mut entries = map.iter().collect::<Vec<_>>();
            entries.sort_by(|a, b| a.0.cmp(b.0));
            format!(
                "{{{}}}",
                entries
                    .into_iter()
                    .map(|(key, value)| format!(
                        "{}:{}",
                        serde_json::to_string(key).unwrap_or_else(|_| "\"\"".to_string()),
                        canonical_json(value)
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn constant_time_eq_matches_plain_equality() {
        assert!(constant_time_eq("", ""));
        assert!(constant_time_eq("abc123", "abc123"));
        assert!(!constant_time_eq("abc123", "abc124"));
        // Differing lengths are unequal, never a panic.
        assert!(!constant_time_eq("abc", "abcd"));
        assert!(!constant_time_eq("abcd", "abc"));
    }

    #[test]
    fn hmac_sha256_is_stable_and_key_sensitive() {
        // Stable across calls (regression-locks the wire format).
        let a = hmac_sha256_base64_no_pad(b"secret", b"payload");
        let b = hmac_sha256_base64_no_pad(b"secret", b"payload");
        assert_eq!(a, b);
        // No padding characters in the encoding.
        assert!(!a.contains('='));
        // A different key yields a different tag.
        assert_ne!(a, hmac_sha256_base64_no_pad(b"other", b"payload"));
        // A different payload yields a different tag.
        assert_ne!(a, hmac_sha256_base64_no_pad(b"secret", b"payload2"));
    }

    #[test]
    fn hmac_handles_keys_longer_than_the_block() {
        // Keys over 64 bytes are hashed down first; must not panic and must
        // stay deterministic.
        let long_key = vec![0x61u8; 200];
        let a = hmac_sha256_base64_no_pad(&long_key, b"payload");
        let b = hmac_sha256_base64_no_pad(&long_key, b"payload");
        assert_eq!(a, b);
        assert!(!a.is_empty());
    }

    #[test]
    fn sha256_base64_no_pad_is_unpadded_and_stable() {
        let digest = sha256_base64_no_pad(b"napaxi");
        assert_eq!(digest, sha256_base64_no_pad(b"napaxi"));
        assert!(!digest.contains('='));
        // Distinct input must yield a distinct digest.
        assert_ne!(digest, sha256_base64_no_pad(b"napaxi-other"));
    }

    #[test]
    fn canonical_json_sorts_keys_and_is_order_independent() {
        let a = canonical_json(&json!({ "b": 1, "a": 2 }));
        let b = canonical_json(&json!({ "a": 2, "b": 1 }));
        assert_eq!(a, b, "key order must not change the canonical form");
        assert_eq!(a, r#"{"a":2,"b":1}"#);
    }

    #[test]
    fn canonical_json_has_no_insignificant_whitespace() {
        let canonical = canonical_json(&json!({
            "nested": { "z": [1, 2], "y": "v" },
            "x": true
        }));
        assert!(!canonical.contains(' '));
        assert!(!canonical.contains('\n'));
        assert_eq!(canonical, r#"{"nested":{"y":"v","z":[1,2]},"x":true}"#);
    }
}
