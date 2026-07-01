//! Mobile platform capability contract shared by SDK adapters.
//!
//! Core owns the tool names, parameters, and canonical result shape so Flutter,
//! native Android/iOS, and future adapters can expose the same mobile tools.

use serde_json::{Value, json};

use crate::tool_registry::ToolDescriptor;

pub const OPEN_URL: &str = "open_url";
pub const MAKE_CALL: &str = "make_call";
pub const SEND_SMS: &str = "send_sms";
pub const GET_CLIPBOARD: &str = "get_clipboard";
pub const SET_CLIPBOARD: &str = "set_clipboard";
pub const GET_DEVICE_INFO: &str = "get_device_info";
pub const GET_LOCATION: &str = "get_location";
pub const SEND_NOTIFICATION: &str = "send_notification";
pub const GET_CONTACTS: &str = "get_contacts";
pub const CREATE_CALENDAR_EVENT: &str = "create_calendar_event";
pub const LIST_CALENDAR_EVENTS: &str = "list_calendar_events";
pub const TAKE_PHOTO: &str = "take_photo";
pub const MEDIA_LIBRARY: &str = "media_library";
pub const RECORD_AUDIO: &str = "record_audio";
pub const SET_ALARM: &str = "set_alarm";
pub const INSTALL_APK: &str = "install_apk";

const TOOL_NAMES: &[&str] = &[
    OPEN_URL,
    MAKE_CALL,
    SEND_SMS,
    GET_CLIPBOARD,
    SET_CLIPBOARD,
    GET_DEVICE_INFO,
    GET_LOCATION,
    SEND_NOTIFICATION,
    GET_CONTACTS,
    CREATE_CALENDAR_EVENT,
    LIST_CALENDAR_EVENTS,
    TAKE_PHOTO,
    MEDIA_LIBRARY,
    RECORD_AUDIO,
    SET_ALARM,
    INSTALL_APK,
];

pub fn is_platform_tool(name: &str) -> bool {
    TOOL_NAMES.contains(&name)
}

