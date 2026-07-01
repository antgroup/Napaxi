//! Detects output-token-cap overflow errors from OpenAI-compatible providers
//! and computes a safe reduced max_tokens for retry.

use std::sync::LazyLock;
use regex::Regex;

static RE_CONTEXT_LENGTH: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)maximum context length is\s+(\d+)\s*token").expect("static regex is valid"));

static RE_PROMPT_TOKENS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)(?:prompt|messages?)\s+(?:is|are|contains?|has|have|was)\s+(\d+)\s*token")
        .expect("static regex is valid")
});

// OpenAI's canonical phrasing puts the count before the noun and omits a verb:
// "you requested 8192 tokens (1000 in the messages, 8192 in the output)".
// The number precedes "in the messages/prompt", so RE_PROMPT_TOKENS (which
// expects noun-then-verb-then-number) can't match it.
static RE_PROMPT_TOKENS_PREFIXED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(\d+)\s+in the (?:prompt|messages?)").expect("static regex is valid"));

static RE_PROMPT_CHARS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)prompt\s+contains?\s+(\d+)\s*character").expect("static regex is valid"));

/// Parses an LLM provider error and returns the available output token budget
/// if the error indicates an output-cap overflow (i.e., max_tokens was too
/// large rather than the prompt being too long).
pub(super) fn parse_available_output_tokens(error_msg: &str) -> Option<i32> {
    let lower = error_msg.to_ascii_lowercase();

    let is_output_cap_error = (lower.contains("maximum context length")
        && (lower.contains("in the output")
            || (lower.contains("requested") && lower.contains("output tokens"))))
        || (lower.contains("output tokens") && lower.contains("too many"));

    if !is_output_cap_error {
        return None;
    }

    let ctx = RE_CONTEXT_LENGTH.captures(error_msg)?;
    let context_window: i32 = ctx.get(1)?.as_str().parse().ok()?;

    // Try token-based prompt size first, accepting either phrasing:
    // noun-then-number ("messages was 500 tokens") or OpenAI's canonical
    // number-then-noun ("1000 in the messages").
    let prompt_tokens = RE_PROMPT_TOKENS
        .captures(error_msg)
        .or_else(|| RE_PROMPT_TOKENS_PREFIXED.captures(error_msg))
        .and_then(|cap| cap.get(1))
        .and_then(|m| m.as_str().parse::<i32>().ok());
    if let Some(prompt_tokens) = prompt_tokens {
        let available = context_window - prompt_tokens;
        if available >= 1 {
            return Some(available);
        }
    }

    // Fallback: character-based prompt size (LM Studio / llama.cpp).
    // Estimate ~3 chars per token (conservative, over-reserves input).
    if let Some(char_cap) = RE_PROMPT_CHARS.captures(error_msg) {
        let prompt_chars: i32 = char_cap.get(1)?.as_str().parse().ok()?;
        let estimated_input = (prompt_chars + 2) / 3;
        let available = context_window - estimated_input;
        if available >= 1 {
            return Some(available);
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_standard_openai_output_overflow() {
        let msg = "This model's maximum context length is 8192 tokens. However, you requested 8192 tokens (1000 in the messages, 8192 in the output). Please reduce the length.";
        assert_eq!(parse_available_output_tokens(msg), Some(7192));
    }

    #[test]
    fn detects_lm_studio_char_based_overflow() {
        let msg = "This model's maximum context length is 65536 tokens. However, you requested 65536 output tokens and your prompt contains 77409 characters.";
        assert_eq!(
            parse_available_output_tokens(msg),
            Some(65536 - (77409 + 2) / 3)
        );
    }

    #[test]
    fn returns_none_for_unrelated_errors() {
        assert_eq!(parse_available_output_tokens("connection timeout"), None);
        assert_eq!(parse_available_output_tokens("rate limit exceeded"), None);
    }

    #[test]
    fn detects_token_prompt_measurement() {
        let msg = "This model's maximum context length is 4096 tokens. However, you requested 4096 output tokens and your messages was 500 tokens.";
        assert_eq!(parse_available_output_tokens(msg), Some(3596));
    }

    // Property tests: the parser runs on arbitrary, adversarial provider error
    // strings, so its invariants must hold for all inputs, not just the
    // hand-picked examples above.
    use proptest::prelude::*;

    proptest! {
        // Never panics and never returns a non-positive budget for ANY input.
        // A retry with max_tokens <= 0 would be nonsensical; the parser must
        // only surface a usable positive budget or None.
        #[test]
        fn parse_never_panics_and_budget_is_positive(s in ".*") {
            if let Some(budget) = parse_available_output_tokens(&s) {
                prop_assert!(budget >= 1, "budget must be >= 1, got {budget}");
            }
        }

        // For a well-formed OpenAI-shape output-cap error, the recovered budget
        // is always context_window - prompt_tokens, strictly less than the
        // window, and positive whenever prompt < window. Uses the
        // "messages was N tokens" phrasing the token regex recognizes.
        #[test]
        fn well_formed_output_cap_recovers_window_minus_prompt(
            window in 2i64..1_000_000,
            prompt in 1i64..999_999,
        ) {
            prop_assume!(prompt < window);
            let msg = format!(
                "This model's maximum context length is {window} tokens. \
                 However, you requested {window} output tokens and your \
                 messages was {prompt} tokens."
            );
            let got = parse_available_output_tokens(&msg);
            prop_assert_eq!(got, Some((window - prompt) as i32));
            let budget = got.unwrap();
            prop_assert!((budget as i64) < window);
        }

        // Arbitrary token counts embedded in non-output-cap errors must never
        // be mistaken for a budget (only genuine output-cap shapes recover).
        #[test]
        fn unrelated_errors_with_numbers_return_none(n in 0u32..1_000_000) {
            let msg = format!("request failed after {n} ms; please retry");
            prop_assert_eq!(parse_available_output_tokens(&msg), None);
        }
    }
}
