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

#[path = "web_search/parser.rs"]
mod parser;

use parser::{browser_observation_diagnostics, host_tool_error, parse_browser_search_results};

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
    freshness: &str,
) -> Result<Vec<SearchResult>, String> {
    let direct_url = browser_bing_search_url(query, language, freshness);
    let direct_opened = match crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_OPEN,
        serde_json::json!({
            "url": direct_url,
            "mode": "mobile",
            "force_reload": true,
        }),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await
    {
        Ok(_) => true,
        Err(error) => {
            tracing::debug!(query, error = %error, "web_search direct Bing URL failed; falling back to homepage flow");
            false
        }
    };

    if direct_opened {
        for milliseconds in [1200_u64, 2200, 3500] {
            if let Some(results) =
                get_text_browser_search_results(context, query, count, milliseconds).await?
            {
                return Ok(results);
            }
            if let Some(results) = snapshot_browser_search_results(context, query, count).await? {
                return Ok(results);
            }
        }
    }

    // Fallback to the visible homepage flow that has proven useful on Android
    // WebView when direct /search?q=... navigation is intercepted or returns a
    // partially rendered page.
    let url = browser_bing_home_url(language);
    crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_OPEN,
        serde_json::json!({
            "url": url,
            "mode": "mobile",
            "force_reload": true,
        }),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await?;

    let initial_observation = crate::tool_registry::request_host_tool_execution_with_context(
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
    let initial_results = parse_browser_search_results(&initial_observation, count);
    if !initial_results.is_empty() {
        tracing::debug!(
            query,
            result_count = initial_results.len(),
            "web_search parsed initial browser_wait output"
        );
        return Ok(initial_results);
    }

    let mut last_type_error = None;
    for params in browser_search_type_attempts(query) {
        let type_output = match crate::tool_registry::request_host_tool_execution_with_context(
            context.bridge.clone(),
            crate::browser_tools::BROWSER_TYPE,
            params,
            BROWSER_SEARCH_TIMEOUT,
            Some(&context.tool_context),
        )
        .await
        {
            Ok(output) => output,
            Err(error) => {
                tracing::debug!(query, error = %error, "web_search browser_type bridge error");
                last_type_error = Some(error);
                if let Some(results) =
                    get_text_browser_search_results(context, query, count, 800).await?
                {
                    return Ok(results);
                }
                if let Some(results) =
                    snapshot_browser_search_results(context, query, count).await?
                {
                    return Ok(results);
                }
                continue;
            }
        };
        if let Some(error) = host_tool_error(&type_output) {
            tracing::debug!(query, error = %error, "web_search browser_type attempt failed");
            last_type_error = Some(error);
            if let Some(results) =
                get_text_browser_search_results(context, query, count, 800).await?
            {
                return Ok(results);
            }
            if let Some(results) = snapshot_browser_search_results(context, query, count).await? {
                return Ok(results);
            }
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
            if results.is_empty()
                && let Some(text_results) =
                    get_text_browser_search_results(context, query, count, 0).await?
            {
                results = text_results;
            }
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

async fn get_text_browser_search_results(
    context: &BrowserSearchContext,
    query: &str,
    count: usize,
    wait_milliseconds: u64,
) -> Result<Option<Vec<SearchResult>>, String> {
    if wait_milliseconds > 0 {
        let _ = crate::tool_registry::request_host_tool_execution_with_context(
            context.bridge.clone(),
            crate::browser_tools::BROWSER_WAIT,
            serde_json::json!({
                "milliseconds": wait_milliseconds,
                "screenshot_mode": "never",
            }),
            BROWSER_SEARCH_TIMEOUT,
            Some(&context.tool_context),
        )
        .await;
    }
    let output = match crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_GET_TEXT,
        serde_json::json!({}),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await
    {
        Ok(output) => output,
        Err(error) => {
            tracing::debug!(
                query,
                error = %error,
                "web_search browser_get_text unavailable or failed"
            );
            return Ok(None);
        }
    };
    let results = parse_browser_search_results(&output, count);
    tracing::debug!(
        query,
        result_count = results.len(),
        diagnostics = %browser_observation_diagnostics(&output),
        "web_search parsed browser_get_text output"
    );
    Ok((!results.is_empty()).then_some(results))
}

async fn snapshot_browser_search_results(
    context: &BrowserSearchContext,
    query: &str,
    count: usize,
) -> Result<Option<Vec<SearchResult>>, String> {
    let snapshot_output = crate::tool_registry::request_host_tool_execution_with_context(
        context.bridge.clone(),
        crate::browser_tools::BROWSER_SNAPSHOT,
        serde_json::json!({"screenshot_mode": "never"}),
        BROWSER_SEARCH_TIMEOUT,
        Some(&context.tool_context),
    )
    .await?;
    let results = parse_browser_search_results(&snapshot_output, count);
    tracing::debug!(
        query,
        result_count = results.len(),
        diagnostics = %browser_observation_diagnostics(&snapshot_output),
        "web_search parsed recovery browser_snapshot output"
    );
    Ok((!results.is_empty()).then_some(results))
}

fn browser_bing_search_url(query: &str, language: &str, freshness: &str) -> String {
    let mut url = format!(
        "https://www.bing.com/search?q={}&setlang={}",
        urlencoding::encode(query),
        urlencoding::encode(language)
    );
    match freshness {
        "day" => url.push_str("&filters=ex1%3A%22ez1%22"),
        "week" => url.push_str("&filters=ex1%3A%22ez2%22"),
        "month" => url.push_str("&filters=ex1%3A%22ez3%22"),
        _ => {}
    }
    url
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
    fn browser_bing_search_url_uses_real_search_url() {
        assert_eq!(
            browser_bing_search_url("test query", "zh-Hans", ""),
            "https://www.bing.com/search?q=test%20query&setlang=zh-Hans"
        );
        assert_eq!(
            browser_bing_search_url("test query", "en-US", "day"),
            "https://www.bing.com/search?q=test%20query&setlang=en-US&filters=ex1%3A%22ez1%22"
        );
    }

    #[test]
    fn browser_bing_home_url_supports_visible_field_fallback() {
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
            "url": "https://cn.bing.com/search?q=test",
            "search_results": [
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
                "url": "https://cn.bing.com/search?q=test",
                "search_results": [
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
            "url": "https://cn.bing.com/search?q=test",
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
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].url, "https://www.goodexpos.com");
        assert_eq!(
            results[0].title,
            "2026年7月北京展会排期-2026年7月展会 - 优展网"
        );
        assert_eq!(results[1].url, "https://www.zhanxun.cn");
        assert_eq!(results[1].title, "2026年7月北京展会一览表-展讯网会展平台");
    }

    #[test]
    fn normalizes_bing_redirect_links() {
        let output = serde_json::json!({
            "success": true,
            "url": "https://cn.bing.com/search?q=test",
            "search_results": [
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
            "url": "https://cn.bing.com/search?q=test",
            "search_results": [
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
            "url": "https://cn.bing.com/search?q=test",
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
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].title, "杭州7月活动汇总（持续更新） 杭州本地宝");
        assert_eq!(
            results[0].url,
            "https://hz.bendibao.com/xiuxian/date.php?type=4&y=2026&m=07&f=0"
        );
    }

    #[test]
    fn does_not_parse_target_site_footer_links_as_search_results() {
        let output = serde_json::json!({
            "success": true,
            "url": "https://www.ososhow.com/month/concert-7.html",
            "title": "7月音乐会",
            "search_results": [
                {
                    "title": "ososhow.com",
                    "url": "https://www.ososhow.com/month/concert-7.html",
                    "snippet": "https://www.ososhow.com › month"
                },
                {"title": "京ICP备10036305号-7", "url": "https://beian.miit.gov.cn/"},
                {"title": "京公网安备11010802047360号", "url": "https://beian.mps.gov.cn/#/query/webSearch?code=11010802047360"}
            ],
            "links": [
                {"role":"link","tag":"a","href":"https://beian.miit.gov.cn/","text":"京ICP备10036305号-7"}
            ]
        })
        .to_string();

        assert!(parse_browser_search_results(&output, 5).is_empty());
    }

    #[test]
    fn parses_browser_get_text_lines() {
        let output = serde_json::json!({
            "success": true,
            "url": "https://www.bing.com/search?q=test",
            "title": "test - Search",
            "text": "网页\nexample.com\nhttps://example.com › article\nExample title\nExample snippet about the result\nsecond.test\nhttps://second.test/path\nSecond title\nSecond useful snippet"
        })
        .to_string();

        let results = parse_browser_search_results(&output, 5);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].url, "https://example.com");
        assert_eq!(results[0].title, "Example title");
        assert_eq!(results[1].url, "https://second.test/path");
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
