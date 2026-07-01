use super::*;
use crate::types::{
    ActivationCriteria, GatingRequirements, LoadedSkill, SkillManifest, SkillSource, SkillTrust,
};
use std::path::PathBuf;

fn make_skill(name: &str, keywords: &[&str], tags: &[&str], patterns: &[&str]) -> Arc<LoadedSkill> {
    make_skill_with_desc(name, keywords, tags, patterns, &format!("{} skill", name))
}

fn make_skill_with_tokens(
    name: &str,
    keywords: &[&str],
    tags: &[&str],
    patterns: &[&str],
    max_tokens: usize,
) -> Arc<LoadedSkill> {
    let mut skill = make_skill(name, keywords, tags, patterns);
    Arc::get_mut(&mut skill)
        .unwrap()
        .manifest
        .activation
        .max_context_tokens = max_tokens;
    skill
}

fn make_skill_with_tokens_and_content(
    name: &str,
    keywords: &[&str],
    tags: &[&str],
    patterns: &[&str],
    max_tokens: usize,
    content: &str,
) -> Arc<LoadedSkill> {
    let mut skill = make_skill_with_tokens(name, keywords, tags, patterns, max_tokens);
    Arc::get_mut(&mut skill).unwrap().prompt_content = content.to_string();
    skill
}

