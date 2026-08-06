//! Mobile web search builtin tool.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use std::sync::LazyLock;

use crate::tool_registry::{ToolDescriptor, ToolExecutionContext, ToolRequestBridge};

pub const WEB_SEARCH_TOOL_NAME: &str = "web_search";

const DEFAULT_COUNT: usize = 5;
const MAX_COUNT: usize = 10;
const CACHE_TTL: Duration = Duration::from_secs(15 * 60);
const CACHE_MAX_ENTRIES: usize = 64;
const BROWSER_SEARCH_TIMEOUT: Duration = Duration::from_secs(45);
static SEARCH_CACHE: LazyLock<Mutex<SearchCache>> =
    LazyLock::new(|| Mutex::new(SearchCache::default()));

#[derive(Default)]
struct SearchCache {
    entries: HashMap<String, CachedEntry>,
    order: VecDeque<String>,
}

struct CachedEntry {
    body: String,
    inserted: Instant,
}

#[derive(Clone)]
pub(crate) struct BrowserSearchContext {
    pub(crate) bridge: ToolRequestBridge,
    pub(crate) tool_context: ToolExecutionContext,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SearchResult {
    title: String,
    url: String,
    snippet: String,
}

pub fn descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: WEB_SEARCH_TOOL_NAME.to_string(),
        description: "Search the web and return JSON with query, diagnostics, result_count, and a results array of title, url, and snippet. Supports optional count, language, and freshness filters.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search query."
                },
                "count": {
                    "type": "integer",
                    "description": "Number of results to return, from 1 to 10. Defaults to 5.",
                    "minimum": 1,
                    "maximum": MAX_COUNT
                },
                "language": {
                    "type": "string",
                    "description": "Preferred search language, such as en or zh-Hans. Defaults to zh-Hans."
                },
                "freshness": {
                    "type": "string",
                    "description": "Optional time filter.",
                    "enum": ["day", "week", "month"]
                }
            },
            "required": ["query"]
        }),
        effect: crate::tool_registry::ToolEffect::Read,
    }
}

pub(crate) async fn execute_with_browser(
    params: serde_json::Value,
    browser_context: Option<BrowserSearchContext>,
) -> Result<String, String> {
    let query = params
        .get("query")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "web_search query is required".to_string())?;
    let count = params
        .get("count")
        .and_then(serde_json::Value::as_u64)
        .map(|value| (value as usize).clamp(1, MAX_COUNT))
        .unwrap_or(DEFAULT_COUNT);
    let language = params
        .get("language")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("zh-Hans");
    let freshness = params
        .get("freshness")
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .unwrap_or("");

    let cache_mode = "browser";
    let key = cache_key(query, count, language, freshness, cache_mode);
    if let Some(cached) = cache_get(&key) {
        tracing::debug!(query, cache_mode, "web_search cache hit");
        return Ok(cached);
    }

    let context = browser_context.ok_or_else(|| {
        "web_search requires a browser host bridge; HTTP fallback is disabled".to_string()
    })?;
    tracing::info!(query, "web_search using browser-backed search");
    let results = search_with_browser(&context, query, count, language, freshness)
        .await
        .map_err(|error| format!("web_search browser path failed: {error}"))?;
    if results.is_empty() {
        return Err(
            "web_search browser path returned no results; HTTP fallback is disabled".to_string(),
        );
    }
    let diagnostics = "source=browser; fallback=disabled".to_string();
    let body = format_results_with_diagnostics(query, &results, &diagnostics);
    cache_put(key, body.clone());
    Ok(body)
}

