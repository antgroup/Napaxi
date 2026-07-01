//! Deterministic skill prefilter for two-phase selection.
//!
//! The first phase of skill selection is entirely deterministic -- no LLM involvement,
//! no skill content in context. This prevents circular manipulation where a loaded
//! skill could influence which skills get loaded.
//!
//! Scoring:
//! - Keyword exact match: 10 points (capped at 30 total)
//! - Keyword substring match: 5 points (capped at 30 total)
//! - Tag match: 3 points (capped at 15 total)
//! - Regex pattern match: 20 points (capped at 40 total)
//! - AgentSkills metadata term match: 4 points (capped at 20 total)
//! - ClawHub/OpenClaw metadata regex match: 20 points (capped at 40 total)

use std::sync::Arc;

use crate::types::LoadedSkill;

/// Default maximum context tokens allocated to skills.
pub const MAX_SKILL_CONTEXT_TOKENS: usize = 4000;

/// Maximum keyword score cap per skill to prevent gaming via keyword stuffing.
/// Even if a skill has 20 keywords, it can earn at most this many keyword points.
const MAX_KEYWORD_SCORE: u32 = 30;

/// Maximum tag score cap per skill (parallel to keyword cap).
const MAX_TAG_SCORE: u32 = 15;

/// Maximum regex pattern score cap per skill. Without a cap, 5 patterns at
/// 20 points each could yield 100 points, dominating keyword+tag scores.
const MAX_REGEX_SCORE: u32 = 40;

/// Maximum score from AgentSkills metadata terms such as name, display_name,
/// description, and metadata intents.
const MAX_METADATA_TERM_SCORE: u32 = 20;

/// Result of prefiltering with score information.
#[derive(Debug)]
pub struct ScoredSkill<'a> {
    pub skill: &'a LoadedSkill,
    pub score: u32,
}

/// Select candidate skills for a given message using deterministic scoring.
///
/// Returns skills sorted by score (highest first), limited by `max_candidates`
/// and total context budget. No LLM is involved in this selection.
pub fn prefilter_skills<'a>(
    message: &str,
    available_skills: &'a [Arc<LoadedSkill>],
    max_candidates: usize,
    max_context_tokens: usize,
) -> Vec<&'a LoadedSkill> {
    if available_skills.is_empty() || message.is_empty() {
        return vec![];
    }

    let message_lower = message.to_lowercase();

    let mut scored: Vec<ScoredSkill<'a>> = available_skills
        .iter()
        .filter_map(|skill| {
            let score = score_skill(skill, &message_lower, message);
            if score > 0 {
                Some(ScoredSkill { skill, score })
            } else {
                None
            }
        })
        .collect();

    // Sort by score descending
    scored.sort_by_key(|b| std::cmp::Reverse(b.score));

    // Apply candidate limit and context budget
    let mut result = Vec::new();
    let mut budget_remaining = max_context_tokens;

    for entry in scored {
        if result.len() >= max_candidates {
            break;
        }
        let declared_tokens = entry.skill.manifest.activation.max_context_tokens;
        // Rough token estimate: ~0.25 tokens per byte (~4 bytes per token for English prose)
        let approx_tokens = (entry.skill.prompt_content.len() as f64 * 0.25) as usize;
        let raw_cost = if approx_tokens > declared_tokens * 2 {
            tracing::warn!(
                "Skill '{}' declares max_context_tokens={} but prompt is ~{} tokens; using actual estimate",
                entry.skill.name(),
                declared_tokens,
                approx_tokens,
            );
            approx_tokens
        } else {
            declared_tokens
        };
        // Enforce a minimum token cost so max_context_tokens=0 can't bypass budgeting
        let token_cost = raw_cost.max(1);
        if token_cost <= budget_remaining {
            budget_remaining -= token_cost;
            result.push(entry.skill);
        }
    }

    result
}

/// Score a skill against a user message.
fn score_skill(skill: &LoadedSkill, message_lower: &str, message_original: &str) -> u32 {
    // Exclusion veto: if any exclude_keyword is present in the message, score 0
    if skill
        .lowercased_exclude_keywords
        .iter()
        .any(|excl| message_lower.contains(excl.as_str()))
    {
        return 0;
    }

    let mut score: u32 = 0;

    // Keyword scoring with cap to prevent gaming via keyword stuffing
    let mut keyword_score: u32 = 0;
    for kw_lower in &skill.lowercased_keywords {
        // Exact word match (surrounded by word boundaries)
        if message_lower
            .split_whitespace()
            .any(|word| word.trim_matches(|c: char| !c.is_alphanumeric()) == kw_lower.as_str())
        {
            keyword_score += 10;
        } else if message_lower.contains(kw_lower.as_str()) {
            // Substring match
            keyword_score += 5;
        }
    }
    score += keyword_score.min(MAX_KEYWORD_SCORE);

    // Tag scoring from activation.tags
    let mut tag_score: u32 = 0;
    for tag_lower in &skill.lowercased_tags {
        if message_lower.contains(tag_lower.as_str()) {
            tag_score += 3;
        }
    }
    score += tag_score.min(MAX_TAG_SCORE);

    // Regex pattern scoring using pre-compiled patterns (cached at load time), with cap
    let mut regex_score: u32 = 0;
    for re in skill
        .compiled_patterns
        .iter()
        .chain(skill.compiled_metadata_patterns.iter())
    {
        if re.is_match(message_original) {
            regex_score += 20;
        }
    }
    score += regex_score.min(MAX_REGEX_SCORE);

    let mut metadata_term_score: u32 = 0;
    for term in &skill.lowercased_metadata_terms {
        if metadata_term_matches(term, message_lower) {
            metadata_term_score += 4;
        }
    }
    score += metadata_term_score.min(MAX_METADATA_TERM_SCORE);

    score
}

