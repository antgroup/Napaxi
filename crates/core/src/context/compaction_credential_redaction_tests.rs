use super::*;

// Edition 2024 makes an identifier directly before a closing `"` a reserved
// prefix (hard error), so credential-bearing inputs are assembled at runtime
// via format!/concat! and assertion messages end in punctuation.

#[test]
fn redacts_github_pat_prefix() {
    let input = format!(
        "token is ghp_{tok} . ",
        tok = "oAbCdEfGhIjKlMnOpQrStUv8000deadbeef"
    );
    let out = redact_credentials_in_text(&input);
    assert!(
        out.contains("ghp_[REDACTED]"),
        "redaction missing: {out} . "
    );
    assert!(!out.contains("oAbCdEfGhIjKlMnOpQrStUv8000deadbeef"));
}

#[test]
fn redacts_bearer_authorization() {
    let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9payload . ";
    let out = redact_credentials_in_text(input);
    assert!(
        out.contains("Authorization: Bearer [REDACTED]"),
        "redaction missing: {out} . "
    );
    assert!(!out.contains("eyJhbGci"));
}

#[test]
fn redacts_bare_authorization_assignment() {
    let input = "Authorization: dXNlcjpwYXNzMTIzNDU2Nzg5 . ";
    let out = redact_credentials_in_text(input);
    assert!(
        out.contains("Authorization: [REDACTED]"),
        "redaction missing: {out} . "
    );
    assert!(!out.contains("dXNlcjpwYXNzMTIzNDU2Nzg5"));
}

#[test]
fn redacts_anthropic_prefix() {
    let input = format!("keys: sk-ant-{tok} . ", tok = "api03AbCdEfGhIjKlMnOpQrStUv");
    let out = redact_credentials_in_text(&input);
    assert!(
        out.contains("sk-ant-[REDACTED]"),
        "redaction missing: {out} . "
    );
    assert!(!out.contains("api03AbCdEfGhIjKlMnOpQrStUv"));
}

#[test]
fn redacts_openai_long_prefix() {
    let input = format!("sk-{tok} . ", tok = "AbCdEfGhIjKlMnOpQrSt0123456789");
    let out = redact_credentials_in_text(&input);
    assert!(out.contains("sk-[REDACTED]"), "redaction missing: {out} . ");
    assert!(!out.contains("AbCdEfGhIjKlMnOpQrSt0123456789"));
}

#[test]
fn does_not_redact_short_sk() {
    // sk- with <20 body chars is left alone (avoids false positives).
    let out = redact_credentials_in_text("dash sk-short stuff . ");
    assert_eq!(out, "dash sk-short stuff . ");
}

#[test]
fn redacts_key_value_assignments() {
    let input = "config: api_key=abc12345678901234 token=abcdef0123456789 secret: SHORT . ";
    let out = redact_credentials_in_text(input);
    assert!(
        out.contains("api_key=[REDACTED]"),
        "api_key not redacted: {out} . "
    );
    assert!(
        out.contains("token=[REDACTED]"),
        "token not redacted: {out} . "
    );
    // `secret: SHORT` body below the 8-char floor must NOT be redacted.
    assert!(
        out.contains("secret: SHORT"),
        "short secret wrongly redacted: {out} . "
    );
}

#[test]
fn redacts_slack_and_google_prefixes() {
    let input = "slack xoxb-1234567890ABCDEFGH; google AIzaSyABCDEFGHIJKLMN01234567 . ";
    let out = redact_credentials_in_text(input);
    assert!(
        out.contains("xoxb-[REDACTED]"),
        "slack not redacted: {out} . "
    );
    assert!(
        out.contains("AIza[REDACTED]"),
        "google not redacted: {out} . "
    );
}

#[test]
fn leaves_ordinary_text_untouched() {
    let text = "Run cargo test in the worktree, ref 55f899f . ";
    let out = redact_credentials_in_text(text);
    assert_eq!(out, text, "ordinary text was changed.");
}

#[test]
fn local_summary_redacts_user_credentials_before_preview() {
    let user_msg = SessionMessage {
        id: "u1".to_string(),
        role: "user".to_string(),
        content: format!(
            "Please use ghp_{tok} and Bearer {jwt} . ",
            tok = "deadbeefcafe1234567890abcdef",
            jwt = "supersecretjwt1234"
        ),
        created_at: "2026-11-12T00:00:00Z".to_string(),
        interrupted: false,
        turn_id: None,
    };
    let summary = summarize_middle_locally(None, std::slice::from_ref(&user_msg), None);
    assert!(
        !summary.contains("ghp_deadbeefcafe1234567890abcdef"),
        "ghp leaked into summary."
    );
    assert!(
        !summary.contains("supersecretjwt1234"),
        "bearer jwt leaked into summary."
    );
    assert!(summary.contains("[REDACTED]"));
    // Structural invariants preserved.
    assert!(summary.contains("## Conversation Context Summary"));
    assert!(summary.contains("### User Goals And Constraints"));
}

#[test]
fn compaction_user_prompt_redacts_sampled_input() {
    let user_msg = SessionMessage {
        id: "u1".to_string(),
        role: "user".to_string(),
        content: format!(
            "key=Bearer {jwt} long ghp_{tok} . ",
            jwt = "eyJleGFtcGxllnNpZ25hdHVyZQ",
            tok = "1234567890abcdefghijklmno"
        ),
        created_at: "2026-11-12T00:00:00Z".to_string(),
        interrupted: false,
        turn_id: None,
    };
    let prompt = compaction_user_prompt(None, std::slice::from_ref(&user_msg), None);
    assert!(
        !prompt.contains("eyJleGFtcGxllnNpZ25hdHVyZQ"),
        "jwt leaked into prompt."
    );
    assert!(
        !prompt.contains("1234567890abcdefghijklmno"),
        "ghp leaked into prompt."
    );
    assert!(prompt.contains("[REDACTED]"));
}
