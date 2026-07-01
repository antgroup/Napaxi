use serde::{Deserialize, Serialize};

/// Skill evolution module status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvolutionStatus {
    /// Fully enabled
    #[default]
    Enabled,
    /// Selectively enabled (only whitelisted skills)
    Selective,
    /// Fully disabled
    Disabled,
}

/// Skill evolution module configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionConfig {
    /// Global enable status
    #[serde(default)]
    pub status: EvolutionStatus,

    /// User ID (multi-user isolation support)
    #[serde(default)]
    pub user_id: String,

    /// Memory nudge interval (conversation turns)
    #[serde(default = "default_memory_interval")]
    pub memory_nudge_interval: usize,

    /// Memory flush minimum turns
    #[serde(default = "default_memory_flush_turns")]
    pub memory_flush_min_turns: usize,

    /// Skill nudge interval (tool call count)
    #[serde(default = "default_skill_interval")]
    pub skill_nudge_interval: usize,

    /// Background review timeout (seconds)
    #[serde(default = "default_review_timeout")]
    pub review_timeout_secs: u64,

    /// Minimum cooldown between same-type reviews (seconds)
    #[serde(default = "default_review_cooldown")]
    pub review_cooldown_secs: u64,

    /// Rollback retained version count
    #[serde(default = "default_max_versions")]
    pub max_backup_versions: usize,

    /// Whitelist (used when status = Selective)
    #[serde(default)]
    pub enabled_skills: Vec<String>,

    /// Blacklist (takes priority over whitelist)
    #[serde(default)]
    pub disabled_skills: Vec<String>,

    /// Security policy
    #[serde(default)]
    pub security: SecurityPolicy,
}

fn default_memory_interval() -> usize {
    10
}
fn default_memory_flush_turns() -> usize {
    6
}
fn default_skill_interval() -> usize {
    10
}
fn default_review_timeout() -> u64 {
    60
}
fn default_review_cooldown() -> u64 {
    60
}
fn default_max_versions() -> usize {
    5
}

impl Default for EvolutionConfig {
    fn default() -> Self {
        Self {
            status: EvolutionStatus::default(),
            user_id: "default".to_string(),
            memory_nudge_interval: default_memory_interval(),
            memory_flush_min_turns: default_memory_flush_turns(),
            skill_nudge_interval: default_skill_interval(),
            review_timeout_secs: default_review_timeout(),
            review_cooldown_secs: default_review_cooldown(),
            max_backup_versions: default_max_versions(),
            enabled_skills: Vec::new(),
            disabled_skills: Vec::new(),
            security: SecurityPolicy::default(),
        }
    }
}

/// Security policy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityPolicy {
    /// Enforce security scan before editing
    #[serde(default = "default_true")]
    pub require_scan_before_edit: bool,

    /// Require user confirmation (low/medium confidence)
    #[serde(default = "default_true")]
    pub require_user_confirmation: bool,

    /// Maximum skill content length (characters)
    #[serde(default = "default_max_skill_content")]
    pub max_skill_content_chars: usize,

    /// Maximum supported file size (bytes)
    #[serde(default = "default_max_file_bytes")]
    pub max_skill_file_bytes: usize,

    /// Auto-rollback retention (auto-backup before modification)
    #[serde(default = "default_true")]
    pub auto_backup_before_edit: bool,

    /// Minimum trigger complexity (tool call count)
    #[serde(default = "default_min_complexity")]
    pub min_complexity_threshold: usize,

    /// Auto-execute high-confidence suggestions
    #[serde(default = "default_false")]
    pub auto_apply_high_confidence: bool,

    /// Similarity threshold for aggregating similar suggestions (0.0-1.0)
    #[serde(default = "default_similarity_threshold")]
    pub similarity_threshold: f64,

    /// Maximum suggestions generated per review
    #[serde(default = "default_max_suggestions_per_review")]
    pub max_suggestions_per_review: usize,
}

fn default_false() -> bool {
    false
}
fn default_similarity_threshold() -> f64 {
    0.8
}
fn default_max_suggestions_per_review() -> usize {
    5
}

fn default_true() -> bool {
    true
}
fn default_max_skill_content() -> usize {
    100_000
}
fn default_max_file_bytes() -> usize {
    1_048_576
}
fn default_min_complexity() -> usize {
    5
}

impl Default for SecurityPolicy {
    fn default() -> Self {
        Self {
            require_scan_before_edit: true,
            require_user_confirmation: true,
            max_skill_content_chars: default_max_skill_content(),
            max_skill_file_bytes: default_max_file_bytes(),
            auto_backup_before_edit: true,
            min_complexity_threshold: default_min_complexity(),
            auto_apply_high_confidence: false,
            similarity_threshold: default_similarity_threshold(),
            max_suggestions_per_review: default_max_suggestions_per_review(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = EvolutionConfig::default();
        assert_eq!(config.status, EvolutionStatus::Enabled);
        assert_eq!(config.memory_nudge_interval, 10);
        assert_eq!(config.skill_nudge_interval, 10);
        assert_eq!(config.review_timeout_secs, 60);
        assert!(config.security.require_scan_before_edit);
    }

    #[test]
    fn test_yaml_deserialization() {
        let yaml = r#"
status: enabled
memory_nudge_interval: 20
skill_nudge_interval: 15
security:
  max_skill_content_chars: 50000
"#;
        let config: EvolutionConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.memory_nudge_interval, 20);
        assert_eq!(config.skill_nudge_interval, 15);
        assert_eq!(config.security.max_skill_content_chars, 50000);
    }

    #[test]
    fn test_evolution_status_disabled() {
        let yaml = r#"
status: disabled
memory_nudge_interval: 10
"#;
        let config: EvolutionConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.status, EvolutionStatus::Disabled);
    }

    #[test]
    fn test_evolution_status_selective() {
        let yaml = r#"
status: selective
enabled_skills:
  - skill1
  - skill2
disabled_skills:
  - skill3
"#;
        let config: EvolutionConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.status, EvolutionStatus::Selective);
        assert_eq!(config.enabled_skills, vec!["skill1", "skill2"]);
        assert_eq!(config.disabled_skills, vec!["skill3"]);
    }

    #[test]
    fn test_security_policy_defaults() {
        let policy = SecurityPolicy::default();
        assert!(policy.require_scan_before_edit);
        assert!(policy.require_user_confirmation);
        assert!(policy.auto_backup_before_edit);
        assert_eq!(policy.max_skill_content_chars, 100_000);
        assert_eq!(policy.max_skill_file_bytes, 1_048_576);
        assert_eq!(policy.min_complexity_threshold, 5);
    }

    #[test]
    fn test_config_default_values() {
        let config = EvolutionConfig::default();
        assert_eq!(config.memory_nudge_interval, 10);
        assert_eq!(config.skill_nudge_interval, 10);
        assert_eq!(config.review_timeout_secs, 60);
        assert_eq!(config.max_backup_versions, 5);
        assert_eq!(config.memory_flush_min_turns, 6);
    }
}