fn metadata_term_matches(term: &str, message_lower: &str) -> bool {
    if term.is_empty() {
        return false;
    }
    if term
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
    {
        message_lower
            .split_whitespace()
            .any(|word| word.trim_matches(|c: char| !c.is_alphanumeric()) == term)
            || message_lower.contains(term)
    } else {
        message_lower.contains(term)
    }
}

/// Extract explicit `/skill-name` mentions from a message.
///
/// Users can write `/github` or `/file-issues` anywhere in their message to
/// force-activate a skill. Returns the matched skills and a rewritten message
/// where each `/skill-name` is replaced with the skill's description (so the
/// sentence still reads naturally for the LLM).
///
/// Example: `"fetch issues from /github"` with a skill named `github`
/// (description "GitHub API") → rewritten to `"fetch issues from GitHub API"`,
/// and the github skill is force-included.
pub fn extract_skill_mentions(
    message: &str,
    available_skills: &[Arc<LoadedSkill>],
) -> (Vec<Arc<LoadedSkill>>, String) {
    let mut matched = Vec::new();
    let mut rewritten = message.to_string();

    // Build a name→skill lookup (case-insensitive)
    let skill_map: std::collections::HashMap<String, Arc<LoadedSkill>> = available_skills
        .iter()
        .map(|s| (s.manifest.name.to_lowercase(), s.clone()))
        .collect();

    // Find /word patterns that match skill names. Scan from end to avoid
    // index shifts when replacing.
    let mut replacements: Vec<(usize, usize, String)> = Vec::new();
    let bytes = message.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'/' {
            // Check that / is at start or preceded by whitespace/punctuation
            let is_boundary = i == 0
                || bytes[i - 1] == b' '
                || bytes[i - 1] == b'\n'
                || bytes[i - 1] == b'\t'
                || bytes[i - 1] == b'"'
                || bytes[i - 1] == b'(';

            if is_boundary {
                // Extract the name using the same character class accepted by
                // skill validation: [a-zA-Z0-9._-]+
                let start = i + 1;
                let mut end = start;
                while end < bytes.len()
                    && (bytes[end].is_ascii_lowercase()
                        || bytes[end].is_ascii_uppercase()
                        || bytes[end].is_ascii_digit()
                        || bytes[end] == b'-'
                        || bytes[end] == b'_'
                        || bytes[end] == b'.')
                {
                    end += 1;
                }
                if end > start {
                    let name = &message[start..end];
                    let lookup = name.to_lowercase();
                    if let Some(skill) = skill_map.get(&lookup) {
                        let replacement = if skill.manifest.description.is_empty() {
                            // No description — just remove the slash
                            name.replace('-', " ")
                        } else {
                            skill.manifest.description.clone()
                        };
                        replacements.push((i, end, replacement));
                        if !matched
                            .iter()
                            .any(|s: &Arc<LoadedSkill>| s.manifest.name == skill.manifest.name)
                        {
                            matched.push(skill.clone());
                        }
                    }
                }
            }
        }
        i += 1;
    }

    // Apply replacements in reverse order to preserve indices
    for (start, end, replacement) in replacements.into_iter().rev() {
        rewritten.replace_range(start..end, &replacement);
    }

    (matched, rewritten)
}

/// Apply confidence factor to a base score.
///
/// Authored skills always get factor 1.0 (no adjustment).
/// Extracted skills get `0.5 + 0.5 * confidence`, so a skill with 0% confidence
/// gets its score halved (not zeroed — it can still be selected when strongly
/// keyword-matched).
pub fn apply_confidence_factor(base_score: u32, confidence: f64, is_authored: bool) -> u32 {
    if is_authored {
        return base_score;
    }
    let factor = 0.5 + 0.5 * confidence.clamp(0.0, 1.0);
    (base_score as f64 * factor) as u32
}

#[cfg(test)]
mod tests;