async fn search_with_browser(
    context: &BrowserSearchContext,
    query: &str,
    count: usize,
    language: &str,
    _freshness: &str,
) -> Result<Vec<SearchResult>, String> {
    let url = browser_bing_home_url(language);
    crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_OPEN,
        serde_json::json!({
            "url": url,
            // Match the path users reported works in Android WebView: load Bing
            // first, then submit the visible search field in the mobile WebView.
            // Directly opening a /search?q=... URL can produce lower-quality or
            // generic result sets, and desktop mode may not expose the same
            // visible field quickly enough on Android.
            "mode": "mobile",
            "force_reload": true,
        }),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await?;

    // Android WebView can report an empty/partial snapshot immediately after
    // navigation. Give the homepage a short visible-browser settle step before
    // resolving the search field, otherwise browser_type may see no candidates.
    crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_WAIT,
        serde_json::json!({
            "milliseconds": 1500,
            "screenshot_mode": "never",
        }),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await?;

    let mut last_type_error = None;
    for params in browser_search_type_attempts(query) {
        let type_output = crate::tool_registry::request_host_tool_execution_with_context(
            context.bridge.clone(),
            crate::browser_tools::BROWSER_TYPE,
            params,
            BROWSER_SEARCH_TIMEOUT,
            Some(&context.tool_context),
        )
        .await?;
        if let Some(error) = host_tool_error(&type_output) {
            tracing::debug!(query, error = %error, "web_search browser_type attempt failed");
            last_type_error = Some(error);
            continue;
        }

        let mut last_observation = type_output;
        let mut results = parse_browser_search_results(&last_observation, count);
        tracing::debug!(
            query,
            result_count = results.len(),
            "web_search parsed browser_type output"
        );
        if !results.is_empty() {
            return Ok(results);
        }

        // Browser form submission is asynchronous in Android WebView. Poll a
        // few snapshots instead of treating the first post-type snapshot as the
        // final result page; otherwise we can observe the Bing homepage before
        // the navigation or result DOM has settled and incorrectly report an
        // empty result set.
        for milliseconds in [800_u64, 1500, 2500, 3500] {
            let wait_output = crate::tool_registry::request_host_tool_execution_with_context(
                context.bridge.clone(),
                crate::browser_tools::BROWSER_WAIT,
                serde_json::json!({
                    "milliseconds": milliseconds,
                    "screenshot_mode": "never",
                }),
                BROWSER_SEARCH_TIMEOUT,
                Some(&context.tool_context),
            )
            .await?;
            last_observation = wait_output;
            results = parse_browser_search_results(&last_observation, count);
            tracing::debug!(
                query,
                milliseconds,
                result_count = results.len(),
                "web_search parsed browser_wait output"
            );
            if !results.is_empty() {
                return Ok(results);
            }
        }

        let snapshot_output = crate::tool_registry::request_host_tool_execution_with_context(
            context.bridge.clone(),
            crate::browser_tools::BROWSER_SNAPSHOT,
            serde_json::json!({"screenshot_mode": "never"}),
            BROWSER_SEARCH_TIMEOUT,
            Some(&context.tool_context),
        )
        .await?;
        last_observation = snapshot_output;
        results = parse_browser_search_results(&last_observation, count);
        tracing::debug!(
            query,
            result_count = results.len(),
            diagnostics = %browser_observation_diagnostics(&last_observation),
            "web_search parsed browser_snapshot output"
        );
        if !results.is_empty() {
            return Ok(results);
        }
        last_type_error = Some(format!(
            "browser search submitted but no parseable result links were found ({})",
            browser_observation_diagnostics(&last_observation)
        ));
    }

    Err(last_type_error.unwrap_or_else(|| "browser search field was not found".to_string()))
}

fn browser_bing_home_url(language: &str) -> String {
    format!(
        "https://cn.bing.com/?setlang={}&cc=",
        urlencoding::encode(language)
    )
}

