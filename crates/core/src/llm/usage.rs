use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LlmUsage {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_read_tokens: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write_tokens: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_tokens: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_tokens: Option<usize>,
}

impl LlmUsage {
    pub fn prompt_tokens(&self) -> Option<usize> {
        let input = self.input_tokens.unwrap_or(0);
        let cache_read = self.cache_read_tokens.unwrap_or(0);
        let cache_write = self.cache_write_tokens.unwrap_or(0);
        let total = input.saturating_add(cache_read).saturating_add(cache_write);
        (total > 0).then_some(total)
    }

    pub(crate) fn merge_present(&mut self, other: LlmUsage) {
        if other.input_tokens.is_some() {
            self.input_tokens = other.input_tokens;
        }
        if other.output_tokens.is_some() {
            self.output_tokens = other.output_tokens;
        }
        if other.cache_read_tokens.is_some() {
            self.cache_read_tokens = other.cache_read_tokens;
        }
        if other.cache_write_tokens.is_some() {
            self.cache_write_tokens = other.cache_write_tokens;
        }
        if other.reasoning_tokens.is_some() {
            self.reasoning_tokens = other.reasoning_tokens;
        }
        if other.total_tokens.is_some() {
            self.total_tokens = other.total_tokens;
        }
    }

    fn has_any_token_count(&self) -> bool {
        [
            self.input_tokens,
            self.output_tokens,
            self.cache_read_tokens,
            self.cache_write_tokens,
            self.reasoning_tokens,
            self.total_tokens,
        ]
        .into_iter()
        .any(|value| value.is_some())
    }
}

pub(super) fn openai_usage(value: &Value) -> Option<LlmUsage> {
    usage_object(value, "usage").and_then(openai_usage_from_object)
}

pub(super) fn anthropic_usage(value: &Value) -> Option<LlmUsage> {
    usage_object(value, "usage").and_then(anthropic_usage_from_object)
}

pub(super) fn anthropic_stream_usage(value: &Value) -> Option<LlmUsage> {
    value
        .pointer("/message/usage")
        .or_else(|| value.pointer("/usage"))
        .and_then(anthropic_usage_from_object)
}

pub(super) fn gemini_usage(value: &Value) -> Option<LlmUsage> {
    value
        .get("usageMetadata")
        .and_then(gemini_usage_from_object)
}

fn usage_object<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
    value.get(key).filter(|usage| usage.is_object())
}

fn openai_usage_from_object(usage: &Value) -> Option<LlmUsage> {
    let prompt = token_at(usage, "prompt_tokens")
        .or_else(|| token_at(usage, "input_tokens"))
        .or_else(|| token_at(usage, "prompt"));
    let cache_read = usage
        .pointer("/prompt_tokens_details/cached_tokens")
        .and_then(token_value)
        .or_else(|| {
            usage
                .pointer("/input_tokens_details/cached_tokens")
                .and_then(token_value)
        })
        .or_else(|| token_at(usage, "cached_tokens"))
        .or_else(|| token_at(usage, "cache_read_input_tokens"))
        .or_else(|| token_at(usage, "cache_read_tokens"));
    let cache_write = token_at(usage, "cache_creation_input_tokens")
        .or_else(|| token_at(usage, "cache_write_tokens"))
        .or_else(|| token_at(usage, "cache_creation_tokens"));
    let input = prompt
        .map(|tokens| tokens.saturating_sub(cache_read.unwrap_or(0)))
        .or_else(|| token_at(usage, "input"));
    let mut normalized = LlmUsage {
        input_tokens: input,
        output_tokens: token_at(usage, "completion_tokens")
            .or_else(|| token_at(usage, "output_tokens"))
            .or_else(|| token_at(usage, "output")),
        cache_read_tokens: cache_read,
        cache_write_tokens: cache_write,
        reasoning_tokens: usage
            .pointer("/completion_tokens_details/reasoning_tokens")
            .and_then(token_value)
            .or_else(|| {
                usage
                    .pointer("/output_tokens_details/reasoning_tokens")
                    .and_then(token_value)
            })
            .or_else(|| token_at(usage, "reasoning_tokens")),
        total_tokens: token_at(usage, "total_tokens").or_else(|| token_at(usage, "total")),
    };
    if normalized.total_tokens.is_none() {
        normalized.total_tokens = component_total(&normalized);
    }
    normalized.has_any_token_count().then_some(normalized)
}

