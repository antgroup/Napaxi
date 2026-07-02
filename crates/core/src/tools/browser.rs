//! Browser control tool contract shared by SDK adapters.
//!
//! Core owns the tool names, schemas, and capability mapping. Host adapters own
//! the visible browser implementation and user approval UI.

use serde_json::{Value, json};

use crate::tool_registry::ToolDescriptor;

pub const BROWSER_CAPABILITY_ID: &str = "napaxi.tool.browser";

pub const BROWSER_OPEN: &str = "browser_open";
pub const BROWSER_SNAPSHOT: &str = "browser_snapshot";
pub const BROWSER_CLICK: &str = "browser_click";
pub const BROWSER_TYPE: &str = "browser_type";
pub const BROWSER_SCROLL: &str = "browser_scroll";
pub const BROWSER_WAIT: &str = "browser_wait";
pub const BROWSER_FIND_TEXT: &str = "browser_find_text";
pub const BROWSER_KEYS: &str = "browser_keys";
pub const BROWSER_BACK: &str = "browser_back";
pub const BROWSER_CLOSE: &str = "browser_close";

const TOOL_NAMES: &[&str] = &[
    BROWSER_OPEN,
    BROWSER_SNAPSHOT,
    BROWSER_CLICK,
    BROWSER_TYPE,
    BROWSER_SCROLL,
    BROWSER_WAIT,
    BROWSER_FIND_TEXT,
    BROWSER_KEYS,
    BROWSER_BACK,
    BROWSER_CLOSE,
];

pub fn is_browser_tool(name: &str) -> bool {
    TOOL_NAMES.contains(&name)
}

