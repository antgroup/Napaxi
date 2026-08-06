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
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const BROWSER_SEARCH_TIMEOUT: Duration = Duration::from_secs(45);

#[cfg(target_os = "android")]
const USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 \
    (KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36";

#[cfg(target_os = "ios")]
const USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) \
    AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

#[cfg(not(any(target_os = "android", target_os = "ios")))]
const USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
    AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36";

static HTTP_CLIENT: LazyLock<reqwest::Client> = LazyLock::new(|| {
    reqwest::Client::builder()
        .gzip(true)
        .brotli(true)
        .deflate(true)
        .user_agent(USER_AGENT)
        .redirect(reqwest::redirect::Policy::limited(5))
        .timeout(REQUEST_TIMEOUT)
        .build()
        .expect("failed to build web-search HTTP client")
});

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
        description: "Search the web and return structured results with title, URL, and snippet. Supports optional count, language, and freshness filters.".to_string(),
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

    let cache_mode = if browser_context.is_some() {
        "browser"
    } else {
        "http"
    };
    let key = cache_key(query, count, language, freshness, cache_mode);
    if let Some(cached) = cache_get(&key) {
        tracing::debug!(query, cache_mode, "web_search cache hit");
        return Ok(cached);
    }

    let results = match browser_context {
        Some(context) => {
            tracing::info!(query, "web_search using browser-backed search");
            match search_with_browser(&context, query, count, language, freshness).await {
                Ok(results) if !results.is_empty() => results,
                Ok(_) => {
                    tracing::warn!(
                        query,
                        "web_search browser path returned no results; falling back to HTTP search"
                    );
                    search_with_fallback(query, count, language, freshness).await?
                }
                Err(error) => {
                    tracing::warn!(query, error = %error, "web_search browser path failed; falling back to HTTP search");
                    search_with_fallback(query, count, language, freshness).await?
                }
            }
        }
        None => {
            tracing::info!(
                query,
                "web_search using HTTP fallback because no browser host bridge is available"
            );
            search_with_fallback(query, count, language, freshness).await?
        }
    };
    let body = format_results(query, &results);
    cache_put(key, body.clone());
    Ok(body)
}

async fn search_with_fallback(
    query: &str,
    count: usize,
    language: &str,
    freshness: &str,
) -> Result<Vec<SearchResult>, String> {
    let mut last_error = None;
    for provider in [SearchProvider::Bing, SearchProvider::DuckDuckGo] {
        match provider.search(query, count, language, freshness).await {
            Ok(results) if !results.is_empty() => return Ok(results),
            Ok(_) => last_error = Some(format!("{} returned no results", provider.id())),
            Err(error) => last_error = Some(error),
        }
    }
    Err(last_error.unwrap_or_else(|| "all search providers returned no results".to_string()))
}

async fn search_with_browser(
    context: &BrowserSearchContext,
    query: &str,
    count: usize,
    language: &str,
    freshness: &str,
) -> Result<Vec<SearchResult>, String> {
    let url = browser_bing_search_url(query, count, language, freshness);
    let open_output = crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_OPEN,
        serde_json::json!({
            "url": url,
            // Android WebView's mobile Bing page can return a sparse snapshot
            // immediately after load. The desktop result page is more stable
            // for the generic browser element parser and still stays inside
            // the host browser surface.
            "mode": "desktop",
            "force_reload": true,
        }),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await?;

    let mut results = parse_browser_search_results(&open_output, count);
    tracing::debug!(query, result_count = results.len(), "web_search parsed browser_open output");
    if results.is_empty() {
        let wait_output = crate::tool_registry::request_host_tool_execution_with_context(
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
        results = parse_browser_search_results(&wait_output, count);
        tracing::debug!(query, result_count = results.len(), "web_search parsed browser_wait output");
    }
    if results.is_empty() {
        let snapshot_output = crate::tool_registry::request_host_tool_execution_with_context(
            context.bridge.clone(),
            crate::browser_tools::BROWSER_SNAPSHOT,
            serde_json::json!({"screenshot_mode": "never"}),
            BROWSER_SEARCH_TIMEOUT,
            Some(&context.tool_context),
        )
        .await?;
        results = parse_browser_search_results(&snapshot_output, count);
        tracing::debug!(query, result_count = results.len(), "web_search parsed browser_snapshot output");
    }
    Ok(results)
}

fn browser_bing_search_url(query: &str, count: usize, language: &str, freshness: &str) -> String {
    bing_search_url(query, count, language, freshness)
}

fn bing_search_url(query: &str, count: usize, language: &str, freshness: &str) -> String {
    let encoded_query = encode_search_query(query);
    let mut url = format!(
        "https://www.bing.com/search?q={}&pq={}&setlang={}&cc=&count={}",
        encoded_query,
        encoded_query,
        urlencoding::encode(language),
        count * 2,
    );
    if let Some(filter) = freshness_filter(freshness) {
        url.push_str("&filters=ex1:ez");
        url.push_str(filter);
    }
    url
}

#[derive(Debug, Clone, Copy)]
enum SearchProvider {
    Bing,
    DuckDuckGo,
}

impl SearchProvider {
    fn id(self) -> &'static str {
        match self {
            Self::Bing => "bing",
            Self::DuckDuckGo => "duckduckgo",
        }
    }

    async fn search(
        self,
        query: &str,
        count: usize,
        language: &str,
        freshness: &str,
    ) -> Result<Vec<SearchResult>, String> {
        match self {
            Self::Bing => search_bing(query, count, language, freshness).await,
            Self::DuckDuckGo => search_duckduckgo(query, count).await,
        }
    }
}

