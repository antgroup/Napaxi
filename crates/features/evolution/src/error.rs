use thiserror::Error;
use uuid::Uuid;

/// Skill evolution module unified error type
#[derive(Error, Debug)]
pub enum EvolutionError {
    // ============ Configuration/State Errors ============
    #[error("Evolution is disabled globally")]
    Disabled,

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("Skill {0} is not allowed to evolve")]
    SkillNotAllowed(String),

    #[error("Not found: {0}")]
    NotFound(String),

    // ============ Queue/Confirmation Errors ============
    #[error("Confirmation not found: {0}")]
    ConfirmationNotFound(Uuid),

    #[error("Confirmation {0} has expired")]
    ConfirmationExpired(Uuid),

    #[error("Confirmation {0} already processed with status: {1}")]
    AlreadyProcessed(Uuid, String),

    #[error("Invalid confirmation status: {0}")]
    InvalidStatus(String),

    #[error("Queue operation failed: {0}")]
    QueueError(String),

    #[error("Pending queue not available/initialized")]
    QueueUnavailable,

    // ============ Skill Operation Errors ============
    #[error("Skill not found: {0}")]
    SkillNotFound(String),

    #[error("Skill already exists: {0}")]
    SkillAlreadyExists(String),

    #[error("Invalid skill name: {0}")]
    InvalidSkillName(String),

    #[error("Invalid frontmatter: {0}")]
    InvalidFrontmatter(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Invalid path: {0}")]
    InvalidPath(String),

    #[error("Skill content too large ({0} bytes, max {1} bytes)")]
    SkillTooLarge(usize, usize),

    #[error("Patch failed: {0}")]
    PatchFailed(String),

    #[error("Security scan failed: {0}")]
    SecurityScanFailed(String),

    // ============ Rollback Errors ============
    #[error("Backup not found: {0}")]
    BackupNotFound(String),

    #[error("Backup corrupted: {0}")]
    BackupCorrupted(Uuid),

    #[error("Rollback failed: {0}")]
    RollbackFailed(String),

    // ============ Job Errors ============
    #[error("Job scheduling failed: {0}")]
    JobScheduleFailed(String),

    #[error("Job execution failed: {0}")]
    JobExecutionFailed(String),

    #[error("Review timeout after {0} seconds")]
    ReviewTimeout(u64),

    // ============ Storage Errors ============
    #[error("Storage error: {message}")]
    Storage { message: String },

    #[error("Serialization error: {0}")]
    Serialization(String),

    // ============ Hook Errors ============
    #[error("Hook execution error: {0}")]
    HookError(String),

    // ============ IO/System Errors ============
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Unexpected error: {0}")]
    Unexpected(String),
}

/// Result type alias
pub type EvolutionResult<T> = Result<T, EvolutionError>;

// ============ Standard Library Error Conversions ============

impl From<serde_json::Error> for EvolutionError {
    fn from(e: serde_json::Error) -> Self {
        EvolutionError::Serialization(e.to_string())
    }
}

impl From<serde_yaml::Error> for EvolutionError {
    fn from(e: serde_yaml::Error) -> Self {
        EvolutionError::Serialization(e.to_string())
    }
}

impl EvolutionError {
    /// Get user-friendly error message
    pub fn user_message(&self) -> String {
        match self {
            EvolutionError::Disabled => "Skill evolution is currently disabled".to_string(),

            EvolutionError::NotFound(key) => {
                if key == "nudge_state" {
                    "Counter state not initialized".to_string()
                } else {
                    format!("Not found: {}", key)
                }
            }

            EvolutionError::ConfirmationNotFound(_) => {
                "Confirmation request not found; it may have expired or been processed".to_string()
            }

            EvolutionError::ConfirmationExpired(_) => {
                "Confirmation request has timed out (30 minutes); please trigger a new review"
                    .to_string()
            }

            EvolutionError::AlreadyProcessed(_, status) => {
                format!("Request already processed, status: {}", status)
            }

            EvolutionError::SecurityScanFailed(details) => {
                format!("Security scan failed: {}", details)
            }

            EvolutionError::SkillNotFound(name) => format!("Skill '{}' does not exist", name),

            EvolutionError::SkillAlreadyExists(name) => format!("Skill '{}' already exists", name),

            EvolutionError::InvalidSkillName(reason) => {
                format!("Invalid skill name: {}", reason)
            }

            EvolutionError::PatchFailed(reason) => format!("Patch failed: {}", reason),

            EvolutionError::BackupCorrupted(_) => {
                "Backup file is corrupted, cannot rollback".to_string()
            }

            EvolutionError::Storage { message } => format!("Storage error: {}", message),

            EvolutionError::JobScheduleFailed(reason) => {
                format!("Job scheduling failed: {}", reason)
            }

            EvolutionError::JobExecutionFailed(reason) => {
                format!("Review execution failed: {}", reason)
            }

            EvolutionError::Io(e) => format!("File operation failed: {}", e),

            EvolutionError::Unexpected(msg) => format!("Unexpected error: {}", msg),

            _ => format!("Operation failed: {}", self),
        }
    }

    /// Whether the error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            EvolutionError::Storage { .. }
                | EvolutionError::Io(_)
                | EvolutionError::JobScheduleFailed(_)
                | EvolutionError::NotFound(_)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evolution_error_display() {
        let err = EvolutionError::Disabled;
        assert_eq!(format!("{}", err), "Evolution is disabled globally");

        let err = EvolutionError::SkillNotFound("test".to_string());
        assert!(format!("{}", err).contains("test"));

        let err = EvolutionError::ConfirmationNotFound(Uuid::new_v4());
        assert!(format!("{}", err).contains("Confirmation not found"));
    }

    #[test]
    fn test_evolution_error_user_message() {
        assert_eq!(
            EvolutionError::Disabled.user_message(),
            "Skill evolution is currently disabled"
        );

        let err = EvolutionError::ConfirmationNotFound(Uuid::new_v4());
        assert!(err
            .user_message()
            .contains("Confirmation request not found"));

        let err = EvolutionError::ConfirmationExpired(Uuid::new_v4());
        assert!(err.user_message().contains("timed out"));
    }

    #[test]
    fn test_evolution_error_is_retryable() {
        assert!(EvolutionError::Storage {
            message: "test".to_string()
        }
        .is_retryable());
        assert!(EvolutionError::Io(std::io::Error::other("test")).is_retryable());
        assert!(EvolutionError::JobScheduleFailed("test".to_string()).is_retryable());
        assert!(EvolutionError::NotFound("test".to_string()).is_retryable());

        assert!(!EvolutionError::Disabled.is_retryable());
        assert!(!EvolutionError::InvalidSkillName("test".to_string()).is_retryable());
    }

    #[test]
    fn test_from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let err: EvolutionError = io_err.into();
        assert!(matches!(err, EvolutionError::Io(_)));
    }

    #[test]
    fn test_from_serde_json_error() {
        let json_err = serde_json::from_str::<serde_json::Value>("invalid json").unwrap_err();
        let err: EvolutionError = json_err.into();
        assert!(matches!(err, EvolutionError::Serialization(_)));
    }

    #[test]
    fn test_from_serde_yaml_error() {
        let yaml_err = serde_yaml::from_str::<serde_json::Value>("[invalid yaml").unwrap_err();
        let err: EvolutionError = yaml_err.into();
        assert!(matches!(err, EvolutionError::Serialization(_)));
    }
}
