use super::*;

#[test]
fn test_default_registry_url() {
    // When CLAWHUB_REGISTRY is not set, should use default
    let catalog = SkillCatalog::with_url(DEFAULT_REGISTRY_URL);
    assert_eq!(catalog.registry_url(), DEFAULT_REGISTRY_URL);
}

#[test]
fn test_custom_registry_url() {
    let catalog = SkillCatalog::with_url("https://custom.registry.example");
    assert_eq!(catalog.registry_url(), "https://custom.registry.example");
}

#[tokio::test]
async fn test_search_returns_error_on_network_failure() {
    // Use RFC 5737 TEST-NET-1 (192.0.2.0/24) for reliable failure even behind proxies.
    // Short timeout so the test doesn't block for the full 10s REQUEST_TIMEOUT.
    let catalog =
        SkillCatalog::with_url_and_timeout("http://192.0.2.1:9999", Duration::from_secs(1));
    let outcome = catalog.search("test").await;
    assert!(outcome.results.is_empty());
    assert!(outcome.error.is_some());
    let error = outcome.error.unwrap();
    assert!(
        error.contains("Registry unreachable")
            || error.contains("connect")
            || error.contains("502")
            || error.contains("503")
            || error.contains("504"),
        "Expected connection or gateway error, got: {error}",
    );
}

#[tokio::test]
async fn test_cache_is_populated_after_search() {
    let catalog = SkillCatalog::with_url("http://127.0.0.1:1");

    // First search populates cache (even with empty results)
    catalog.search("cached-query").await;

    let cache = catalog.cache.read().await;
    assert!(cache.iter().any(|c| c.query == "cached-query"));
}

#[tokio::test]
async fn test_clear_cache() {
    let catalog = SkillCatalog::with_url("http://127.0.0.1:1");
    catalog.search("something").await;

    catalog.clear_cache().await;
    let cache = catalog.cache.read().await;
    assert!(cache.is_empty());
}

#[test]
fn test_skill_download_url() {
    let url = skill_download_url("https://clawhub.ai", "owner/my-skill");
    assert_eq!(
        url,
        "https://clawhub.ai/api/v1/download?slug=owner%2Fmy-skill"
    );
}

#[test]
fn test_skill_download_url_encodes_special_chars() {
    let url = skill_download_url("https://clawhub.ai", "foo&bar=baz#frag");
    assert!(url.contains("slug=foo%26bar%3Dbaz%23frag"));
}

#[test]
fn test_resolve_catalog_slug_for_name_unique_match() {
    let entries = vec![CatalogEntry {
        slug: "finance/mortgage-calculator".to_string(),
        name: "Mortgage Calculator".to_string(),
        description: String::new(),
        version: String::new(),
        score: 1.0,
        updated_at: None,
        stars: None,
        downloads: None,
        installs_current: None,
        owner: None,
    }];

    assert_eq!(
        resolve_catalog_slug_for_name("Mortgage Calculator", &entries).unwrap(),
        Some("finance/mortgage-calculator".to_string())
    );
    assert_eq!(
        resolve_catalog_slug_for_name("mortgage-calculator", &entries).unwrap(),
        Some("finance/mortgage-calculator".to_string())
    );
}

#[test]
fn test_resolve_catalog_slug_for_name_ambiguous() {
    let entries = vec![
        CatalogEntry {
            slug: "alice/mortgage-calculator".to_string(),
            name: "Mortgage Calculator".to_string(),
            description: String::new(),
            version: String::new(),
            score: 1.0,
            updated_at: None,
            stars: None,
            downloads: None,
            installs_current: None,
            owner: None,
        },
        CatalogEntry {
            slug: "bob/mortgage-calculator".to_string(),
            name: "Mortgage Calculator".to_string(),
            description: String::new(),
            version: String::new(),
            score: 0.9,
            updated_at: None,
            stars: None,
            downloads: None,
            installs_current: None,
            owner: None,
        },
    ];

    let err = resolve_catalog_slug_for_name("Mortgage Calculator", &entries).unwrap_err();
    assert!(matches!(err, CatalogResolveError::AmbiguousName { .. }));
    assert!(err.to_string().contains("use a slug instead"));
}