fn make_skill_with_desc(
    name: &str,
    keywords: &[&str],
    tags: &[&str],
    patterns: &[&str],
    desc: &str,
) -> Arc<LoadedSkill> {
    let pattern_strings: Vec<String> = patterns.iter().map(|s| s.to_string()).collect();
    let compiled = LoadedSkill::compile_patterns(&pattern_strings);
    let kw_vec: Vec<String> = keywords.iter().map(|s| s.to_string()).collect();
    let tag_vec: Vec<String> = tags.iter().map(|s| s.to_string()).collect();
    let lowercased_keywords = kw_vec.iter().map(|k| k.to_lowercase()).collect();
    let lowercased_tags = tag_vec.iter().map(|t| t.to_lowercase()).collect();
    Arc::new(LoadedSkill {
        manifest: SkillManifest {
            name: name.to_string(),
            display_name: None,
            version: "1.0.0".to_string(),
            description: desc.to_string(),
            activation: ActivationCriteria {
                keywords: kw_vec,
                exclude_keywords: vec![],
                patterns: pattern_strings,
                tags: tag_vec,
                max_context_tokens: 1000,
            },
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "Test prompt".to_string(),
        trust: SkillTrust::Trusted,
        source: SkillSource::User(PathBuf::from("/tmp/test")), // safety: dummy path in test, not used for I/O
        content_hash: "sha256:000".to_string(),
        compiled_patterns: compiled,
        lowercased_keywords,
        lowercased_exclude_keywords: vec![],
        lowercased_tags,
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: String::new(),
    })
}

#[test]
fn test_empty_message_returns_nothing() {
    let skills = vec![make_skill("test", &["write"], &[], &[])];
    let result = prefilter_skills("", &skills, 3, MAX_SKILL_CONTEXT_TOKENS);
    assert!(result.is_empty());
}

#[test]
fn test_no_matching_skills() {
    let skills = vec![make_skill("cooking", &["recipe", "cook", "bake"], &[], &[])];
    let result = prefilter_skills(
        "Help me write an email",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert!(result.is_empty());
}

#[test]
fn test_keyword_exact_match() {
    let skills = vec![make_skill("writing", &["write", "edit"], &[], &[])];
    let result = prefilter_skills(
        "Please write an email",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].name(), "writing");
}

#[test]
fn test_keyword_substring_match() {
    let skills = vec![make_skill("writing", &["writing"], &[], &[])];
    let result = prefilter_skills(
        "I need help with rewriting this text",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_tag_match() {
    let skills = vec![make_skill("writing", &[], &["prose", "email"], &[])];
    let result = prefilter_skills(
        "Draft an email for me",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_regex_pattern_match() {
    let skills = vec![make_skill(
        "writing",
        &[],
        &[],
        &[r"(?i)\b(write|draft)\b.*\b(email|letter)\b"],
    )];
    let result = prefilter_skills(
        "Please draft an email to my boss",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_scoring_priority() {
    let skills = vec![
        make_skill("cooking", &["cook"], &[], &[]),
        make_skill(
            "writing",
            &["write", "draft"],
            &["email"],
            &[r"(?i)\b(write|draft)\b.*\bemail\b"],
        ),
    ];
    let result = prefilter_skills(
        "Write and draft an email",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].name(), "writing");
}

#[test]
fn test_max_candidates_limit() {
    let skills = vec![
        make_skill("a", &["test"], &[], &[]),
        make_skill("b", &["test"], &[], &[]),
        make_skill("c", &["test"], &[], &[]),
    ];
    let result = prefilter_skills("test", &skills, 2, MAX_SKILL_CONTEXT_TOKENS);
    assert_eq!(result.len(), 2);
}

#[test]
fn test_context_budget_limit() {
    let skill = make_skill_with_tokens("big", &["test"], &[], &[], 3000);
    let skill2 = make_skill_with_tokens("also_big", &["test"], &[], &[], 3000);

    let skills = vec![skill, skill2];
    let result = prefilter_skills("test", &skills, 5, 4000);
    assert_eq!(result.len(), 1);
}

#[test]
fn test_invalid_regex_handled_gracefully() {
    let skills = vec![make_skill("bad", &["test"], &[], &["[invalid regex"])];
    let result = prefilter_skills("test", &skills, 3, MAX_SKILL_CONTEXT_TOKENS);
    assert_eq!(result.len(), 1);
}

#[test]
fn test_keyword_score_capped() {
    let many_keywords: Vec<&str> = vec![
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
    ];
    let skill = make_skill("spammer", &many_keywords, &[], &[]);
    let skills = vec![skill];
    let result = prefilter_skills(
        "a b c d e f g h i j k l m n o p",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_tag_score_capped() {
    let many_tags: Vec<&str> = vec![
        "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
    ];
    let skill = make_skill("tag-spammer", &[], &many_tags, &[]);
    let skills = vec![skill];
    let result = prefilter_skills(
        "alpha bravo charlie delta echo foxtrot golf hotel",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_regex_score_capped() {
    let skill = make_skill(
        "regex-spammer",
        &[],
        &[],
        &[
            r"(?i)\bwrite\b",
            r"(?i)\bdraft\b",
            r"(?i)\bedit\b",
            r"(?i)\bcompose\b",
            r"(?i)\bauthor\b",
        ],
    );
    let skills = vec![skill];
    let result = prefilter_skills(
        "write draft edit compose author",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(result.len(), 1);
}

#[test]
fn test_zero_context_tokens_still_costs_budget() {
    let skill = make_skill_with_tokens_and_content("free", &["test"], &[], &[], 0, "");
    let skill2 = make_skill_with_tokens_and_content("also_free", &["test"], &[], &[], 0, "");

    let skills = vec![skill, skill2];
    let result = prefilter_skills("test", &skills, 5, 1);
    assert_eq!(result.len(), 1);
}

fn make_skill_with_excludes(
    name: &str,
    keywords: &[&str],
    exclude_keywords: &[&str],
    tags: &[&str],
    patterns: &[&str],
) -> Arc<LoadedSkill> {
    let excl_vec: Vec<String> = exclude_keywords.iter().map(|s| s.to_string()).collect();
    let mut skill = make_skill(name, keywords, tags, patterns);
    Arc::get_mut(&mut skill)
        .unwrap()
        .lowercased_exclude_keywords = excl_vec.iter().map(|k| k.to_lowercase()).collect();
    Arc::get_mut(&mut skill)
        .unwrap()
        .manifest
        .activation
        .exclude_keywords = excl_vec;
    skill
}

#[test]
fn test_exclude_keyword_vetos_match() {
    let skills = vec![make_skill_with_excludes(
        "writer",
        &["write"],
        &["route"],
        &[],
        &[],
    )];
    let result = prefilter_skills(
        "route this write request to another agent",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert!(
        result.is_empty(),
        "skill with matching exclude_keyword should score 0"
    );
}

#[test]
fn test_exclude_keyword_absent_does_not_block() {
    let skills = vec![make_skill_with_excludes(
        "writer",
        &["write"],
        &["route"],
        &[],
        &[],
    )];
    let result = prefilter_skills(
        "help me write an email",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert_eq!(
        result.len(),
        1,
        "skill should activate when no exclude_keyword is present"
    );
}

#[test]
fn test_exclude_keyword_veto_wins_over_positive_match() {
    let skills = vec![make_skill_with_excludes(
        "writer",
        &["write", "draft", "compose"],
        &["redirect"],
        &[],
        &[],
    )];
    let result = prefilter_skills(
        "write and draft and compose — but redirect this somewhere else",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert!(
        result.is_empty(),
        "exclude_keyword veto must win even when multiple positive keywords match"
    );
}

#[test]
fn test_exclude_keyword_case_insensitive() {
    let skills = vec![make_skill_with_excludes(
        "writer",
        &["write"],
        &["Route"],
        &[],
        &[],
    )];
    let result = prefilter_skills(
        "please ROUTE this write request",
        &skills,
        3,
        MAX_SKILL_CONTEXT_TOKENS,
    );
    assert!(
        result.is_empty(),
        "exclude_keyword veto should be case-insensitive"
    );
}

#[test]
fn test_apply_confidence_factor_authored() {
    assert_eq!(apply_confidence_factor(100, 0.0, true), 100);
    assert_eq!(apply_confidence_factor(100, 0.5, true), 100);
    assert_eq!(apply_confidence_factor(100, 1.0, true), 100);
}

#[test]
fn test_apply_confidence_factor_extracted() {
    // 0% confidence → factor 0.5 → score halved
    assert_eq!(apply_confidence_factor(100, 0.0, false), 50);
    // 50% confidence → factor 0.75 → score * 0.75
    assert_eq!(apply_confidence_factor(100, 0.5, false), 75);
    // 100% confidence → factor 1.0 → unchanged
    assert_eq!(apply_confidence_factor(100, 1.0, false), 100);
}

#[test]
fn test_apply_confidence_factor_clamps() {
    // Negative confidence clamped to 0
    assert_eq!(apply_confidence_factor(100, -0.5, false), 50);
    // Over 1.0 clamped to 1.0
    assert_eq!(apply_confidence_factor(100, 1.5, false), 100);
}

// ── extract_skill_mentions tests ──────────────────────────

#[test]
fn test_extract_no_mentions() {
    let skills = vec![make_skill("github", &["github"], &[], &[])];
    let (matched, rewritten) = extract_skill_mentions("fetch issues from github", &skills);
    assert!(matched.is_empty());
    assert_eq!(rewritten, "fetch issues from github");
}

#[test]
fn test_extract_slash_mention() {
    let skills = vec![make_skill("github", &["github"], &[], &[])];
    let (matched, rewritten) = extract_skill_mentions("fetch issues from /github", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(matched[0].manifest.name, "github");
    assert_eq!(rewritten, "fetch issues from github skill");
}

#[test]
fn test_extract_slash_mention_with_description() {
    let skills = vec![make_skill_with_desc(
        "github",
        &["github"],
        &[],
        &[],
        "GitHub API",
    )];
    let (matched, rewritten) = extract_skill_mentions("fetch issues from /github", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(rewritten, "fetch issues from GitHub API");
}

#[test]
fn test_extract_hyphenated_skill_name() {
    let skills = vec![make_skill_with_desc(
        "file-issues",
        &["file", "issues"],
        &[],
        &[],
        "file detailed GitHub issues",
    )];
    let (matched, rewritten) =
        extract_skill_mentions("please /file-issues for all found bugs", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(
        rewritten,
        "please file detailed GitHub issues for all found bugs"
    );
}

#[test]
fn test_extract_underscored_skill_name() {
    let skills = vec![make_skill_with_desc(
        "my_skill",
        &["skill"],
        &[],
        &[],
        "custom workflow",
    )];
    let (matched, rewritten) = extract_skill_mentions("run /my_skill on this task", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(matched[0].manifest.name, "my_skill");
    assert_eq!(rewritten, "run custom workflow on this task");
}

#[test]
fn test_extract_dotted_skill_name() {
    let skills = vec![make_skill_with_desc(
        "skill.v2",
        &["skill"],
        &[],
        &[],
        "second generation skill",
    )];
    let (matched, rewritten) = extract_skill_mentions("please use /skill.v2 here", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(matched[0].manifest.name, "skill.v2");
    assert_eq!(rewritten, "please use second generation skill here");
}

#[test]
fn test_extract_multiple_mentions() {
    let skills = vec![
        make_skill_with_desc("github", &["github"], &[], &[], "GitHub API"),
        make_skill_with_desc("linear", &["linear"], &[], &[], "Linear project management"),
    ];
    let (matched, rewritten) = extract_skill_mentions("sync /github issues to /linear", &skills);
    assert_eq!(matched.len(), 2);
    assert_eq!(
        rewritten,
        "sync GitHub API issues to Linear project management"
    );
}

#[test]
fn test_extract_unknown_slash_not_replaced() {
    let skills = vec![make_skill("github", &["github"], &[], &[])];
    let (matched, rewritten) = extract_skill_mentions("run /unknown-thing now", &skills);
    assert!(matched.is_empty());
    assert_eq!(rewritten, "run /unknown-thing now");
}

#[test]
fn test_extract_slash_at_start_of_message() {
    let skills = vec![make_skill_with_desc(
        "github",
        &["github"],
        &[],
        &[],
        "GitHub API",
    )];
    let (matched, rewritten) = extract_skill_mentions("/github list my repos", &skills);
    assert_eq!(matched.len(), 1);
    assert_eq!(rewritten, "GitHub API list my repos");
}

#[test]
fn test_extract_url_not_matched() {
    let skills = vec![make_skill("github", &["github"], &[], &[])];
    let (matched, rewritten) = extract_skill_mentions("open https://github.com/repo", &skills);
    // The /github.com won't match because '.' breaks the name pattern
    assert!(matched.is_empty());
    assert_eq!(rewritten, "open https://github.com/repo");
}