fn anthropic_usage_from_object(usage: &Value) -> Option<LlmUsage> {
    let mut normalized = LlmUsage {
        input_tokens: token_at(usage, "input_tokens"),
        output_tokens: token_at(usage, "output_tokens"),
        cache_read_tokens: token_at(usage, "cache_read_input_tokens")
            .or_else(|| token_at(usage, "cache_read_tokens")),
        cache_write_tokens: token_at(usage, "cache_creation_input_tokens")
            .or_else(|| token_at(usage, "cache_write_tokens")),
        reasoning_tokens: None,
        total_tokens: None,
    };
    normalized.total_tokens = component_total(&normalized);
    normalized.has_any_token_count().then_some(normalized)
}

fn gemini_usage_from_object(usage: &Value) -> Option<LlmUsage> {
    let prompt = token_at(usage, "promptTokenCount");
    let cache_read = token_at(usage, "cachedContentTokenCount");
    let mut normalized = LlmUsage {
        input_tokens: prompt.map(|tokens| tokens.saturating_sub(cache_read.unwrap_or(0))),
        output_tokens: token_at(usage, "candidatesTokenCount"),
        cache_read_tokens: cache_read,
        cache_write_tokens: None,
        reasoning_tokens: token_at(usage, "thoughtsTokenCount"),
        total_tokens: token_at(usage, "totalTokenCount"),
    };
    if normalized.total_tokens.is_none() {
        normalized.total_tokens = component_total(&normalized);
    }
    normalized.has_any_token_count().then_some(normalized)
}

fn token_at(value: &Value, key: &str) -> Option<usize> {
    value.get(key).and_then(token_value)
}

fn token_value(value: &Value) -> Option<usize> {
    if let Some(value) = value.as_u64() {
        return usize::try_from(value).ok();
    }
    if let Some(value) = value.as_i64() {
        return (value >= 0).then(|| usize::try_from(value).ok()).flatten();
    }
    let value = value.as_f64()?;
    if !value.is_finite() || value < 0.0 {
        return None;
    }
    usize::try_from(value.trunc() as u64).ok()
}

fn component_total(usage: &LlmUsage) -> Option<usize> {
    let total = usage
        .prompt_tokens()
        .unwrap_or(0)
        .saturating_add(usage.output_tokens.unwrap_or(0));
    (total > 0).then_some(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn openai_usage_subtracts_cached_prompt_tokens() {
        let value = serde_json::json!({
            "usage": {
                "prompt_tokens": 1000,
                "completion_tokens": 50,
                "total_tokens": 1050,
                "prompt_tokens_details": { "cached_tokens": 250 },
                "completion_tokens_details": { "reasoning_tokens": 20 }
            }
        });

        assert_eq!(
            openai_usage(&value),
            Some(LlmUsage {
                input_tokens: Some(750),
                output_tokens: Some(50),
                cache_read_tokens: Some(250),
                cache_write_tokens: None,
                reasoning_tokens: Some(20),
                total_tokens: Some(1050),
            })
        );
    }

    #[test]
    fn openai_usage_accepts_input_token_aliases() {
        let value = serde_json::json!({
            "usage": {
                "input_tokens": 300,
                "output_tokens": 20,
                "input_tokens_details": { "cached_tokens": 75 },
                "cache_creation_input_tokens": 25
            }
        });

        let usage = openai_usage(&value).unwrap();
        assert_eq!(usage.input_tokens, Some(225));
        assert_eq!(usage.cache_read_tokens, Some(75));
        assert_eq!(usage.cache_write_tokens, Some(25));
        assert_eq!(usage.prompt_tokens(), Some(325));
    }

    #[test]
    fn anthropic_usage_keeps_cache_read_and_write() {
        let value = serde_json::json!({
            "usage": {
                "input_tokens": 100,
                "output_tokens": 20,
                "cache_read_input_tokens": 400,
                "cache_creation_input_tokens": 60
            }
        });

        let usage = anthropic_usage(&value).unwrap();
        assert_eq!(usage.prompt_tokens(), Some(560));
        assert_eq!(usage.output_tokens, Some(20));
        assert_eq!(usage.total_tokens, Some(580));
    }

    #[test]
    fn gemini_usage_maps_cached_content_to_cache_read() {
        let value = serde_json::json!({
            "usageMetadata": {
                "promptTokenCount": 900,
                "cachedContentTokenCount": 300,
                "candidatesTokenCount": 40,
                "totalTokenCount": 940
            }
        });

        let usage = gemini_usage(&value).unwrap();
        assert_eq!(usage.input_tokens, Some(600));
        assert_eq!(usage.cache_read_tokens, Some(300));
        assert_eq!(usage.prompt_tokens(), Some(900));
        assert_eq!(usage.total_tokens, Some(940));
    }
}
