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

/// Signature protocol version 1: the legacy canonical-JSON form used by
/// the first agent-app deployments. Strings serialize via
/// `serde_json::to_string` (no `/` escape) and numbers render via
/// `serde_json::Number::Display`. Kept only so historical stored
/// proposals whose `signature_protocol_version == 1` can be re-verified
/// byte-for-byte without silent drift.
pub(crate) const SIGNATURE_PROTOCOL_VERSION_V1: u32 = 1;

/// Signature protocol version 2: the canonical-JSON form named
/// `canonical-json-minv1` in the shared fixtures (AOSP `org.json`-compatible).
/// Strings escape `/` as `\/`, control code points as lowercase `\u00xx`,
/// integers fitting `i64` render as decimal digits, and everything else
/// follows Java `Double.toString`. New proposals and triggers are signed at
/// this version; providers that only speak v1 are rejected as
/// `protocol_incompatible` rather than silently relaxed.
pub(crate) const SIGNATURE_PROTOCOL_VERSION_V2: u32 = 2;

/// Canonical JSON serialized for a specific signature-protocol version.
///
/// Host and provider must agree on the version before signing or
/// verifying, since the version selects the canonical byte form. New
/// code should pass [`SIGNATURE_PROTOCOL_VERSION_V2`]; verification of
/// a stored legacy payload must use version 1 (or [`canonical_json_v1`]).
pub(crate) fn canonical_json_for_signature(value: &Value, version: u32) -> String {
    if version <= SIGNATURE_PROTOCOL_VERSION_V1 {
        canonical_json_v1(value)
    } else {
        canonical_json(value)
    }
}

/// Legacy canonical-JSON form (signature-protocol version 1).
///
/// Object keys are sorted lexicographically; strings serialize via
/// `serde_json::to_string`, which does not escape `/` and emits
/// `serde_json`'s default number rendering. Kept for byte-for-byte
/// verification of historical stored proposals; new code must use
/// [`canonical_json`] (version 2). The legacy path silently replaces
/// serialization failures with `""`, matching the historical behavior.
pub(crate) fn canonical_json_v1(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string()),
        Value::Array(values) => format!(
            "[{}]",
            values
                .iter()
                .map(canonical_json_v1)
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
                        canonical_json_v1(value)
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
    }
}
/// Deterministic, canonical-JSON serialization for signing
/// (`canonical-json-minv1`).
///
/// Object keys are sorted lexicographically and there is no insignificant
/// whitespace, so the host and provider derive byte-identical payloads from
/// the same logical value regardless of map iteration order.
///
/// Strings are escaped exactly like AOSP `org.json.JSONObject.quote`:
/// `"` and `\` are escaped; the five named controls `\b\f\n\r\t` use their
/// lowercase-name escape; every other code point below U+0020 uses lowercase
/// `\u00xx`; `/` is escaped as `\/`; everything else (CJK, emoji incl. ZWJ,
/// U+2028/U+2029, U+FEFF, U+007F) is emitted as raw UTF-8. The business
/// string is never rewritten — `10/22`, `元/吨`, URLs, Markdown and newlines
/// must round-trip byte-for-byte.
///
/// Numbers use Java `Double.toString` rules: integers that fit in `i64`
/// render as decimal digits; everything else parses as a double and renders
/// as Java would (decimal below `1e7` and at/above `1e-3`, scientific `E`
/// form otherwise, mantissa always carrying a fractional digit, exponent
/// without a leading `+`). This matches the Android/iOS provider
/// implementations byte-for-byte; the cross-platform contract is pinned by
/// `packages/agent_provider/shared/signing_fixtures.json`.
pub(crate) fn canonical_json(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => canonical_number(value),
        Value::String(value) => canonical_string(value),
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
                        canonical_string(key),
                        canonical_json(value)
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            )
        }
    }
}

/// String escaping per `canonical-json-minv1` (mirrors AOSP
/// `org.json.JSONObject.quote`). The input string is treated as raw UTF-8
/// bytes; no business character (`/`, CJK, emoji, …) is rewritten — only the
/// JSON-level escape rules above are applied.
fn canonical_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{0008}' => out.push_str("\\b"),
            '\u{000C}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '/' => out.push_str("\\/"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Number serialization per `canonical-json-minv1` (mirrors Java