pub fn browser_tool_descriptors() -> Vec<ToolDescriptor> {
    vec![
        descriptor(
            BROWSER_OPEN,
            "Only open an absolute http:// or https:// URL in the persistent visible in-app browser session. Defaults to mobile browser mode, using the app WebView's normal mobile profile. Reuses the current page when the URL and browser mode already match unless force_reload is true. Never use this for file:// URLs, local filesystem paths, workspace paths, sandbox paths, generated HTML files, or files you just created; use file tools or the generated attachment instead.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "pattern": "^https?://",
                        "description": "Absolute http:// or https:// URL to open. Do not pass file:// URLs, local paths, workspace paths, sandbox paths, generated HTML files, or files you just created."
                    },
                    "mode": {
                        "type": "string",
                        "enum": ["desktop", "mobile"],
                        "description": "Browser rendering profile. Defaults to mobile. Use desktop only when the user asks for a desktop page or a mobile page is blocked/limited."
                    },
                    "force_reload": {
                        "type": "boolean",
                        "description": "Reload even when the current URL already matches."
                    }
                },
                "required": ["url"]
            }),
        ),
        descriptor(
            BROWSER_SNAPSHOT,
            "Read the current visible browser page state. Returns browser_mode, user_agent, page_state, viewport_map, page_change_token, backend_capabilities, optional screenshot metadata, and last_action_effect. Use viewport_map when DOM text is incomplete: it contains visible text blocks, clickable element positions, overlays, bbox, center points, nearby text, action hints, and diagnostics. If screenshot metadata is present and image_analyze is available, analyze the screenshot for visual understanding; otherwise use the JSON state and do not claim visual inspection.",
            crate::tool_registry::ToolEffect::Read,
            json!({
                "type": "object",
                "properties": {
                    "screenshot_mode": {
                        "type": "string",
                        "enum": ["auto", "never", "always"],
                        "description": "Optional screenshot capture preference. Defaults to auto. Screenshots are an optional visual aid; the JSON viewport_map is the non-visual fallback."
                    }
                }
            }),
        ),
        descriptor(
            BROWSER_CLICK,
            "Click an element in the current browser page. Prefer element_id from the latest browser_snapshot page_state. Legacy index, CSS selector, visible text, and accessibility label are still accepted; text/label clicks may use a visible text ancestor fallback for dynamic JavaScript components. For high-confidence viewport_map targets, click_point may be used as a coordinate fallback. The host verifies the click effect and may perform one safe recovery retry; failures include structured failure_code values such as no_effect_after_click, obscured, site_restricted, login_required, and target_unstable.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "element_id": {
                        "type": "string",
                        "description": "Stable element id from browser_snapshot page_state.elements. Preferred target."
                    },
                    "index": {
                        "type": "integer",
                        "description": "Legacy element index from browser_snapshot interactive elements."
                    },
                    "selector": {
                        "type": "string",
                        "description": "CSS selector for the element to click."
                    },
                    "text": {
                        "type": "string",
                        "description": "Visible text contained by the element to click."
                    },
                    "label": {
                        "type": "string",
                        "description": "Accessible label, aria-label, placeholder, or title for the element to click."
                    },
                    "click_point": {
                        "type": "object",
                        "description": "High-confidence viewport coordinate fallback from viewport_map center/clickable_point. Prefer element_id when possible.",
                        "properties": {
                            "x": {"type": "number"},
                            "y": {"type": "number"}
                        },
                        "required": ["x", "y"]
                    }
                }
            }),
        ),
        descriptor(
            BROWSER_TYPE,
            "Type text into an input or editable element in the current browser page. Prefer element_id from the latest browser_snapshot page_state.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "Text to enter."
                    },
                    "index": {
                        "type": "integer",
                        "description": "Legacy element index from browser_snapshot interactive elements."
                    },
                    "element_id": {
                        "type": "string",
                        "description": "Stable element id from browser_snapshot page_state.elements. Preferred target."
                    },
                    "selector": {
                        "type": "string",
                        "description": "CSS selector for the editable element."
                    },
                    "label": {
                        "type": "string",
                        "description": "Accessible label, aria-label, placeholder, or title for the editable element."
                    },
                    "submit": {
                        "type": "boolean",
                        "description": "Submit/press Enter after typing. Requires approval for high-risk flows."
                    },
                    "clear_first": {
                        "type": "boolean",
                        "description": "Clear existing field value before typing. Defaults to true."
                    }
                },
                "required": ["text"]
            }),
        ),
        descriptor(
            BROWSER_SCROLL,
            "Scroll the current browser page.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "direction": {
                        "type": "string",
                        "enum": ["up", "down", "left", "right"],
                        "description": "Scroll direction. Defaults to down."
                    },
                    "amount": {
                        "type": "integer",
                        "description": "Approximate scroll amount in pixels. Defaults to 700."
                    }
                }
            }),
        ),
        descriptor(
            BROWSER_WAIT,
            "Wait for the browser page to load, settle, or contain expected text. When scroll_to_text is true, the host may scroll the text into view.",
            crate::tool_registry::ToolEffect::Read,
            json!({
                "type": "object",
                "properties": {
                    "milliseconds": {
                        "type": "integer",
                        "description": "Maximum wait duration in milliseconds. Defaults to 1000.",
                        "minimum": 0,
                        "maximum": 30000
                    },
                    "text": {
                        "type": "string",
                        "description": "Optional visible text to wait for."
                    },
                    "scroll_to_text": {
                        "type": "boolean",
                        "description": "If text is provided, scroll the first matching text into view when possible."
                    }
                }
            }),
        ),
        descriptor(
            BROWSER_FIND_TEXT,
            "Find visible text on the current page and scroll the first match into view.",
            crate::tool_registry::ToolEffect::Read,
            json!({
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "Text to find and bring into view."
                    }
                },
                "required": ["text"]
            }),
        ),
        descriptor(
            BROWSER_KEYS,
            "Send simple keyboard keys to the focused browser element. Supported keys are Enter, Escape, Tab, ArrowUp, ArrowDown, ArrowLeft, and ArrowRight.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "keys": {
                        "type": "string",
                        "description": "Key name or plus-separated key sequence such as Enter, Escape, Tab, ArrowDown."
                    }
                },
                "required": ["keys"]
            }),
        ),
        descriptor(
            BROWSER_BACK,
            "Navigate the persistent browser session back if possible.",
            crate::tool_registry::ToolEffect::External,
            empty_parameters(),
        ),
        descriptor(
            BROWSER_CLOSE,
            "Close or clear the persistent browser session. Hiding the UI does not call this tool.",
            crate::tool_registry::ToolEffect::External,
            json!({
                "type": "object",
                "properties": {
                    "clear_storage": {
                        "type": "boolean",
                        "description": "Clear browser cookies and local storage for this app WebView session."
                    }
                }
            }),
        ),
    ]
}

