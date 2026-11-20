    use super::*;
    use chrono::Utc;

    fn message(id: &str, role: &str, content: &str) -> SessionMessage {
        SessionMessage {
            id: id.to_string(),
            role: role.to_string(),
            content: content.to_string(),
            created_at: Utc::now().to_rfc3339(),
            interrupted: false,
            turn_id: None,
        }
    }

    #[test]
    fn derives_focus_from_recent_user_turns() {
        let history = vec![
            message("m1", "user", "first ask"),
            message("m2", "assistant", "ok"),
            message("m3", "user", "second ask"),
            message("m4", "assistant", "ok"),
            message("m5", "user", "third ask"),
        ];
        let focus = derive_auto_focus_topic(&history).expect("focus");
        assert!(focus.starts_with("Recent user focus:"));
        assert!(focus.contains("- first ask"));
        assert!(focus.contains("- second ask"));
        assert!(focus.contains("- third ask"));
    }

    #[test]
    fn limits_to_three_most_recent_turns() {
        let history = vec![
            message("m1", "user", "oldest"),
            message("m2", "user", "two"),
            message("m3", "user", "three"),
            message("m4", "user", "newest"),
        ];
        let focus = derive_auto_focus_topic(&history).expect("focus");
        assert!(!focus.contains("oldest"));
        assert!(focus.contains("- newest"));
    }

    #[test]
    fn skips_persisted_summary_handoff() {
        let history = vec![
            message("m1", "user", "## Conversation Context Summary\nstale topic"),
            message("m2", "assistant", "ok"),
            message("m3", "user", "current real ask"),
        ];
        let focus = derive_auto_focus_topic(&history).expect("focus");
        assert!(focus.contains("- current real ask"));
        assert!(!focus.contains("stale topic"));
    }

    #[test]
    fn returns_none_without_user_turns() {
        let history = vec![message("m1", "assistant", "hello")];
        assert!(derive_auto_focus_topic(&history).is_none());
    }
