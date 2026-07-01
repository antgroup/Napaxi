//! DTOs for mobile A2A deep-link handoff.

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const A2A_DEEPLINK_CAPABILITY_ID: &str = "napaxi.a2a.deeplink";
pub const A2A_LOCAL_CAPABILITY_ID: &str = "napaxi.a2a.local";
pub const A2A_TOOL_CAPABILITY_ID: &str = "napaxi.tool.a2a";
pub(super) const SIGNATURE_ALGORITHM_HMAC_SHA256_V1: &str = "hmac-sha256-v1";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2AAgentCard {
    pub agent_id: String,
    pub display_name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub accepted_input_modes: Vec<String>,
    #[serde(default)]
    pub accepted_output_modes: Vec<String>,
    #[serde(default)]
    pub deep_link_url: String,
    #[serde(default)]
    pub universal_link_url: Option<String>,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default = "default_true")]
    pub requires_user_confirmation: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2AEnvelopeKind {
    TaskRequest,
    TaskResult,
    TaskUpdate,
    PeerInvite,
    PeerAccept,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2AMessageKind {
    Hello,
    PairingRequest,
    PairingAccept,
    TaskRequest,
    TaskAccept,
    TaskReject,
    TaskProgress,
    TaskResult,
    Ack,
    Error,
    Ping,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2AParty {
    pub agent_id: String,
    #[serde(default)]
    pub peer_id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub deep_link_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ADeepLinkEnvelope {
    #[serde(default = "default_protocol_version")]
    pub protocol_version: u32,
    pub envelope_id: String,
    pub kind: A2AEnvelopeKind,
    pub sender: A2AParty,
    #[serde(default)]
    pub recipient: Option<A2AParty>,
    #[serde(default)]
    pub task: Option<A2ATaskRequest>,
    #[serde(default)]
    pub result: Option<A2ATaskResult>,
    #[serde(default)]
    pub callback: Option<A2ACallback>,
    pub created_at: String,
    pub expires_at: String,
    pub nonce: String,
    pub idempotency_key: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub signature_algorithm: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ATaskRequest {
    pub task_id: String,
    pub message: String,
    #[serde(default)]
    pub artifacts: Vec<A2AArtifact>,
    #[serde(default)]
    pub context: Value,
    #[serde(default)]
    pub requested_output_modes: Vec<String>,
    #[serde(default)]
    pub risk_hint: String,
    #[serde(default)]
    pub session_mode: A2ASessionMode,
    #[serde(default)]
    pub parent_task_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2AArtifact {
    pub artifact_id: String,
    #[serde(default)]
    pub mime_type: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub uri: Option<String>,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum A2ASessionMode {
    #[default]
    Isolated,
    Main,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ACallback {
    #[serde(default)]
    pub deep_link_url: String,
    #[serde(default)]
    pub universal_link_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ATaskResult {
    pub task_id: String,
    pub status: A2ATaskStatus,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub artifacts: Vec<A2AArtifact>,
    #[serde(default)]
    pub run_id: Option<String>,
    #[serde(default)]
    pub completed_at: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum A2ATaskStatus {
    Received,
    PendingUserConfirmation,
    Accepted,
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Rejected,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2APeer {
    pub peer_id: String,
    pub agent_id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub deep_link_url: String,
    #[serde(default)]
    pub trust_level: A2APeerTrustLevel,
    #[serde(default)]
    pub shared_secret: String,
    #[serde(default)]
    pub public_key: String,
    #[serde(default)]
    pub endpoints: Vec<A2APeerEndpoint>,
    #[serde(default)]
    pub last_seen_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2APeerEndpoint {
    pub transport: A2ATransportKind,
    pub uri: String,
    #[serde(default)]
    pub priority: u32,
    #[serde(default)]
    pub last_seen_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2ATransportKind {
    LanWebSocket,
    LanTcp,
    Ble,
    DeepLink,
    HostProvided,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[derive(Default)]
pub enum A2APeerTrustLevel {
    #[default]
    Untrusted,
    UserConfirmed,
    Trusted,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ATaskRecord {
    pub task_id: String,
    pub envelope_id: String,
    #[serde(default)]
    pub idempotency_key: String,
    pub agent_id: String,
    pub sender: A2AParty,
    #[serde(default)]
    pub callback: Option<A2ACallback>,
    pub request: A2ATaskRequest,
    pub status: A2ATaskStatus,
    pub trust: A2ATaskTrust,
    pub source: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub peer_message_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub session_key: Option<String>,
    #[serde(default)]
    pub run_id: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub result_artifacts: Vec<A2AArtifact>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum A2ATaskTrust {
    Untrusted,
    SignedPeer,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2APeerSession {
    pub session_id: String,
    pub local_peer_id: String,
    pub remote_peer_id: String,
    #[serde(default)]
    pub remote_agent_id: String,
    pub status: A2APeerSessionStatus,
    pub transport: A2ATransportKind,
    #[serde(default)]
    pub endpoint: String,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub last_message_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2APeerSessionStatus {
    Pairing,
    Active,
    Suspended,
    Closed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2APeerMessage {
    pub message_id: String,
    pub session_id: String,
    pub from_peer_id: String,
    pub to_peer_id: String,
    pub kind: A2AMessageKind,
    pub created_at: String,
    pub expires_at: String,
    pub nonce: String,
    pub idempotency_key: String,
    #[serde(default)]
    pub payload: Value,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub signature_algorithm: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2ADeliveryRecord {
    pub message_id: String,
    pub session_id: String,
    pub direction: A2AMessageDirection,
    pub kind: A2AMessageKind,
    pub status: A2ADeliveryStatus,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub task_id: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2AMessageDirection {
    Inbound,
    Outbound,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum A2ADeliveryStatus {
    Created,
    Sent,
    Delivered,
    Accepted,
    Rejected,
    Running,
    Succeeded,
    Failed,
    Expired,
    Duplicate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2AEventRecord {
    pub event_id: String,
    pub kind: A2AEnvelopeKind,
    pub envelope_id: String,
    pub status: String,
    pub created_at: String,
    #[serde(default)]
    pub task_id: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct A2AResultLink {
    pub task_id: String,
    pub envelope: A2ADeepLinkEnvelope,
    #[serde(default)]
    pub deep_link_url: String,
}

pub(super) fn default_protocol_version() -> u32 {
    1
}

fn default_true() -> bool {
    true
}