async fn search_bing(
    query: &str,
    count: usize,
    language: &str,
    freshness: &str,
) -> Result<Vec<SearchResult>, String> {
    let url = bing_search_url(query, count, language, freshness);
    let html = http_fetch(&url).await?;
    Ok(parse_bing_results(&html, count))
}

async fn search_duckduckgo(query: &str, count: usize) -> Result<Vec<SearchResult>, String> {
    let url = format!(
        "https://html.duckduckgo.com/html/?q={}",
        encode_search_query(query)
    );
    let html = http_fetch(&url).await?;
    Ok(parse_ddg_results(&html, count))
}

fn freshness_filter(freshness: &str) -> Option<&'static str> {
    match freshness {
        "day" => Some("1"),
        "week" => Some("2"),
        "month" => Some("3"),
        "" => None,
        _ => None,
    }
}

fn encode_search_query(query: &str) -> String {
    urlencoding::encode(query).replace("%20", "+")
}

async fn http_fetch(url: &str) -> Result<String, String> {
    let response = HTTP_CLIENT
        .get(url)
        .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
        .send()
        .await
        .map_err(|error| format!("web_search request failed: {error}"))?;
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "web_search request returned HTTP {} {}",
            status.as_u16(),
            status.canonical_reason().unwrap_or("")
        ));
    }
    let body = response
        .text()
        .await
        .map_err(|error| format!("web_search response read failed: {error}"))?;
    if body.is_empty() {
        Err("web_search response was empty".to_string())
    } else {
        Ok(body)
    }
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
        let title = clean_browser_text(&title);
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