pub fn platform_tool_descriptors() -> Vec<ToolDescriptor> {
    vec![
        descriptor(
            OPEN_URL,
            "Open a URL in the device's default browser or app.",
            json!({
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "The URL to open"
                    }
                },
                "required": ["url"]
            }),
        ),
        descriptor(
            MAKE_CALL,
            "Open the phone dialer with a pre-filled number. The user must confirm to dial.",
            json!({
                "type": "object",
                "properties": {
                    "phone_number": {
                        "type": "string",
                        "description": "Phone number to call"
                    }
                },
                "required": ["phone_number"]
            }),
        ),
        descriptor(
            SEND_SMS,
            "Open the SMS app with a pre-filled recipient and optional message body.",
            json!({
                "type": "object",
                "properties": {
                    "phone_number": {
                        "type": "string",
                        "description": "Phone number to send SMS to"
                    },
                    "body": {
                        "type": "string",
                        "description": "Pre-filled message body (optional)"
                    }
                },
                "required": ["phone_number"]
            }),
        ),
        descriptor(
            GET_CLIPBOARD,
            "Read the current text content from the device clipboard.",
            empty_parameters(),
        ),
        descriptor(
            SET_CLIPBOARD,
            "Copy text to the device clipboard.",
            json!({
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "Text to copy to clipboard"
                    }
                },
                "required": ["text"]
            }),
        ),
        descriptor(
            GET_DEVICE_INFO,
            "Get device hardware and OS information (brand, model, OS version, etc.).",
            empty_parameters(),
        ),
        descriptor(
            GET_LOCATION,
            "Get the device's current GPS location (latitude, longitude, altitude, accuracy). Requests location permission if not yet granted.",
            empty_parameters(),
        ),
        descriptor(
            SEND_NOTIFICATION,
            "Send a local notification to the device. Requests notification permission if not yet granted.",
            json!({
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Notification title"
                    },
                    "body": {
                        "type": "string",
                        "description": "Notification body text"
                    }
                },
                "required": ["title", "body"]
            }),
        ),
        descriptor(
            GET_CONTACTS,
            "Search or list contacts from the device address book. Requests contacts permission if not yet granted.",
            json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search keyword to filter contacts by name (optional)"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of contacts to return (default 20)"
                    }
                }
            }),
        ),
        descriptor(
            CREATE_CALENDAR_EVENT,
            "Create a new event in the device calendar. Requests calendar permission if not yet granted.",
            json!({
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Event title"
                    },
                    "start": {
                        "type": "string",
                        "description": "Start time in ISO 8601 format (e.g. 2026-04-28T10:00:00)"
                    },
                    "end": {
                        "type": "string",
                        "description": "End time in ISO 8601 format (e.g. 2026-04-28T11:00:00)"
                    },
                    "description": {
                        "type": "string",
                        "description": "Event description (optional)"
                    }
                },
                "required": ["title", "start", "end"]
            }),
        ),
        descriptor(
            LIST_CALENDAR_EVENTS,
            "List events from the device calendar within a date range. Requests calendar permission if not yet granted.",
            json!({
                "type": "object",
                "properties": {
                    "start": {
                        "type": "string",
                        "description": "Start date in ISO 8601 format (e.g. 2026-04-28)"
                    },
                    "end": {
                        "type": "string",
                        "description": "End date in ISO 8601 format (e.g. 2026-04-29)"
                    }
                },
                "required": ["start", "end"]
            }),
        ),
        descriptor(
            TAKE_PHOTO,
            "Open the device camera to take a photo. Returns the saved photo path in the sandbox.",
            empty_parameters(),
        ),
        descriptor(
            MEDIA_LIBRARY,
            "Access the device media library with explicit user or host authorization. Use status to inspect permission, search to list authorized media metadata, import to copy selected assets into sandbox artifacts, or pick as a manual picker fallback.",
            json!({
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "description": "Media library operation to perform.",
                        "enum": ["status", "search", "import", "pick"]
                    },
                    "media_types": {
                        "type": "array",
                        "description": "Optional media types to include. Defaults to images.",
                        "items": {
                            "type": "string",
                            "enum": ["image", "video"]
                        }
                    },
                    "start_ms": {
                        "type": "integer",
                        "description": "Optional inclusive creation timestamp lower bound in Unix milliseconds."
                    },
                    "end_ms": {
                        "type": "integer",
                        "description": "Optional exclusive creation timestamp upper bound in Unix milliseconds."
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of media items. Default 20 for search/import and 9 for pick. Max 50."
                    },
                    "asset_ids": {
                        "type": "array",
                        "description": "Asset identifiers returned by search to import.",
                        "items": {
                            "type": "string"
                        }
                    },
                    "request_permission": {
                        "type": "boolean",
                        "description": "Whether the host may show a system permission prompt if needed. Default true for search/import."
                    }
                },
                "required": ["action"]
            }),
        ),
        descriptor(
            RECORD_AUDIO,
            "Record audio from the device microphone for a specified duration. Requests microphone permission if not yet granted.",
            json!({
                "type": "object",
                "properties": {
                    "duration_seconds": {
                        "type": "integer",
                        "description": "Recording duration in seconds (default 10, max 60)"
                    }
                }
            }),
        ),
        descriptor(
            SET_ALARM,
            "Schedule an alarm notification at a specified time. Uses the device notification system.",
            json!({
                "type": "object",
                "properties": {
                    "time": {
                        "type": "string",
                        "description": "Alarm time in HH:mm format (e.g. \"07:30\") or ISO 8601"
                    },
                    "message": {
                        "type": "string",
                        "description": "Alarm message"
                    },
                    "repeat_days": {
                        "type": "array",
                        "description": "Optional weekdays for a repeating alarm. Omit for a one-time alarm. Use lowercase weekday names such as monday, tuesday, or all seven days for daily.",
                        "items": {
                            "type": "string",
                            "enum": ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
                        }
                    }
                },
                "required": ["time", "message"]
            }),
        ),
        descriptor(
            INSTALL_APK,
            "Install an Android APK from a sandbox or local file path. If installing unknown apps is not allowed yet, opens the Android permission screen first. The user must confirm the installation in the system package installer.",
            json!({
                "type": "object",
                "properties": {
                    "apk_path": {
                        "type": "string",
                        "description": "APK file path. Prefer sandbox paths such as /workspace/app.apk; absolute local paths are also accepted."
                    }
                },
                "required": ["apk_path"]
            }),
        ),
    ]
}