fn browser_search_type_attempts(query: &str) -> Vec<serde_json::Value> {
    // Keep this close to the visible Bing homepage flow instead of constructing
    // a /search?q=... URL. On Android WebView, submitting the homepage field has
    // produced better results than directly opening the search URL.
    [
        serde_json::json!({
            "selector": "#sb_form_q",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
        serde_json::json!({
            "selector": "input#sb_form_q[name='q']",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
        serde_json::json!({
            "selector": "input[name='q']",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
        serde_json::json!({
            "selector": "input[type='search']",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
        serde_json::json!({
            "label": "搜索网页",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
        serde_json::json!({
            "label": "输入搜索词",
            "text": query,
            "submit": true,
            "submit_selector": "#sb_form",
            "clear_first": true,
        }),
    ]
    .into_iter()
    .collect()
}

fn host_tool_error(output: &str) -> Option<String> {
    let value = serde_json::from_str::<serde_json::Value>(output).ok()?;
    if value
        .get("success")
        .and_then(serde_json::Value::as_bool)
        .is_some_and(|success| !success)
    {
        let message = value
            .get("error")
            .or_else(|| value.get("blocked_or_approval_reason"))
            .or_else(|| value.get("failure_code"))
            .and_then(serde_json::Value::as_str)
            .unwrap_or("browser tool returned success=false");
        return Some(message.to_string());
    }
    None
}

fn browser_observation_diagnostics(output: &str) -> String {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(output) else {
        return "unparseable browser output".to_string();
    };
    let url = value
        .get("url")
        .or_else(|| value_at_path(&value, "page_state.url"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let title = value
        .get("title")
        .or_else(|| value_at_path(&value, "page_state.title"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let text = value
        .get("text")
        .or_else(|| value_at_path(&value, "page_state.text"))
        .and_then(serde_json::Value::as_str)
        .map(clean_browser_text)
        .unwrap_or_default();
    let text_preview: String = text.chars().take(160).collect();
    format!("url={url}; title={title}; text={text_preview}")
}

fn parse_browser_search_results(output: &str, max: usize) -> Vec<SearchResult> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(output) else {
        return Vec::new();
    };
    if value
        .get("success")
        .and_then(serde_json::Value::as_bool)
        .is_some_and(|success| !success)
    {
        return Vec::new();
    }

    let mut results = Vec::new();
    let mut seen_urls = std::collections::HashSet::new();

    // Prefer structured DOM search records emitted by the browser runtime.
    // They keep title/url/snippet tied to the same anchor/container, avoiding
    // the mobile-Bing text-block pairing errors that made the displayed result
    // content drift from what the browser page showed.
    collect_browser_structured_results(&value, &mut results, &mut seen_urls, max);

    if results.len() < max {
        // Text blocks are useful as a mobile fallback when the runtime cannot
        // emit structured result records. They still tend to match the visible
        // result order better than the full-page anchor list.
        collect_browser_viewport_results(&value, &mut results, &mut seen_urls, max);
    }

    collect_browser_elements(&value, &mut |element| {
        if results.len() >= max {
            return;
        }
        let role = string_field(element, "role").to_ascii_lowercase();
        let tag = string_field(element, "tag").to_ascii_lowercase();
        let href = string_field(element, "href");
        if href.is_empty() || (role != "link" && tag != "a") {
            return;
        }
        let Some(url) = normalize_browser_result_url(&href) else {
            return;
        };
        if !seen_urls.insert(url.clone()) {
            return;
        }
        let title = first_non_empty_field(element, &["text", "label"]);
        let title = clean_search_result_title(&title, &url);
        if title.is_empty() || looks_like_search_navigation_title(&title) {
            return;
        }
        let snippet = browser_snippet_from_element(element, &title);
        results.push(SearchResult {
            title,
            url,
            snippet,
        });
    });

    results
}

fn collect_browser_structured_results(
    value: &serde_json::Value,
    results: &mut Vec<SearchResult>,
    seen_urls: &mut std::collections::HashSet<String>,
    max: usize,
) {
    for path in ["search_results", "page_state.search_results"] {
        let Some(items) = value_at_path(value, path).and_then(serde_json::Value::as_array) else {
            continue;
        };
        for item in items {
            if results.len() >= max {
                return;
            }
            let Some(object) = item.as_object() else {
                continue;
            };
            let raw_url = first_non_empty_field(object, &["url", "href", "link"]);
            let Some(url) = normalize_browser_result_url(&raw_url) else {
                continue;
            };
            if !seen_urls.insert(url.clone()) {
                continue;
            }
            let title = clean_search_result_title(
                &first_non_empty_field(object, &["title", "text", "label"]),
                &url,
            );
            if title.is_empty() || looks_like_search_navigation_title(&title) {
                continue;
            }
            let mut snippet = clean_browser_text(&first_non_empty_field(
                object,
                &["snippet", "description", "summary", "nearby_text"],
            ));
            if snippet == title {
                snippet.clear();
            }
            if snippet.len() > 360 {
                snippet.truncate(360);
                snippet = snippet.trim_end().to_string();
            }
            results.push(SearchResult {
                title,
                url,
                snippet,
            });
        }
        if !results.is_empty() {
            return;
        }
    }
}

fn collect_browser_elements<'a>(
    value: &'a serde_json::Value,
    visit: &mut impl FnMut(&'a serde_json::Map<String, serde_json::Value>),
) {
    for path in [
        "links",
        "page_state.links",
        "elements",
        "page_state.elements",
    ] {
        if let Some(elements) = value_at_path(value, path).and_then(serde_json::Value::as_array) {
            for element in elements {
                if let Some(object) = element.as_object() {
                    visit(object);
                }
            }
        }
    }
}

fn collect_browser_viewport_results(
    value: &serde_json::Value,
    results: &mut Vec<SearchResult>,
    seen_urls: &mut std::collections::HashSet<String>,
    max: usize,
) {
    let text_blocks = browser_visible_text_blocks(value);
    for index in 0..text_blocks.len() {
        if results.len() >= max {
            break;
        }
        let current = text_blocks[index].as_str();
        if visible_text_has_search_url(current)
            && index + 1 < text_blocks.len()
            && visible_text_has_search_url(&text_blocks[index + 1])
        {
            continue;
        }
        let Some(url) = visible_text_result_url(current) else {
            continue;
        };
        let Some(url) = normalize_browser_result_url(&url) else {
            continue;
        };
        if !seen_urls.insert(url.clone()) {
            continue;
        }
        let Some(title_index) = find_next_result_title(&text_blocks, index + 1) else {
            continue;
        };
        let title = text_blocks[title_index].clone();
        let snippet = find_next_result_snippet(&text_blocks, title_index + 1);
        results.push(SearchResult {
            title,
            url,
            snippet,
        });
    }
}

fn browser_visible_text_blocks(value: &serde_json::Value) -> Vec<String> {
    let mut texts = Vec::new();
    for path in [
        "viewport_map.visible_text_blocks",
        "page_state.viewport_map.visible_text_blocks",
    ] {
        let Some(blocks) = value_at_path(value, path).and_then(serde_json::Value::as_array) else {
            continue;
        };
        for block in blocks {
            let text = block
                .get("text")
                .and_then(serde_json::Value::as_str)
                .map(clean_browser_text)
                .unwrap_or_default();
            if text.is_empty() {
                continue;
            }
            if texts.last() == Some(&text) {
                continue;
            }
            texts.push(text);
        }
        if !texts.is_empty() {
            break;
        }
    }
    texts
}

fn find_next_result_title(texts: &[String], start: usize) -> Option<usize> {
    let end = (start + 5).min(texts.len());
    for (offset, text) in texts[start..end].iter().enumerate() {
        if visible_text_result_url(text).is_some() {
            continue;
        }
        if looks_like_search_navigation_title(text) || looks_like_visible_result_metadata(text) {
            continue;
        }
        if text.chars().count() >= 4 {
            return Some(start + offset);
        }
    }
    None
}

fn find_next_result_snippet(texts: &[String], start: usize) -> String {
    let end = (start + 3).min(texts.len());
    for text in &texts[start..end] {
        if visible_text_result_url(text).is_some() {
            break;
        }
        if looks_like_search_navigation_title(text) || looks_like_visible_result_metadata(text) {
            continue;
        }
        if text.chars().count() >= 8 {
            let mut snippet = text.clone();
            if snippet.len() > 360 {
                snippet.truncate(360);
                snippet = snippet.trim_end().to_string();
            }
            return snippet;
        }
    }
    String::new()
}

fn visible_text_has_search_url(text: &str) -> bool {
    visible_text_result_url(text).is_some()
}

fn visible_text_result_url(text: &str) -> Option<String> {
    let text = text.trim();
    if text.is_empty() {
        return None;
    }
    if let Some(url) = first_http_url(text) {
        return Some(url);
    }
    let token = text
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .trim_matches(|ch: char| matches!(ch, ',' | ';' | ':' | '。' | '，' | '；' | '：'));
    if looks_like_domain(token) {
        return Some(format!("https://{token}"));
    }
    None
}

fn first_http_url(text: &str) -> Option<String> {
    let start = text.find("https://").or_else(|| text.find("http://"))?;
    let rest = &text[start..];
    let end = rest
        .char_indices()
        .find_map(|(index, ch)| {
            if ch.is_whitespace() || matches!(ch, '›' | '>' | '。' | '，' | ',' | ';' | '；') {
                Some(index)
            } else {
                None
            }
        })
        .unwrap_or(rest.len());
    Some(rest[..end].trim_end_matches('/').to_string())
}

fn looks_like_domain(token: &str) -> bool {
    let token = token.trim_end_matches('/').to_ascii_lowercase();
    if token.contains('/') || token.contains('@') || token.len() < 4 {
        return false;
    }
    let Some((host, tld)) = token.rsplit_once('.') else {
        return false;
    };
    !host.is_empty()
        && tld.len() >= 2
        && tld.chars().all(|ch| ch.is_ascii_alphabetic())
        && host
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '.')
}

fn looks_like_visible_result_metadata(text: &str) -> bool {
    let lower = text.to_ascii_lowercase();
    lower.starts_with("http://")
        || lower.starts_with("https://")
        || looks_like_repeated_label(text)
        || looks_like_domain(text.split_whitespace().next().unwrap_or_default())
        || matches!(
            lower.as_str(),
            "网页" | "图片" | "视频" | "学术" | "词典" | "地图" | "更多"
        )
}

fn looks_like_repeated_label(text: &str) -> bool {
    let parts: Vec<&str> = text.split_whitespace().collect();
    if parts.len() == 2 && parts[0] == parts[1] {
        return true;
    }
    if parts.len() > 2 && parts.len() % 2 == 0 {
        let half = parts.len() / 2;
        return parts[..half] == parts[half..];
    }
    false
}

fn clean_search_result_title(title: &str, url: &str) -> String {
    let host = url
        .split_once("://")
        .map(|(_, rest)| rest.split('/').next().unwrap_or(rest))
        .unwrap_or_default()
        .trim_start_matches("www.")
        .to_ascii_lowercase();
    let mut candidate = clean_browser_text(title);
    if let Some(stripped) = candidate.strip_prefix("网页 ") {
        candidate = stripped.trim().to_string();
    }
    if let Some(index) = candidate
        .find(" http://")
        .or_else(|| candidate.find(" https://"))
    {
        candidate.truncate(index);
        candidate = candidate.trim().to_string();
    }
    if !host.is_empty() {
        let lower = candidate.to_ascii_lowercase();
        if lower == host || lower.starts_with(&format!("{host} ")) {
            candidate = candidate[host.len()..].trim().to_string();
        }
        let lower = candidate.to_ascii_lowercase();
        if lower.contains(&host) && (lower.contains('›') || lower.contains('>')) {
            if let Some(index) = lower.find(&host) {
                candidate.truncate(index);
                candidate = candidate.trim().to_string();
            }
        }
    }
    if looks_like_repeated_label(&candidate) {
        return String::new();
    }
    candidate
}

fn value_at_path<'a>(value: &'a serde_json::Value, path: &str) -> Option<&'a serde_json::Value> {
    let mut current = value;
    for segment in path.split('.') {
        current = current.get(segment)?;
    }
    Some(current)
}

fn string_field(element: &serde_json::Map<String, serde_json::Value>, field: &str) -> String {
    element
        .get(field)
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn first_non_empty_field(
    element: &serde_json::Map<String, serde_json::Value>,
    fields: &[&str],
) -> String {
    fields
        .iter()
        .map(|field| string_field(element, field))
        .find(|value| !value.is_empty())
        .unwrap_or_default()
}

fn browser_snippet_from_element(
    element: &serde_json::Map<String, serde_json::Value>,
    title: &str,
) -> String {
    let raw = first_non_empty_field(element, &["nearby_text", "parent_text"]);
    let mut snippet = clean_browser_text(&raw);
    if snippet == title {
        return String::new();
    }
    if let Some(stripped) = snippet.strip_prefix(title) {
        snippet = stripped
            .trim_start_matches(['-', '—', ':', '|', ' '])
            .to_string();
    }
    if snippet.len() > 360 {
        snippet.truncate(360);
        snippet = snippet.trim_end().to_string();
    }
    snippet
}

fn clean_browser_text(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn normalize_browser_result_url(raw: &str) -> Option<String> {
    let raw = raw.trim();
    if !(raw.starts_with("http://") || raw.starts_with("https://")) {
        return None;
    }
    let candidate = query_param(raw, "url")
        .or_else(|| query_param(raw, "u").and_then(|value| decode_bing_u_param(&value)))
        .filter(|value| value.starts_with("http://") || value.starts_with("https://"))
        .unwrap_or_else(|| raw.to_string());
    if is_search_engine_internal_url(&candidate) {
        return None;
    }
    Some(candidate)
}

fn decode_bing_u_param(value: &str) -> Option<String> {
    if value.starts_with("http://") || value.starts_with("https://") {
        return Some(value.to_string());
    }
    let encoded = value.strip_prefix("a1").unwrap_or(value);
    let bytes = {
        use base64::Engine as _;
        base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(encoded)
            .or_else(|_| base64::engine::general_purpose::URL_SAFE.decode(encoded))
            .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(encoded))
            .or_else(|_| base64::engine::general_purpose::STANDARD.decode(encoded))
            .ok()?
    };
    String::from_utf8(bytes).ok()
}

fn query_param(url: &str, name: &str) -> Option<String> {
    let query = url.split_once('?')?.1.split('#').next().unwrap_or_default();
    for part in query.split('&') {
        let (key, value) = part.split_once('=').unwrap_or((part, ""));
        if key == name {
            return urlencoding::decode(value)
                .ok()
                .map(|decoded| decoded.into_owned());
        }
    }
    None
}

fn is_search_engine_internal_url(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    let host = lower
        .split_once("://")
        .map(|(_, rest)| rest.split('/').next().unwrap_or(rest))
        .unwrap_or(lower.as_str());
    host.ends_with("bing.com")
        || host.ends_with("bing.net")
        || host.ends_with("microsoft.com")
        || lower.contains("/search?")
        || lower.contains("/images/search")
        || lower.contains("/videos/search")
        || lower.contains("/maps")
        || lower.contains("/ck/a")
        || lower.contains("/aclick")
}

fn looks_like_search_navigation_title(title: &str) -> bool {
    let lower = title.to_ascii_lowercase();
    matches!(
        lower.as_str(),
        "images" | "videos" | "maps" | "news" | "shopping" | "search" | "bing"
    ) || ["图片", "视频", "地图", "新闻", "购物", "搜索"]
        .iter()
        .any(|term| title == *term)
}

fn format_results_with_diagnostics(
    query: &str,
    results: &[SearchResult],
    diagnostics: &str,
) -> String {
    let results_json: Vec<_> = results
        .iter()
        .enumerate()
        .map(|(index, result)| {
            serde_json::json!({
                "index": index + 1,
                "title": result.title,
                "url": result.url,
                "snippet": result.snippet,
            })
        })
        .collect();
    serde_json::to_string_pretty(&serde_json::json!({
        "query": query,
        "diagnostics": diagnostics,
        "result_count": results_json.len(),
        "results": results_json,
    }))
    .unwrap_or_else(|_| {
        let mut output =
            format!("Search results for: {query}\nSearch diagnostics: {diagnostics}\n\n");
        for (index, result) in results.iter().enumerate() {
            output.push_str(&format!("{}. **{}**\n", index + 1, result.title));
            output.push_str(&format!("   {}\n", result.url));
            if !result.snippet.is_empty() {
                output.push_str(&format!("   {}\n", result.snippet));
            }
            output.push('\n');
        }
        output.trim_end().to_string()
    })
}

fn cache_key(query: &str, count: usize, language: &str, freshness: &str, mode: &str) -> String {
    format!("{mode}\0{query}\0{count}\0{language}\0{freshness}")
}

fn cache_get(key: &str) -> Option<String> {
    let mut cache = SEARCH_CACHE.lock().ok()?;
    let entry = cache.entries.get(key)?;
    if entry.inserted.elapsed() > CACHE_TTL {
        cache.entries.remove(key);
        cache.order.retain(|item| item != key);
        return None;
    }
    Some(entry.body.clone())
}

fn cache_put(key: String, body: String) {
    let Ok(mut cache) = SEARCH_CACHE.lock() else {
        return;
    };
    if !cache.entries.contains_key(&key) {
        cache.order.push_back(key.clone());
    }
    cache.entries.insert(
        key,
        CachedEntry {
            body,
            inserted: Instant::now(),
        },
    );
    while cache.order.len() > CACHE_MAX_ENTRIES {
        if let Some(oldest) = cache.order.pop_front() {
            cache.entries.remove(&oldest);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptor_exposes_web_search() {
        let descriptor = descriptor();
        assert_eq!(descriptor.name, "web_search");
        assert!(
            descriptor.parameters["required"]
                .as_array()
                .unwrap()
                .iter()
                .any(|value| value.as_str() == Some("query"))
        );
    }

    #[test]
    fn browser_bing_home_url_avoids_direct_query_search() {
        assert_eq!(
            browser_bing_home_url("zh-Hans"),
            "https://cn.bing.com/?setlang=zh-Hans&cc="
        );
    }

    #[test]
    fn browser_search_type_attempts_submit_visible_search_field() {
        let attempts = browser_search_type_attempts("重庆 近期 活动 2026年8月");
        assert_eq!(attempts[0]["selector"], "#sb_form_q");
        assert_eq!(attempts[0]["text"], "重庆 近期 活动 2026年8月");
        assert_eq!(attempts[0]["submit"], true);
        assert_eq!(attempts[0]["submit_selector"], "#sb_form");
        assert_eq!(attempts[0]["clear_first"], true);
        assert!(
            attempts
                .iter()
                .any(|attempt| attempt["selector"] == "input[name='q']")
        );
        assert!(
            attempts
                .iter()
                .any(|attempt| attempt["label"] == "搜索网页")
        );
    }

    #[test]
    fn parses_browser_snapshot_results() {
        let output = serde_json::json!({
            "success": true,
            "elements": [
                {
                    "role": "link",
                    "tag": "a",
                    "href": "https://example.com/event",
                    "text": "重庆活动",
                    "nearby_text": "重庆活动 近期展览和演出安排"
                }
            ]
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "重庆活动");
        assert_eq!(results[0].url, "https://example.com/event");
        assert_eq!(results[0].snippet, "近期展览和演出安排");
    }

    #[test]
    fn parses_browser_snapshot_page_state_results_and_dedupes() {
        let output = serde_json::json!({
            "success": true,
            "page_state": {
                "elements": [
                    {
                        "role": "link",
                        "tag": "a",
                        "href": "https://example.com/same",
                        "text": "First"
                    },
                    {
                        "role": "link",
                        "tag": "a",
                        "href": "https://example.com/same",
                        "text": "Duplicate"
                    },
                    {
                        "role": "link",
                        "tag": "a",
                        "href": "https://example.com/other",
                        "text": "Second"
                    }
                ]
            }
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].title, "First");
        assert_eq!(results[1].title, "Second");
    }

    #[test]
    fn parses_mobile_bing_viewport_text_results_before_element_links() {
        let output = serde_json::json!({
            "success": true,
            "viewport_map": {
                "visible_text_blocks": [
                    {"text": "网页"},
                    {"text": "goodexpos.com"},
                    {"text": "https://www.goodexpos.com › coming-article"},
                    {"text": "2026年7月北京展会排期-2026年7月展会 - 优展网"},
                    {"text": "2026年7月北京展会排期-2026年7月展会,优展网平台是专业展会服务网站"},
                    {"text": "zhanxun.cn"},
                    {"text": "https://www.zhanxun.cn › news"},
                    {"text": "2026年7月北京展会一览表-展讯网会展平台"},
                    {"text": "2026年7月将有100+场展会"}
                ]
            },
            "elements": [
                {"role": "link", "tag": "a", "href": "https://baike.baidu.com/item/beijing", "text": "北京市_百度百科"}
            ]
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].url, "https://www.goodexpos.com");
        assert_eq!(
            results[0].title,
            "2026年7月北京展会排期-2026年7月展会 - 优展网"
        );
        assert_eq!(results[1].url, "https://www.zhanxun.cn");
        assert_eq!(results[1].title, "2026年7月北京展会一览表-展讯网会展平台");
        assert_eq!(results[2].url, "https://baike.baidu.com/item/beijing");
    }

    #[test]
    fn normalizes_bing_redirect_links() {
        let output = serde_json::json!({
            "success": true,
            "elements": [
                {
                    "role": "link",
                    "tag": "a",
                    "href": "https://www.bing.com/ck/a?u=a1aHR0cHM6Ly9leGFtcGxlLmNvbS9iaW5nLXJlc3VsdA",
                    "text": "Redirected"
                }
            ]
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].url, "https://example.com/bing-result");
    }

    #[test]
    fn filters_browser_search_engine_internal_links() {
        let output = serde_json::json!({
            "success": true,
            "elements": [
                {"role": "link", "tag": "a", "href": "https://www.bing.com/search?q=x", "text": "Search"},
                {"role": "link", "tag": "a", "href": "https://example.com/result", "text": "Result"}
            ]
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].url, "https://example.com/result");
    }

    #[test]
    fn browser_parser_returns_empty_for_invalid_output() {
        assert!(parse_browser_search_results("not json", 5).is_empty());
        assert!(parse_browser_search_results(r#"{"success":false}"#, 5).is_empty());
    }

    #[test]
    fn cleans_structured_mobile_bing_titles() {
        let output = serde_json::json!({
            "success": true,
            "search_results": [
                {
                    "title": "杭州7月活动汇总（持续更新） 杭州本地宝 https://hz.bendibao.com › xiuxian › date.php",
                    "url": "https://hz.bendibao.com/xiuxian/date.php?type=4&y=2026&m=07&f=0",
                    "snippet": "2026年7月杭州活动时间表"
                },
                {
                    "title": "豆瓣 豆瓣 https://www.douban.com › location › hangzhou › events › future...",
                    "url": "https://www.douban.com/location/hangzhou/events/future-exhibition",
                    "snippet": "杭州展览活动"
                }
            ],
            "links": [
                {"role":"link","tag":"a","href":"https://baike.baidu.com/item/hangzhou","text":"杭州市_百度百科"}
            ]
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].title, "杭州7月活动汇总（持续更新） 杭州本地宝");
        assert_eq!(
            results[0].url,
            "https://hz.bendibao.com/xiuxian/date.php?type=4&y=2026&m=07&f=0"
        );
        assert_eq!(results[1].title, "杭州市_百度百科");
    }

    #[test]
    fn formats_search_results_as_json_with_explicit_count() {
        let body = format_results_with_diagnostics(
            "napaxi",
            &[SearchResult {
                title: "Napaxi result".to_string(),
                url: "https://example.com/napaxi".to_string(),
                snippet: "Useful snippet".to_string(),
            }],
            "source=browser; fallback=disabled",
        );
        let value: serde_json::Value = serde_json::from_str(&body).unwrap();
        assert_eq!(value["query"], "napaxi");
        assert_eq!(value["diagnostics"], "source=browser; fallback=disabled");
        assert_eq!(value["result_count"], 1);
        assert_eq!(value["results"][0]["index"], 1);
        assert_eq!(value["results"][0]["url"], "https://example.com/napaxi");
    }
}