#[test]
fn test_resolve_catalog_slug_for_name_prefers_exact_display_name() {
    let entries = vec![
        CatalogEntry {
            slug: "alice/ab".to_string(),
            name: "AB".to_string(),
            description: String::new(),
            version: String::new(),
            score: 1.0,
            updated_at: None,
            stars: None,
            downloads: None,
            installs_current: None,
            owner: None,
        },
        CatalogEntry {
            slug: "bob/a-b".to_string(),
            name: "A-B".to_string(),
            description: String::new(),
            version: String::new(),
            score: 0.9,
            updated_at: None,
            stars: None,
            downloads: None,
            installs_current: None,
            owner: None,
        },
    ];

    assert_eq!(
        resolve_catalog_slug_for_name("AB", &entries).unwrap(),
        Some("alice/ab".to_string())
    );
}

#[test]
fn test_catalog_entry_is_installed_matches_normalized_slug_name() {
    let installed = vec!["finance-mortgage-calculator".to_string()];

    assert!(catalog_entry_is_installed(
        "finance/mortgage-calculator",
        "Mortgage Calculator",
        &installed,
    ));
}

#[test]
fn test_catalog_entry_is_installed_does_not_match_partial_suffix() {
    let installed = vec!["calculator".to_string()];

    assert!(!catalog_entry_is_installed(
        "alice/mortgage-calculator",
        "Mortgage Calculator",
        &installed,
    ));
}

#[test]
fn test_parse_wrapped_response() {
    // ClawHub returns {"results": [...]} format
    let json = r#"{"results":[{"slug":"markdown","displayName":"Markdown","summary":"A skill","version":"1.0.0","score":3.5}]}"#;
    let envelope: CatalogSearchEnvelope = serde_json::from_str(json).unwrap();
    assert_eq!(envelope.results.len(), 1);
    assert_eq!(envelope.results[0].slug, "markdown");
    assert_eq!(
        envelope.results[0].display_name.as_deref(),
        Some("Markdown")
    );
}

#[test]
fn test_parse_bare_array_response() {
    // Fallback: bare array format
    let json = r#"[{"slug":"markdown","displayName":"Markdown","summary":"A skill","version":"1.0.0","score":3.5}]"#;
    let results: Vec<CatalogSearchResult> = serde_json::from_str(json).unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].slug, "markdown");
}

#[test]
fn test_parse_skill_detail() {
    // Response format matches the actual ClawHub API: {"skill": {...}, "owner": {...}}
    let json = r#"{
            "skill": {
                "slug": "steipete/markdown-writer",
                "displayName": "Markdown Writer",
                "summary": "Write markdown docs",
                "stats": {
                    "stars": 142,
                    "downloads": 8400,
                    "installsCurrent": 55,
                    "installsAllTime": 200,
                    "versions": 5
                },
                "updatedAt": 1700000000000
            },
            "owner": {
                "handle": "steipete",
                "displayName": "Peter S."
            },
            "latestVersion": {
                "version": "1.2.3",
                "createdAt": 1700000000000,
                "changelog": ""
            }
        }"#;

    let wrapper: SkillDetailResponse = serde_json::from_str(json).unwrap();
    let inner = &wrapper.skill;
    assert_eq!(inner.slug, "steipete/markdown-writer");
    assert_eq!(inner.display_name.as_deref(), Some("Markdown Writer"));

    let stats = inner.stats.as_ref().unwrap();
    assert_eq!(stats.stars, Some(142));
    assert_eq!(stats.downloads, Some(8400));
    assert_eq!(stats.installs_current, Some(55));

    let owner = wrapper.owner.as_ref().unwrap();
    assert_eq!(owner.handle.as_deref(), Some("steipete"));
}

#[tokio::test]
async fn test_fetch_skill_detail_returns_none_on_error() {
    let catalog = SkillCatalog::with_url("http://127.0.0.1:1");
    let result = catalog.fetch_skill_detail("nonexistent/skill").await;
    assert!(result.is_none());
}

#[test]
fn test_catalog_entry_serde() {
    let entry = CatalogEntry {
        slug: "test/skill".to_string(),
        name: "Test Skill".to_string(),
        description: "A test".to_string(),
        version: "1.0.0".to_string(),
        score: 0.95,
        updated_at: Some(1700000000000),
        stars: Some(42),
        downloads: Some(1000),
        installs_current: None,
        owner: Some("tester".to_string()),
    };
    let json = serde_json::to_string(&entry).unwrap();
    let parsed: CatalogEntry = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.slug, "test/skill");
    assert_eq!(parsed.name, "Test Skill");
}
