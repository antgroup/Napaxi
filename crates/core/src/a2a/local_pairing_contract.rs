//! Local A2A pairing wire-shape contract.
//!
//! These constants pin the *cross-device* and *cross-adapter* wire shapes used
//! by the local pairing + task flow. The durable models (peers, tasks,
//! messages, delivery records) and the cryptographic derivation already live in
//! Rust core and `A2APairing`; what was previously *only* string literals in
//! the Flutter demo were the small, drift-prone surface pieces:
//!
//! - the QR invite payload prefix,
//! - the invite-code JSON field names, and
//! - the task direction / pending / active classification rules.
//!
//! Re-export this module through `napaxi_core::api::a2a` so the Flutter, Android,
//! and iOS adapters bind ONE source of truth instead of hand-copying literals.
//! Per `docs/sdk-adapter-parity.md`, shared host behavior must be contracted in
//! core before it is reimplemented per platform; this is that contract for the
//! local-pairing surface.
//!
//! Changing any value here is a wire-compat break: bump the invite `version`
//! and update every adapter together.

use super::types::{A2ADeliveryStatus, A2AMessageKind, A2ATaskStatus};

/// QR / deep-link payload prefix for a local pairing invite. The string after
/// the prefix is the base64url-encoded invite code (see [`invite_fields`]).
pub const INVITE_QR_PREFIX: &str = "napaxi-a2a-invite:";

/// Current local pairing invite schema version. Carried as the `v` field of the
/// invite JSON so a receiver can reject or migrate older codes.
pub const INVITE_VERSION: u32 = 1;

/// JSON field names inside a decoded local pairing invite. The invite is a flat
/// JSON object, base64url-encoded into the QR payload after [`INVITE_QR_PREFIX`].
/// These names are part of the cross-device wire contract.
pub mod invite_fields {
    /// Schema version (`u32`, see [`super::INVITE_VERSION`]).
    pub const VERSION: &str = "v";
    /// Inviting peer's stable peer id.
    pub const PEER_ID: &str = "peerId";
    /// Inviting peer's agent id.
    pub const AGENT_ID: &str = "agentId";
    /// Human-facing display name.
    pub const DISPLAY_NAME: &str = "displayName";
    /// Inviting peer's public key.
    pub const PUBLIC_KEY: &str = "publicKey";
    /// One-time pairing secret the scanner uses to derive the shared secret.
    pub const PAIRING_SECRET: &str = "pairingSecret";
    /// Local-transport endpoint (e.g. `lan_websocket` URL) if advertised.
    pub const ENDPOINT: &str = "endpoint";
    /// Transport kind for [`ENDPOINT`].
    pub const TRANSPORT: &str = "transport";
    /// Creation timestamp (RFC3339).
    pub const CREATED_AT: &str = "createdAt";
}

/// Message kinds that carry the pairing handshake. Adapters route inbound
/// messages of these kinds into the pairing flow rather than the task flow.
pub const PAIRING_HANDSHAKE_KINDS: [A2AMessageKind; 2] = [
    A2AMessageKind::PairingRequest,
    A2AMessageKind::PairingAccept,
];

/// Direction of a task relative to a given local peer id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskDirection {
    /// The local peer initiated the task (outbound).
    Sent,
    /// The local peer received the task (inbound).
    Received,
}

/// Is this task status one where the task is still awaiting action (received /
/// awaiting confirmation / accepted but not yet running or finished)? Shared so
/// "pending" badges and preflight counts match across adapters.
pub fn is_pending_task_status(status: &A2ATaskStatus) -> bool {
    matches!(
        status,
        A2ATaskStatus::Received | A2ATaskStatus::PendingUserConfirmation | A2ATaskStatus::Accepted
    )
}

/// Is this task status one where the task is "in play" — either still pending
/// or actively running? This is the superset the demo uses to decide whether a
/// task still needs attention, as opposed to a terminal state (succeeded /
/// failed / cancelled / rejected).
pub fn is_active_task_status(status: &A2ATaskStatus) -> bool {
    is_pending_task_status(status) || matches!(status, A2ATaskStatus::Running)
}

/// Delivery status that should trigger an automatic task receipt back to the
/// sender. When a received task message reaches this status the receiving
/// adapter sends an acknowledgement so the sender's ledger shows delivery.
pub const AUTO_RECEIPT_ON_STATUS: A2ADeliveryStatus = A2ADeliveryStatus::Delivered;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invite_prefix_and_version_are_stable() {
        // These are cross-device wire values; this test exists to make any
        // change to them a deliberate, reviewed break.
        assert_eq!(INVITE_QR_PREFIX, "napaxi-a2a-invite:");
        assert_eq!(INVITE_VERSION, 1);
    }

    #[test]
    fn invite_field_names_match_the_documented_wire_shape() {
        assert_eq!(invite_fields::VERSION, "v");
        assert_eq!(invite_fields::PEER_ID, "peerId");
        assert_eq!(invite_fields::PAIRING_SECRET, "pairingSecret");
        assert_eq!(invite_fields::PUBLIC_KEY, "publicKey");
    }

    #[test]
    fn pairing_handshake_kinds_are_the_two_pairing_messages() {
        assert!(PAIRING_HANDSHAKE_KINDS.contains(&A2AMessageKind::PairingRequest));
        assert!(PAIRING_HANDSHAKE_KINDS.contains(&A2AMessageKind::PairingAccept));
        assert!(!PAIRING_HANDSHAKE_KINDS.contains(&A2AMessageKind::TaskRequest));
    }

    #[test]
    fn task_status_classification_matches_demo_semantics() {
        // Pending statuses are a subset of active ("in play").
        for status in [
            A2ATaskStatus::Received,
            A2ATaskStatus::PendingUserConfirmation,
            A2ATaskStatus::Accepted,
        ] {
            assert!(
                is_pending_task_status(&status),
                "{status:?} should be pending"
            );
            assert!(is_active_task_status(&status), "pending implies active");
        }
        // Running is active but not pending.
        assert!(is_active_task_status(&A2ATaskStatus::Running));
        assert!(!is_pending_task_status(&A2ATaskStatus::Running));
        // Terminal states are neither.
        for status in [
            A2ATaskStatus::Succeeded,
            A2ATaskStatus::Failed,
            A2ATaskStatus::Cancelled,
            A2ATaskStatus::Rejected,
        ] {
            assert!(!is_pending_task_status(&status), "{status:?} is terminal");
            assert!(!is_active_task_status(&status), "{status:?} is terminal");
        }
    }
}
