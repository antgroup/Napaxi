//! Mobile webpage fetch builtin tool.

use crate::tool_registry::ToolDescriptor;

pub const WEB_FETCH_TOOL_NAME: &str = "web_fetch";

const MAX_FETCH_BYTES: u64 = 2 * 1024 * 1024;
const MAX_OUTPUT_CHARS: usize = 24_000;

pub fn descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: WEB_FETCH_TOOL_NAME.to_string(),
        description: "Fetch a public webpage by URL and return readable text content. Use web_search for discovery and web_fetch for reading a known URL.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "Public HTTP or HTTPS webpage URL to fetch."
                },
                "timeout_secs": {
                    "type": "integer",
                    "description": "Request timeout in seconds. Defaults to 30, maximum 120."
                }
            },
            "required": ["url"]
        }),
        effect: crate::tool_registry::ToolEffect::Read,
    }
}

pub async fn execute(params: serde_json::Value) -> Result<String, String> {
    let url = params
        .get("url")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "web_fetch url is required".to_string())?;
    let timeout_secs = params
        .get("timeout_secs")
        .and_then(serde_json::Value::as_u64)
        .unwrap_or(crate::http_tool::DEFAULT_TIMEOUT_SECS);
    let (status, headers, bytes) =
        crate::http_tool::get_external_url_bytes(url, timeout_secs, MAX_FETCH_BYTES).await?;
    let content_type = headers
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    let raw = String::from_utf8_lossy(&bytes);
    let text = if content_type.contains("html") || looks_like_html(&raw) {
        html_to_text(&raw)
    } else {
        raw.to_string()
    };
    let (content, truncated) = truncate_text(&text, MAX_OUTPUT_CHARS);
    Ok(serde_json::json!({
        "status": status.as_u16(),
        "success": status.is_success(),
        "url": url,
        "content_type": content_type,
        "content": content,
        "truncated": truncated,
        "size_bytes": bytes.len(),
    })
    .to_string())
}

fn looks_like_html(text: &str) -> bool {
    let prefix = text
        .chars()
        .take(512)
        .collect::<String>()
        .to_ascii_lowercase();
    prefix.contains("<html") || prefix.contains("<!doctype html")
}

fn html_to_text(html: &str) -> String {
    let without_scripts = remove_tag_blocks(html, "script");
    let without_styles = remove_tag_blocks(&without_scripts, "style");
    let mut output = String::with_capacity(without_styles.len());
    let mut in_tag = false;
    for ch in without_styles.chars() {
        match ch {
            '<' => {
                in_tag = true;
                output.push(' ');
            }
            '>' => {
                in_tag = false;
                output.push(' ');
            }
            _ if !in_tag => output.push(ch),
            _ => {}
        }
    }
    decode_basic_entities(&output)
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace(" .", ".")
        .replace(" ,", ",")
        .replace(" !", "!")
        .replace(" ?", "?")
        .replace(" ;", ";")
        .replace(" :", ":")
}

fn remove_tag_blocks(input: &str, tag: &str) -> String {
    let mut output = String::with_capacity(input.len());
    let mut remaining = input;
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    loop {
        let lowered = remaining.to_ascii_lowercase();
        let Some(start) = lowered.find(&open) else {
            output.push_str(remaining);
            break;
        };
        output.push_str(&remaining[..start]);
        let after_start = &remaining[start..];
        let lowered_after = after_start.to_ascii_lowercase();
        let Some(end_offset) = lowered_after.find(&close) else {
            break;
        };
        remaining = &after_start[end_offset + close.len()..];
    }
    output
}

fn decode_basic_entities(text: &str) -> String {
    let named = text
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ");
    let with_numeric = decode_numeric_entities(&named);
    // Decode &amp; last so an encoded literal like "&amp;lt;" is not turned
    // into a working "&lt;" entity by the named/numeric passes above.
    with_numeric.replace("&amp;", "&")
}

fn decode_numeric_entities(text: &str) -> String {
    if !text.contains("&#") {
        return text.to_string();
    }
    let mut output = String::with_capacity(text.len());
    let mut remaining = text;
    while let Some(start) = remaining.find("&#") {
        output.push_str(&remaining[..start]);
        let after = &remaining[start + 2..];
        let Some(semi) = after.find(';') else {
            output.push_str(&remaining[start..]);
            return output;
        };
        let body = &after[..semi];
        let parsed = if let Some(hex) = body.strip_prefix(['x', 'X']) {
            u32::from_str_radix(hex, 16).ok()
        } else {
            body.parse::<u32>().ok()
        };
        match parsed.and_then(char::from_u32) {
            Some(ch) => {
                output.push(ch);
                remaining = &after[semi + 1..];
            }
            None => {
                // Leave malformed references untouched and keep scanning past them.
                output.push_str("&#");
                remaining = after;
            }
        }
    }
    output.push_str(remaining);
    output
}

fn truncate_text(text: &str, max_chars: usize) -> (String, bool) {
    if text.chars().count() <= max_chars {
        return (text.to_string(), false);
    }
    let mut out = String::new();
    for ch in text.chars().take(max_chars) {
        out.push(ch);
    }
    (out, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptor_exposes_web_fetch() {
        let descriptor = descriptor();
        assert_eq!(descriptor.name, "web_fetch");
        assert!(
            descriptor.parameters["required"]
                .as_array()
                .unwrap()
                .iter()
                .any(|value| value.as_str() == Some("url"))
        );
    }

    #[test]
    fn strips_scripts_styles_and_tags() {
        let text = html_to_text(
            r#"<html><head><style>.x{}</style><script>alert(1)</script></head>
            <body><h1>Hello &amp; welcome</h1><p>Read <b>this</b>.</p></body></html>"#,
        );
        assert_eq!(text, "Hello & welcome Read this.");
    }

    #[test]
    fn truncates_on_char_boundary() {
        let (text, truncated) = truncate_text("你好世界", 2);
        assert_eq!(text, "你好");
        assert!(truncated);
    }

    #[test]
    fn decodes_decimal_and_hex_numeric_entities() {
        assert_eq!(
            decode_basic_entities("It&#8217;s a &#x2764; test"),
            "It’s a ❤ test"
        );
    }

    #[test]
    fn decodes_apostrophe_named_entity() {
        assert_eq!(decode_basic_entities("don&apos;t"), "don't");
    }

    #[test]
    fn leaves_malformed_numeric_entities_intact() {
        assert_eq!(decode_basic_entities("a &# b &#zz; c"), "a &# b &#zz; c");
    }

    #[test]
    fn decodes_amp_after_numeric_to_avoid_double_decoding() {
        // "&amp;#60;" is an encoded literal for the text "&#60;", not a
        // request to produce "<". The amp pass must run after numeric decoding.
        assert_eq!(decode_basic_entities("&amp;#60;"), "&#60;");
    }
}