/// `Double.toString` for non-`i64`-fitting numbers, matching AOSP org.json).
fn canonical_number(value: &serde_json::Number) -> String {
    if value.is_i64() {
        // `is_i64()` already proved the `i64` accessor succeeds; `expect` keeps
        // the panic message actionable without relaxing the `unwrap_used` lint.
        return value
            .as_i64()
            .expect("serde_json Number::is_i64() guarantees as_i64() is Some")
            .to_string();
    }
    if value.is_u64() {
        // u64-only integers (i64::MAX < value <= u64::MAX) round-trip through
        // Java Double.toString in org.json, losing precision but matching the
        // shared fixture bytes.
        return format_double_java(
            value
                .as_u64()
                .expect("serde_json Number::is_u64() guarantees as_u64() is Some")
                as f64,
        );
    }
    if value.is_f64() {
        return format_double_java(
            value
                .as_f64()
                .expect("serde_json Number::is_f64() guarantees as_f64() is Some"),
        );
    }
    // Defensive fallback: an unknown variant should not exist in `serde_json`
    // today, but never silently substitute — emit whatever the underlying
    // number prints so a mismatch is observable rather than masked.
    value.to_string()
}

/// Format `value` like Java's `Double.toString`. Used by the canonical-JSON
/// serializer for any number that is not an `i64`-fitting integer literal.
fn format_double_java(value: f64) -> String {
    // NaN/Infinity cannot round-trip through JSON; org.json emits them as
    // "null"/strings but no fixture uses them. Fall back to Display so the
    // output stays a single JSON token and never silently succeeds a sign.
    if value.is_nan() || value.is_infinite() {
        return format!("{value}");
    }
    if value == 0.0 {
        return if value.is_sign_negative() {
            "-0.0".to_string()
        } else {
            "0.0".to_string()
        };
    }
    let abs = value.abs();
    // Java Double.toString: decimal form when 1e-3 <= |x| < 1e7, otherwise
    // scientific with uppercase `E` and no leading `+`/zero on the exponent.
    if (1e-3..1e7).contains(&abs) {
        let s = format!("{value}");
        if !s.contains('.') && !s.contains('e') && !s.contains('E') {
            format!("{s}.0")
        } else {
            s
        }
    } else {
        // `{:e}` produces `<mantissa>e<exp>` with the shortest mantissa that
        // round-trips, e.g. "1e7", "1.5e-10", "9.223372036854776e18".
        let s = format!("{value:e}");
        let (mantissa, exponent) = s
            .split_once('e')
            .expect("finite non-zero f64 always serializes with an exponent via {:e}");
        let mantissa = if mantissa.contains('.') {
            mantissa.to_string()
        } else {
            format!("{mantissa}.0")
        };
        let exponent: i32 = exponent
            .parse()
            .expect("Rust {:e} exponent is a signed integer");
        format!("{mantissa}E{exponent}")
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

    #[test]
    fn canonical_json_escapes_slash_per_canonical_json_minv1() {
        // The 2026-11-03 signature_invalid root cause: serde_json does not
        // escape `/`, but AOSP org.json (and the shared fixture contract)
        // does. A slash in the business string must round-trip unchanged
        // after parsing while serializing to `\/` for signing.
        let value = json!("10/22");
        assert_eq!(canonical_json(&value), r#""10\/22""#);
        assert_eq!(
            sha256_base64_no_pad(canonical_json(&value).as_bytes()),
            "Z2vsKlSky1Ry62usAWhybVrc+YEaIwrvvzsk7L5Nd/k"
        );

        // Symbol/unit with CJK + slash stays raw CJK and escapes the slash.
        let value = json!("元/吨");
        assert_eq!(canonical_json(&value), r#""元\/吨""#);

        // URL: every slash escaped, ampersand and other ASCII punctuation raw.
        let value = json!("https://napaxi.example.com/a/b?c=1&d=2");
        assert_eq!(
            canonical_json(&value),
            r#""https:\/\/napaxi.example.com\/a\/b?c=1&d=2""#
        );
    }
}
