use super::*;

#[test]
fn test_skill_trust_ordering() {
    assert!(SkillTrust::Installed < SkillTrust::Trusted);
}

#[test]
fn test_skill_trust_display() {
    assert_eq!(SkillTrust::Installed.to_string(), "installed");
    assert_eq!(SkillTrust::Trusted.to_string(), "trusted");
}

#[test]
fn test_enforce_keyword_limits() {
    let mut criteria = ActivationCriteria {
        keywords: (0..30).map(|i| format!("kw{}", i)).collect(),
        patterns: (0..10).map(|i| format!("pat{}", i)).collect(),
        tags: (0..20).map(|i| format!("tag{}", i)).collect(),
        ..Default::default()
    };
    criteria.enforce_limits();
    assert_eq!(criteria.keywords.len(), MAX_KEYWORDS_PER_SKILL);
    assert_eq!(criteria.patterns.len(), MAX_PATTERNS_PER_SKILL);
    assert_eq!(criteria.tags.len(), MAX_TAGS_PER_SKILL);
}

#[test]
fn test_enforce_limits_filters_short_keywords() {
    let mut criteria = ActivationCriteria {
        keywords: vec!["a".into(), "be".into(), "cat".into(), "dog".into()],
        tags: vec!["x".into(), "foo".into(), "ab".into(), "bar".into()],
        ..Default::default()
    };
    criteria.enforce_limits();
    assert_eq!(criteria.keywords, vec!["cat", "dog"]);
    assert_eq!(criteria.tags, vec!["foo", "bar"]);
}

#[test]
fn test_activation_criteria_enforce_limits() {
    let mut keywords: Vec<String> = vec!["a".into(), "bb".into()];
    keywords.extend((0..25).map(|i| format!("keyword{}", i)));

    let patterns: Vec<String> = (0..8).map(|i| format!("pattern{}", i)).collect();

    let mut tags: Vec<String> = vec!["x".into(), "ab".into()];
    tags.extend((0..15).map(|i| format!("tag{}", i)));

    let mut criteria = ActivationCriteria {
        keywords,
        patterns,
        tags,
        ..Default::default()
    };

    criteria.enforce_limits();

    assert!(
        !criteria
            .keywords
            .iter()
            .any(|k| k.len() < MIN_KEYWORD_TAG_LENGTH),
        "keywords shorter than {} chars should be filtered out",
        MIN_KEYWORD_TAG_LENGTH
    );
    assert_eq!(
        criteria.keywords.len(),
        MAX_KEYWORDS_PER_SKILL,
        "keywords should be capped at {}",
        MAX_KEYWORDS_PER_SKILL
    );

    assert_eq!(
        criteria.patterns.len(),
        MAX_PATTERNS_PER_SKILL,
        "patterns should be capped at {}",
        MAX_PATTERNS_PER_SKILL
    );
    for i in 0..MAX_PATTERNS_PER_SKILL {
        assert_eq!(criteria.patterns[i], format!("pattern{}", i));
    }

    assert!(
        !criteria
            .tags
            .iter()
            .any(|t| t.len() < MIN_KEYWORD_TAG_LENGTH),
        "tags shorter than {} chars should be filtered out",
        MIN_KEYWORD_TAG_LENGTH
    );
    assert_eq!(
        criteria.tags.len(),
        MAX_TAGS_PER_SKILL,
        "tags should be capped at {}",
        MAX_TAGS_PER_SKILL
    );
}

#[test]
fn test_compile_patterns() {
    let patterns = vec![
        r"(?i)\bwrite\b".to_string(),
        "[invalid".to_string(),
        r"(?i)\bedit\b".to_string(),
    ];
    let compiled = LoadedSkill::compile_patterns(&patterns);
    assert_eq!(compiled.len(), 2);
}

#[test]
fn test_parse_skill_manifest_yaml() {
    let yaml = r#"
name: writing-assistant
version: "1.0.0"
description: Professional writing and editing
activation:
  keywords: ["write", "edit", "proofread"]
  patterns: ["(?i)\\b(write|draft)\\b.*\\b(email|letter)\\b"]
  max_context_tokens: 2000
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    assert_eq!(manifest.name, "writing-assistant");
    assert_eq!(manifest.activation.keywords.len(), 3);
}

#[test]
fn test_parse_requires() {
    let yaml = r#"
name: test-skill
requires:
  bins: ["vale"]
  env: ["VALE_CONFIG"]
  config: ["/etc/vale.ini"]
  skills: ["commitment-triage", "commitment-digest"]
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    assert_eq!(manifest.requires.bins, vec!["vale"]);
    assert_eq!(manifest.requires.env, vec!["VALE_CONFIG"]);
    assert_eq!(manifest.requires.config, vec!["/etc/vale.ini"]);
    assert_eq!(
        manifest.requires.skills,
        vec!["commitment-triage", "commitment-digest"]
    );
}