pub fn browser_tool_descriptors_json() -> String {
    serde_json::to_string(&browser_tool_descriptors()).unwrap_or_else(|_| "[]".to_string())
}

fn descriptor(
    name: &str,
    description: &str,
    effect: crate::tool_registry::ToolEffect,
    parameters: Value,
) -> ToolDescriptor {
    ToolDescriptor {
        name: name.to_string(),
        description: description.to_string(),
        parameters,
        effect,
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
    fn descriptors_cover_all_browser_tools() {
        let descriptors = browser_tool_descriptors();
        let names = descriptors
            .iter()
            .map(|descriptor| descriptor.name.as_str())
            .collect::<Vec<_>>();

        assert_eq!(names, TOOL_NAMES);
        assert!(is_browser_tool(BROWSER_OPEN));
        assert!(!is_browser_tool("web_fetch"));
    }

    #[test]
    fn descriptors_match_shared_contract_fixture() {
        // The shared fixture at packages/api_contract/fixtures/browser/ is the
        // single source of truth that the Flutter offline fallback
        // (browser_tool_host.dart `_fallbackToolDefinitions`) is also pinned
        // against. Locking core ⇄ fixture here, and Dart ⇄ fixture in
        // browser_tool_contract_fixture_test.dart, means the offline fallback
        // can no longer silently drift from this canonical descriptor set.
        let fixture_path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../packages/api_contract/fixtures/browser/tool_descriptors.json"
        );
        let fixture_text = std::fs::read_to_string(fixture_path)
            .expect("read shared browser tool_descriptors fixture");
        let fixture: Value =
            serde_json::from_str(&fixture_text).expect("parse browser fixture json");
        let actual: Value = serde_json::from_str(&browser_tool_descriptors_json())
            .expect("parse browser_tool_descriptors_json output");
        assert_eq!(
            actual, fixture,
            "browser_tool_descriptors() drifted from the shared contract fixture; \
             regenerate packages/api_contract/fixtures/browser/tool_descriptors.json"
        );
    }

    #[test]
    fn descriptors_include_required_parameter_schemas() {
        let descriptors = browser_tool_descriptors();
        let by_name = descriptors
            .iter()
            .map(|descriptor| (descriptor.name.as_str(), descriptor))
            .collect::<std::collections::HashMap<_, _>>();

        assert_eq!(by_name[BROWSER_OPEN].parameters["required"], json!(["url"]));
        let open_description = by_name[BROWSER_OPEN].description.to_lowercase();
        assert!(open_description.contains("mobile"));
        assert!(open_description.contains("http"));
        assert!(open_description.contains("https"));
        assert!(open_description.contains("file://"));
        assert!(open_description.contains("local"));
        assert!(open_description.contains("generated html"));
        assert_eq!(
            by_name[BROWSER_OPEN].parameters["properties"]["url"]["pattern"],
            json!("^https?://")
        );
        assert_eq!(
            by_name[BROWSER_OPEN].parameters["properties"]["mode"]["enum"],
            json!(["desktop", "mobile"])
        );
        assert!(
            by_name[BROWSER_SNAPSHOT]
                .description
                .contains("viewport_map")
        );
        assert!(
            by_name[BROWSER_CLICK]
                .description
                .contains("no_effect_after_click")
        );
        assert_eq!(
            by_name[BROWSER_SNAPSHOT].parameters["properties"]["screenshot_mode"]["enum"],
            json!(["auto", "never", "always"])
        );
        assert!(
            by_name[BROWSER_CLICK].parameters["properties"]
                .as_object()
                .unwrap()
                .contains_key("click_point")
        );
        assert_eq!(
            by_name[BROWSER_TYPE].parameters["required"],
            json!(["text"])
        );
        assert!(
            by_name[BROWSER_CLICK].parameters["properties"]
                .as_object()
                .unwrap()
                .contains_key("element_id")
        );
        assert_eq!(
            by_name[BROWSER_SCROLL].parameters["properties"]["direction"]["enum"],
            json!(["up", "down", "left", "right"])
        );
        assert_eq!(
            by_name[BROWSER_KEYS].parameters["required"],
            json!(["keys"])
        );
        assert_eq!(
            by_name[BROWSER_FIND_TEXT].parameters["required"],
            json!(["text"])
        );
    }
}