pub fn platform_tool_descriptors_json() -> String {
    serde_json::to_string(&platform_tool_descriptors()).unwrap_or_else(|_| "[]".to_string())
}

#[cfg(test)]
fn mobile_attachment_result(
    sandbox_path: &str,
    kind: &str,
    filename: &str,
    mime_type: &str,
    size_bytes: u64,
) -> Value {
    json!({
        "sandbox_path": sandbox_path,
        "file_path": sandbox_path,
        "kind": kind,
        "filename": filename,
        "mime_type": mime_type,
        "mimeType": mime_type,
        "size_bytes": size_bytes,
        "sizeBytes": size_bytes,
    })
}

fn descriptor(name: &str, description: &str, parameters: Value) -> ToolDescriptor {
    ToolDescriptor {
        name: name.to_string(),
        description: description.to_string(),
        parameters,
        effect: crate::tool_registry::ToolEffect::External,
    }
}

fn empty_parameters() -> Value {
    json!({
        "type": "object",
        "properties": {}
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptors_match_shared_contract_fixture() {
        // The shared fixture at packages/api_contract/fixtures/platform_tools/
        // is the single source of truth that the native iOS and Android adapter
        // copies of this contract are also pinned against (see
        // PlatformToolContractTests.swift and PlatformToolContractTest.kt).
        // Locking core ⇄ fixture here means the hand-copied adapter contracts
        // can no longer silently drift from this canonical descriptor set.
        //
        // Note: the fixture records every tool's effect as "external" (core's
        // value). Adapters may localize `effect` (e.g. iOS marks read-only
        // tools "read"), so adapter guards compare name/description/parameters
        // and intentionally ignore `effect`.
        let fixture_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../packages/api_contract/fixtures/platform_tools/tool_descriptors.json"
        );
        let fixture_text = std::fs::read_to_string(fixture_path)
            .expect("read shared platform_tools tool_descriptors fixture");
        let fixture: Value =
            serde_json::from_str(&fixture_text).expect("parse platform_tools fixture json");
        let actual: Value = serde_json::from_str(&platform_tool_descriptors_json())
            .expect("parse platform_tool_descriptors_json output");
        assert_eq!(
            actual, fixture,
            "platform_tool_descriptors() drifted from the shared contract fixture; \
             regenerate packages/api_contract/fixtures/platform_tools/tool_descriptors.json"
        );
    }

    #[test]
    fn descriptors_cover_all_platform_tools() {
        let descriptors = platform_tool_descriptors();
        let names = descriptors
            .iter()
            .map(|descriptor| descriptor.name.as_str())
            .collect::<Vec<_>>();

        assert_eq!(names, TOOL_NAMES);
        assert!(is_platform_tool(TAKE_PHOTO));
        assert!(!is_platform_tool("shell"));
    }

    #[test]
    fn descriptors_include_required_parameter_schemas() {
        let descriptors = platform_tool_descriptors();
        let by_name = descriptors
            .iter()
            .map(|descriptor| (descriptor.name.as_str(), descriptor))
            .collect::<std::collections::HashMap<_, _>>();

        assert_eq!(by_name[OPEN_URL].parameters["required"], json!(["url"]));
        assert_eq!(
            by_name[RECORD_AUDIO].parameters["properties"]["duration_seconds"]["type"],
            "integer"
        );
        assert_eq!(
            by_name[SET_ALARM].parameters["properties"]["repeat_days"]["items"]["enum"],
            json!([
                "sunday",
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday"
            ])
        );
        assert_eq!(
            by_name[INSTALL_APK].parameters["required"],
            json!(["apk_path"])
        );
    }

    #[test]
    fn attachment_result_keeps_canonical_and_legacy_keys() {
        let value = mobile_attachment_result(
            "/workspace/attachments/camera/photo.jpg",
            "image",
            "photo.jpg",
            "image/jpeg",
            42,
        );

        assert_eq!(
            value["sandbox_path"],
            "/workspace/attachments/camera/photo.jpg"
        );
        assert_eq!(value["file_path"], value["sandbox_path"]);
        assert_eq!(value["mime_type"], "image/jpeg");
        assert_eq!(value["mimeType"], "image/jpeg");
        assert_eq!(value["size_bytes"], 42);
        assert_eq!(value["sizeBytes"], 42);
    }
}
