use super::SearchResult;

pub(super) fn host_tool_error(output: &str) -> Option<String> {
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

pub(super) fn browser_observation_diagnostics(output: &str) -> String {
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

pub(super) fn parse_browser_search_results(output: &str, max: usize) -> Vec<SearchResult> {
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

    if !is_bing_search_observation(&value) {
        return Vec::new();
    }

    let mut results = Vec::new();
    let mut seen_urls = std::collections::HashSet::new();

    // Prefer structured records emitted from Bing result containers. Do not
    // fall back to the page-wide anchor list: after a result click or redirect,
    // generic links can be footer/legal links from a target site rather than
    // search results.
    collect_browser_structured_results(&value, &mut results, &mut seen_urls, max);

    if results.len() < max {
        collect_browser_text_results(&value, &mut results, &mut seen_urls, max);
    }

    if results.len() < max {
        // Text blocks mirror OpenMinis' effective get_text approach: trust the
        // visible Bing result text before any DOM-wide link inventory.
        collect_browser_viewport_results(&value, &mut results, &mut seen_urls, max);
    }

    results
}

fn is_bing_search_observation(value: &serde_json::Value) -> bool {
    let url = value
        .get("url")
        .or_else(|| value_at_path(value, "page_state.url"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_ascii_lowercase();
    if url.is_empty() {
        return false;
    }
    let host_path = url
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(url.as_str());
    let host = host_path.split('/').next().unwrap_or_default();
    let path = host_path
        .split_once('/')
        .map(|(_, rest)| format!("/{rest}"))
        .unwrap_or_default();
    (host == "bing.com"
        || host.ends_with(".bing.com")
        || host == "bing.net"
        || host.ends_with(".bing.net"))
        && path.starts_with("/search")
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
            } else if let Some(rest) = snippet.strip_prefix(&title) {
                snippet = rest.trim_start().to_string();
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

fn collect_browser_text_results(
    value: &serde_json::Value,
    results: &mut Vec<SearchResult>,
    seen_urls: &mut std::collections::HashSet<String>,
    max: usize,
) {
    let text = value
        .get("text")
        .or_else(|| value_at_path(value, "page_state.text"))
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    if text.trim().is_empty() {
        return;
    }
    let lines = text
        .lines()
        .map(clean_browser_text)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    collect_visible_text_sequence_results(&lines, results, seen_urls, max);
}

fn collect_browser_viewport_results(
    value: &serde_json::Value,
    results: &mut Vec<SearchResult>,
    seen_urls: &mut std::collections::HashSet<String>,
    max: usize,
) {
    let text_blocks = browser_visible_text_blocks(value);
    collect_visible_text_sequence_results(&text_blocks, results, seen_urls, max);
}

fn collect_visible_text_sequence_results(
    texts: &[String],
    results: &mut Vec<SearchResult>,
    seen_urls: &mut std::collections::HashSet<String>,
    max: usize,
) {
    for index in 0..texts.len() {
        if results.len() >= max {
            break;
        }
        let current = texts[index].as_str();
        if visible_text_has_search_url(current)
            && index + 1 < texts.len()
            && visible_text_has_search_url(&texts[index + 1])
        {
            continue;
        }
        let Some(url) = visible_text_result_url(current) else {
            continue;
        };
        let Some(url) = normalize_browser_result_url(&url) else {
            continue;
        };
        let Some(title_index) = find_next_result_title(texts, index + 1) else {
            continue;
        };
        let title = clean_search_result_title(&texts[title_index], &url);
        if title.is_empty() || looks_like_search_navigation_title(&title) {
            continue;
        }
        if !seen_urls.insert(url.clone()) {
            continue;
        }
        let snippet = find_next_result_snippet(texts, title_index + 1);
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
    if parts.len() > 2 && parts.len().is_multiple_of(2) {
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
        if lower.contains(&host)
            && (lower.contains('›') || lower.contains('>'))
            && let Some(index) = lower.find(&host)
        {
            candidate.truncate(index);
            candidate = candidate.trim().to_string();
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
    ) || ["图片", "视频", "地图", "新闻", "购物", "搜索"].contains(&title)
}