fn collect_browser_elements<'a>(
    value: &'a serde_json::Value,
    visit: &mut impl FnMut(&'a serde_json::Map<String, serde_json::Value>),
) {
    for path in ["elements", "page_state.elements"] {
        if let Some(elements) = value_at_path(value, path).and_then(serde_json::Value::as_array) {
            for element in elements {
                if let Some(object) = element.as_object() {
                    visit(object);
                }
            }
        }
    }
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

fn parse_bing_results(html: &str, max: usize) -> Vec<SearchResult> {
    let mut results = Vec::new();
    for chunk in html.split("class=\"b_algo\"") {
        if results.len() >= max {
            break;
        }
        let url = match extract_attr(chunk, "<a", "href") {
            Some(value) if value.starts_with("http") => value,
            _ => continue,
        };
        let title = extract_element_inner(chunk, "h2")
            .map(|html| strip_tags(&html))
            .unwrap_or_default();
        if title.is_empty() {
            continue;
        }
        results.push(SearchResult {
            title,
            url,
            snippet: extract_snippet_bing(chunk),
        });
    }
    results
}

fn extract_snippet_bing(chunk: &str) -> String {
    if let Some(snippet) = extract_between(chunk, "class=\"b_lineclamp", "</p>") {
        let snippet = snippet
            .find('>')
            .map(|index| &snippet[index + 1..])
            .unwrap_or(&snippet);
        let cleaned = strip_tags(snippet);
        if !cleaned.is_empty() {
            return cleaned;
        }
    }
    if let Some(caption) = extract_between(chunk, "class=\"b_caption\"", "</div>")
        && let Some(paragraph) = extract_between(&caption, "<p>", "</p>")
            .or_else(|| extract_between(&caption, "<p ", "</p>"))
    {
        let cleaned = strip_tags(&paragraph);
        if !cleaned.is_empty() {
            return cleaned;
        }
    }
    String::new()
}

fn parse_ddg_results(html: &str, max: usize) -> Vec<SearchResult> {
    let mut results = Vec::new();
    for chunk in html.split("class=\"result__a\"") {
        if results.len() >= max {
            break;
        }
        let url = match extract_attr_from_remainder(chunk, "href") {
            Some(value) if value.starts_with("http") => value,
            _ => continue,
        };
        let title = extract_between(chunk, ">", "</a>")
            .map(|html| strip_tags(&html))
            .filter(|title| !title.is_empty())
            .unwrap_or_default();
        if title.is_empty() {
            continue;
        }
        let snippet = extract_between(chunk, "class=\"result__snippet\"", "</a>")
            .or_else(|| extract_between(chunk, "class=\"result__snippet\"", "</td>"))
            .map(|html| {
                let html = html
                    .find('>')
                    .map(|index| &html[index + 1..])
                    .unwrap_or(&html);
                strip_tags(html)
            })
            .unwrap_or_default();
        results.push(SearchResult {
            title,
            url,
            snippet,
        });
    }
    results
}

fn format_results(query: &str, results: &[SearchResult]) -> String {
    let mut output = format!("Search results for: {query}\n\n");
    for (index, result) in results.iter().enumerate() {
        output.push_str(&format!("{}. **{}**\n", index + 1, result.title));
        output.push_str(&format!("   {}\n", result.url));
        if !result.snippet.is_empty() {
            output.push_str(&format!("   {}\n", result.snippet));
        }
        output.push('\n');
    }
    output
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
    while cache.entries.len() > CACHE_MAX_ENTRIES {
        let Some(oldest) = cache.order.pop_front() else {
            break;
        };
        cache.entries.remove(&oldest);
    }
}

fn extract_between(text: &str, start_marker: &str, end_marker: &str) -> Option<String> {
    let start = text.find(start_marker)? + start_marker.len();
    let remaining = &text[start..];
    let end = remaining.find(end_marker)?;
    Some(remaining[..end].to_string())
}

fn extract_element_inner(text: &str, tag: &str) -> Option<String> {
    let open_marker = format!("<{tag}");
    let close_marker = format!("</{tag}>");
    let tag_start = text.find(&open_marker)?;
    let content_start = text[tag_start..].find('>')? + tag_start + 1;
    let content_end = text[content_start..].find(&close_marker)? + content_start;
    Some(text[content_start..content_end].to_string())
}

fn extract_attr(text: &str, tag_start: &str, attr: &str) -> Option<String> {
    let tag_begin = text.find(tag_start)?;
    let tag_end = text[tag_begin..].find('>').map(|index| tag_begin + index)?;
    extract_attr_from_remainder(&text[tag_begin..tag_end], attr)
}

fn extract_attr_from_remainder(text: &str, attr: &str) -> Option<String> {
    let needle = format!("{attr}=\"");
    let start = text.find(&needle)? + needle.len();
    let remaining = &text[start..];
    let end = remaining.find('"')?;
    Some(remaining[..end].to_string())
}

fn strip_tags(html: &str) -> String {
    let mut result = String::with_capacity(html.len());
    let mut in_tag = false;
    for ch in html.chars() {
        match ch {
            '<' => in_tag = true,
            '>' => in_tag = false,
            _ if !in_tag => result.push(ch),
            _ => {}
        }
    }
    result
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
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
    fn browser_bing_url_reuses_http_bing_parameters() {
        assert_eq!(
            browser_bing_search_url("重庆 近期 活动 2026年8月", 5, "zh-Hans", ""),
            "https://www.bing.com/search?q=%E9%87%8D%E5%BA%86+%E8%BF%91%E6%9C%9F+%E6%B4%BB%E5%8A%A8+2026%E5%B9%B48%E6%9C%88&pq=%E9%87%8D%E5%BA%86+%E8%BF%91%E6%9C%9F+%E6%B4%BB%E5%8A%A8+2026%E5%B9%B48%E6%9C%88&setlang=zh-Hans&cc=&count=10"
        );
    }

    #[test]
    fn encodes_search_query_spaces_as_plus() {
        assert_eq!(
            encode_search_query("napaxi web search"),
            "napaxi+web+search"
        );
        assert_eq!(
            encode_search_query("中文 query"),
            "%E4%B8%AD%E6%96%87+query"
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
    fn parses_bing_result_chunks() {
        let html = r#"
          <li class="b_algo"><h2><a href="https://example.com">Example &amp; Test</a></h2>
          <div class="b_caption"><p>A useful snippet.</p></div></li>
        "#;
        let results = parse_bing_results(html, 5);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "Example & Test");
        assert_eq!(results[0].url, "https://example.com");
        assert_eq!(results[0].snippet, "A useful snippet.");
    }

    #[test]
    fn parses_duckduckgo_result_chunks() {
        let html = r#"
          <a rel="nofollow" class="result__a" href="https://example.com/ddg">Duck Result</a>
          <a class="result__snippet">Duck snippet</a>
        "#;
        let results = parse_ddg_results(html, 5);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "Duck Result");
        assert_eq!(results[0].url, "https://example.com/ddg");
        assert_eq!(results[0].snippet, "Duck snippet");
    }
}