#[test]
fn test_loaded_skill_name_version() {
    let skill = LoadedSkill {
        manifest: SkillManifest {
            name: "test".to_string(),
            display_name: None,
            version: "1.0.0".to_string(),
            description: String::new(),
            activation: ActivationCriteria::default(),
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "test prompt".to_string(),
        trust: SkillTrust::Trusted,
        source: SkillSource::User(PathBuf::from("/tmp/test")), // safety: dummy path in test, not used for I/O
        content_hash: "sha256:000".to_string(),
        compiled_patterns: vec![],
        lowercased_keywords: vec![],
        lowercased_exclude_keywords: vec![],
        lowercased_tags: vec![],
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: String::new(),
    };
    assert_eq!(skill.name(), "test");
    assert_eq!(skill.version(), "1.0.0");
}

#[test]
fn test_parse_credentials_frontmatter() {
    let yaml = r#"
name: gmail
version: "1.0.0"
description: Gmail API integration
activation:
  keywords: ["email", "gmail"]
credentials:
  - name: google_oauth_token
    provider: google
    location:
      type: bearer
    hosts: ["gmail.googleapis.com"]
    oauth:
      authorization_url: "https://accounts.google.com/o/oauth2/v2/auth"
      token_url: "https://oauth2.googleapis.com/token"
      scopes: ["https://www.googleapis.com/auth/gmail.modify"]
      test_url: "https://www.googleapis.com/oauth2/v1/userinfo"
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    assert_eq!(manifest.credentials.len(), 1);
    let cred = &manifest.credentials[0];
    assert_eq!(cred.name, "google_oauth_token");
    assert_eq!(cred.provider, "google");
    assert!(matches!(cred.location, SkillCredentialLocation::Bearer));
    assert_eq!(cred.hosts, vec!["gmail.googleapis.com"]);
    let oauth = cred.oauth.as_ref().unwrap();
    assert_eq!(
        oauth.authorization_url,
        "https://accounts.google.com/o/oauth2/v2/auth"
    );
    assert_eq!(oauth.scopes.len(), 1);
    assert_eq!(
        oauth.test_url.as_deref(),
        Some("https://www.googleapis.com/oauth2/v1/userinfo")
    );
    assert!(matches!(oauth.refresh, ProviderRefreshStrategy::Standard));
}

#[test]
fn test_parse_credentials_header_location() {
    let yaml = r#"
name: custom-api
credentials:
  - name: api_key
    provider: custom
    location:
      type: header
      name: X-API-Key
      prefix: "Token"
    hosts: ["api.custom.com"]
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let cred = &manifest.credentials[0];
    match &cred.location {
        SkillCredentialLocation::Header { name, prefix } => {
            assert_eq!(name, "X-API-Key");
            assert_eq!(prefix.as_deref(), Some("Token"));
        }
        other => panic!("expected Header, got {:?}", other),
    }
}

#[test]
fn test_parse_credentials_query_param_location() {
    let yaml = r#"
name: legacy-api
credentials:
  - name: api_key
    provider: legacy
    location:
      type: query_param
      name: access_token
    hosts: ["api.legacy.com"]
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let cred = &manifest.credentials[0];
    match &cred.location {
        SkillCredentialLocation::QueryParam { name } => {
            assert_eq!(name, "access_token");
        }
        other => panic!("expected QueryParam, got {:?}", other),
    }
}

#[test]
fn test_parse_credentials_basic_auth() {
    let yaml = r#"
name: basic-api
credentials:
  - name: basic_cred
    provider: example
    location:
      type: basic_auth
      username: admin
    hosts: ["api.example.com"]
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let cred = &manifest.credentials[0];
    match &cred.location {
        SkillCredentialLocation::BasicAuth { username } => {
            assert_eq!(username, "admin");
        }
        other => panic!("expected BasicAuth, got {:?}", other),
    }
}

#[test]
fn test_parse_credentials_with_custom_refresh() {
    let yaml = r#"
name: slack
credentials:
  - name: slack_token
    provider: slack
    location:
      type: bearer
    hosts: ["slack.com"]
    oauth:
      authorization_url: "https://slack.com/oauth/v2/authorize"
      token_url: "https://slack.com/api/oauth.v2.access"
      scopes: ["chat:write"]
      refresh:
        strategy: custom
        refresh_url: "https://slack.com/api/oauth.v2.access"
        extra_params:
          grant_type: refresh_token
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let oauth = manifest.credentials[0].oauth.as_ref().unwrap();
    match &oauth.refresh {
        ProviderRefreshStrategy::Custom {
            refresh_url,
            extra_params,
        } => {
            assert_eq!(refresh_url, "https://slack.com/api/oauth.v2.access");
            assert_eq!(extra_params.get("grant_type").unwrap(), "refresh_token");
        }
        other => panic!("expected Custom, got {:?}", other),
    }
}

#[test]
fn test_parse_credentials_reauthorize_only() {
    let yaml = r#"
name: github
credentials:
  - name: github_token
    provider: github
    location:
      type: bearer
    hosts: ["api.github.com"]
    oauth:
      authorization_url: "https://github.com/login/oauth/authorize"
      token_url: "https://github.com/login/oauth/access_token"
      refresh:
        strategy: reauthorize_only
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let oauth = manifest.credentials[0].oauth.as_ref().unwrap();
    assert!(matches!(
        oauth.refresh,
        ProviderRefreshStrategy::ReauthorizeOnly
    ));
}

#[test]
fn test_parse_manifest_without_credentials_defaults_empty() {
    let yaml = r#"
name: simple-skill
description: No credentials needed
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    assert!(manifest.credentials.is_empty());
}

#[test]
fn test_credential_spec_serde_roundtrip() {
    let spec = SkillCredentialSpec {
        name: "token".to_string(),
        provider: "github".to_string(),
        location: SkillCredentialLocation::Bearer,
        hosts: vec!["api.github.com".to_string()],
        oauth: None,
        setup_instructions: Some("Go to Settings > Tokens".to_string()),
    };
    let json = serde_json::to_string(&spec).unwrap();
    let back: SkillCredentialSpec = serde_json::from_str(&json).unwrap();
    assert_eq!(back.name, "token");
    assert_eq!(back.provider, "github");
    assert_eq!(back.hosts, vec!["api.github.com"]);
    assert_eq!(
        back.setup_instructions.as_deref(),
        Some("Go to Settings > Tokens")
    );
}

#[test]
fn test_parse_credentials_with_extra_params() {
    let yaml = r#"
name: google-drive
credentials:
  - name: google_oauth_token
    provider: google
    location:
      type: bearer
    hosts: ["www.googleapis.com"]
    oauth:
      authorization_url: "https://accounts.google.com/o/oauth2/v2/auth"
      token_url: "https://oauth2.googleapis.com/token"
      scopes: ["https://www.googleapis.com/auth/drive"]
      use_pkce: true
      extra_params:
        access_type: offline
        prompt: consent
"#;
    let manifest: SkillManifest = serde_yml::from_str(yaml).expect("parse failed");
    let oauth = manifest.credentials[0].oauth.as_ref().unwrap();
    assert!(oauth.use_pkce);
    assert_eq!(oauth.extra_params.get("access_type").unwrap(), "offline");
    assert_eq!(oauth.extra_params.get("prompt").unwrap(), "consent");
}

#[test]
fn test_loaded_skill_default_owner_is_empty() {
    let skill = LoadedSkill {
        manifest: SkillManifest {
            name: "test".to_string(),
            display_name: None,
            version: "1.0.0".to_string(),
            description: String::new(),
            activation: ActivationCriteria::default(),
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "test".to_string(),
        trust: SkillTrust::Trusted,
        source: SkillSource::Bundled(PathBuf::from("test")),
        content_hash: "sha256:000".to_string(),
        compiled_patterns: vec![],
        lowercased_keywords: vec![],
        lowercased_exclude_keywords: vec![],
        lowercased_tags: vec![],
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: String::new(),
    };
    assert!(skill.owner_user_id.is_empty());
}

#[test]
fn test_owner_user_id_distinguishes_same_name_skills() {
    let skill_alice = LoadedSkill {
        manifest: SkillManifest {
            name: "my-skill".to_string(),
            display_name: None,
            version: "1.0.0".to_string(),
            description: "Alice's version".to_string(),
            activation: ActivationCriteria::default(),
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "Alice prompt".to_string(),
        trust: SkillTrust::Trusted,
        source: SkillSource::User(PathBuf::from("alice/my-skill")),
        content_hash: "sha256:aaa".to_string(),
        compiled_patterns: vec![],
        lowercased_keywords: vec![],
        lowercased_exclude_keywords: vec![],
        lowercased_tags: vec![],
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: "alice".to_string(),
    };

    let skill_bob = LoadedSkill {
        manifest: SkillManifest {
            name: "my-skill".to_string(),
            display_name: None,
            version: "2.0.0".to_string(),
            description: "Bob's version".to_string(),
            activation: ActivationCriteria::default(),
            credentials: vec![],
            requires: GatingRequirements::default(),
            metadata: serde_json::Value::Null,
        },
        prompt_content: "Bob prompt".to_string(),
        trust: SkillTrust::Trusted,
        source: SkillSource::User(PathBuf::from("bob/my-skill")),
        content_hash: "sha256:bbb".to_string(),
        compiled_patterns: vec![],
        lowercased_keywords: vec![],
        lowercased_exclude_keywords: vec![],
        lowercased_tags: vec![],
        compiled_metadata_patterns: vec![],
        lowercased_metadata_terms: vec![],
        owner_user_id: "bob".to_string(),
    };

    assert_ne!(skill_alice.owner_user_id, skill_bob.owner_user_id);
    assert_eq!(skill_alice.manifest.name, skill_bob.manifest.name);
}
