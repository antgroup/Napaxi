//! QQ-bot protocol logic, owned by core as platform-independent (sans-IO) code.
//!
//! The Flutter/native adapters own transport only: the WebSocket gateway
//! connection, the heartbeat timer, and the HTTP calls to the QQ OpenAPI. Every
//! platform-independent protocol decision — what outbound payload to build,
//! which endpoint a peer maps to, whether a 4xx means "retry as plain text",
//! how to normalize an inbound gateway event into the shared channel envelope —
//! lives here so it is written and tested once instead of re-implemented per
//! adapter.
//!
//! All entry points are pure JSON-in / JSON-out functions (see [`protocol`]);
//! they hold no connection state and perform no I/O. The stateful gateway
//! handshake is modeled as a reducer in [`gateway`].

pub mod gateway;
pub mod protocol;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod gateway_tests;
