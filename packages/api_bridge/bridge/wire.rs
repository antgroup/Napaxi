//! Bridge-side helpers for translating `CoreResult<T>` from the typed core
//! API into the legacy FRB return shapes (`String`/`bool`/raw value) that
//! `packages/flutter` already consumes.
//!
//! Two design goals:
//!
//! 1. Bridge call sites stay one line. `wire_bool_unit(typed_call(..))`
//!    replaces the `match { Ok => true, Err => { tracing::error!(..); false } }`
//!    boilerplate.
//! 2. Errors that today get logged-and-dropped get a structured wire envelope
//!    instead. `wire_string_or_envelope` returns either the success JSON or
//!    `{"error":{"code":"...","message":"..."}}`, which the Dart side can
//!    detect by parsing and checking for the `error` key. Dart-side adoption
//!    is opt-in — `wire_string_or_default` is the strict-back-compat variant.
//!
//! All wrappers accept `Result<T, E> where E: Into<CoreError>` so they work
//! uniformly across already-typed callers (`CoreResult<T>`) and not-yet-typed
//! callers (`anyhow::Result<T>`). The lift goes through
//! `CoreError::Other(anyhow::Error)` for the latter.

use napaxi_core::api::error::CoreError;

/// Bool wrapper for `Result<(), E>` returns. `Ok` becomes `true`; `Err` is
/// lifted to `CoreError`, logged with structured `code`/`error` fields, and
/// becomes `false`.
pub(crate) fn wire_bool_unit<E>(op: &'static str, result: Result<(), E>) -> bool
where
    E: Into<CoreError>,
{
    match result {
        Ok(()) => true,
        Err(error) => {
            log_error(op, &error.into());
            false
        }
    }
}

/// Bool wrapper for `Result<bool, E>` (e.g. `cancel_session`, where
/// `Ok(false)` is a meaningful "already inactive" signal). `Err` collapses
/// to `false` after a structured log.
pub(crate) fn wire_bool<E>(op: &'static str, result: Result<bool, E>) -> bool
where
    E: Into<CoreError>,
{
    match result {
        Ok(value) => value,
        Err(error) => {
            log_error(op, &error.into());
            false
        }
    }
}

/// `i64` wrapper for `Result<i64, E>` (e.g. `create_engine`). `Err` returns
/// `0` (the legacy "invalid handle" sentinel) after a structured log.
pub(crate) fn wire_i64<E>(op: &'static str, result: Result<i64, E>) -> i64
where
    E: Into<CoreError>,
{
    match result {
        Ok(value) => value,
        Err(error) => {
            log_error(op, &error.into());
            0
        }
    }
}

/// String wrapper that emits the wire error envelope on failure. Forward-
/// compatible shape; Dart can parse and branch on `error.code` once adopted.
#[allow(dead_code)]
pub(crate) fn wire_string_or_envelope<E>(op: &'static str, result: Result<String, E>) -> String
where
    E: Into<CoreError>,
{
    match result {
        Ok(value) => value,
        Err(error) => {
            let core: CoreError = error.into();
            log_error(op, &core);
            core.to_wire_json()
        }
    }
}

/// String wrapper that preserves a legacy default (`""` or caller-supplied
/// fallback) on error. Use when Dart treats the empty/default return as
/// "no data" and cannot adopt the envelope shape in the same change.
pub(crate) fn wire_string_or_default<E>(
    op: &'static str,
    result: Result<String, E>,
    fallback: &str,
) -> String
where
    E: Into<CoreError>,
{
    match result {
        Ok(value) => value,
        Err(error) => {
            log_error(op, &error.into());
            fallback.to_string()
        }
    }
}

fn log_error(op: &'static str, error: &CoreError) {
    tracing::warn!(op, code = error.code(), error = %error, "bridge call failed");
}

#[cfg(test)]
mod tests {
    use super::*;
    use napaxi_core::api::error::{CoreResult, StorageError};

    #[test]
    fn wire_bool_unit_maps_ok_to_true_and_err_to_false() {
        assert!(wire_bool_unit::<CoreError>("noop", Ok(())));
        let err: CoreResult<()> = Err(StorageError::NotFound("/x".into()).into());
        assert!(!wire_bool_unit("delete", err));
    }

    #[test]
    fn wire_bool_passes_inner_value_through() {
        assert!(wire_bool::<CoreError>("cancel", Ok(true)));
        assert!(!wire_bool::<CoreError>("cancel", Ok(false)));
        let err: CoreResult<bool> = Err(CoreError::InvalidHandle(0));
        assert!(!wire_bool("cancel", err));
    }

    #[test]
    fn wire_i64_returns_zero_on_error() {
        assert_eq!(wire_i64::<CoreError>("create", Ok(42)), 42);
        let err: CoreResult<i64> = Err(CoreError::Config("bad".into()));
        assert_eq!(wire_i64("create", err), 0);
    }

    #[test]
    fn wire_i64_accepts_anyhow_through_other_lift() {
        let err: anyhow::Result<i64> = Err(anyhow::anyhow!("legacy boom"));
        assert_eq!(wire_i64("create", err), 0);
    }

    #[test]
    fn wire_string_or_envelope_emits_error_shape() {
        let err: CoreResult<String> = Err(CoreError::InvalidHandle(7));
        let out = wire_string_or_envelope("get_config", err);
        assert!(out.contains(r#""code":"invalid_handle""#));
        assert!(out.contains("7"));
    }

    #[test]
    fn wire_string_or_default_uses_fallback() {
        let err: CoreResult<String> = Err(CoreError::InvalidHandle(0));
        assert_eq!(wire_string_or_default("list", err, "[]"), "[]");
        assert_eq!(
            wire_string_or_default::<CoreError>("list", Ok("ok".into()), "[]"),
            "ok"
        );
    }
}
