//! Mobile web search builtin tool.

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use std::sync::LazyLock;

use crate::tool_registry::ToolDescriptor;

pub const WEB_SEARCH_TOOL_NAME: &str = "web_search";

const DEFAULT_COUNT: usize = 5;
const MAX_COUNT: usize = 10;
const CACHE_TTL: Duration = Duration::from_secs(15 * 60);
const CACHE_MAX_ENTRIES: usize = 64;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

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

pub async fn execute(params: serde_json::Value) -> Result<String, String> {
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

    let key = cache_key(query, count, language, freshness);
    if let Some(cached) = cache_get(&key) {
        return Ok(cached);
    }

    let results = search_with_fallback(query, count, language, freshness).await?;
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
    let mut url = format!(
        "https://www.bing.com/search?q={}&setlang={}&cc=&count={}",
        urlencoding::encode(query),
        urlencoding::encode(language),
        count * 2,
    );
    if let Some(filter) = match freshness {
        "day" => Some("1"),
        "week" => Some("2"),
        "month" => Some("3"),
        "" => None,
        _ => None,
    } {
        url.push_str("&filters=ex1:ez");
        url.push_str(filter);
    }

    let html = http_fetch(&url).await?;
    Ok(parse_bing_results(&html, count))
}

async fn search_duckduckgo(query: &str, count: usize) -> Result<Vec<SearchResult>, String> {
    let url = format!(
        "https://html.duckduckgo.com/html/?q={}",
        urlencoding::encode(query)
    );
    let html = http_fetch(&url).await?;
    Ok(parse_ddg_results(&html, count))
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
        let title = extract_between(chunk, "<h2>", "</h2>")
            .or_else(|| extract_between(chunk, "<h2 ", "</h2>"))
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

fn cache_key(query: &str, count: usize, language: &str, freshness: &str) -> String {
    format!("{query}\0{count}\0{language}\0{freshness}")
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
