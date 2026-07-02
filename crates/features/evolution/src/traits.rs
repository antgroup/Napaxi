use async_trait::async_trait;
use std::any::Any;
use std::collections::HashMap;
use std::sync::Arc;

// ==================== Hook system ====================

/// Hook context
#[derive(Debug)]
pub struct HookContext {
    pub thread_id: String,
    pub messages: Vec<Message>,
    pub metadata: HashMap<String, String>,
}

impl HookContext {
    pub fn new(thread_id: impl Into<String>) -> Self {
        Self {
            thread_id: thread_id.into(),
            messages: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    pub fn add_system_message(&mut self, content: impl Into<String>) {
        self.messages.push(Message {
            role: Role::System,
            content: content.into(),
        });
    }
}

/// Message
#[derive(Debug, Clone)]
pub struct Message {
    pub role: Role,
    pub content: String,
}

/// Role
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    System,
    User,
    Assistant,
    Tool,
}

impl std::fmt::Display for Role {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Role::System => write!(f, "system"),
            Role::User => write!(f, "user"),
            Role::Assistant => write!(f, "assistant"),
            Role::Tool => write!(f, "tool"),
        }
    }
}

/// Tool call
#[derive(Debug, Clone)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: serde_json::Value,
}

/// Hook result
pub type HookResult = Result<(), Box<dyn std::error::Error + Send + Sync>>;

/// Hook trait - for event interception
#[async_trait]
pub trait Hook: Send + Sync {
    /// Called on conversation start
    async fn on_conversation_start(&self, ctx: &mut HookContext) -> HookResult {
        let _ = ctx;
        Ok(())
    }

    /// Called on user input
    async fn on_inbound(&self, ctx: &mut HookContext) -> HookResult {
        let _ = ctx;
        Ok(())
    }

    /// Called after each tool call
    async fn on_tool_call(&self, ctx: &mut HookContext, tool_call: &ToolCall) -> HookResult {
        let _ = ctx;
        let _ = tool_call;
        Ok(())
    }

    /// Called on conversation end
    async fn on_conversation_end(&self, ctx: &mut HookContext) -> HookResult {
        let _ = ctx;
        Ok(())
    }

    /// Convert to Any (for type checking)
    fn as_any(&self) -> &dyn Any;
}

/// Hook registry
#[derive(Default)]
pub struct HookRegistry {
    hooks: Vec<Arc<dyn Hook>>,
}

impl HookRegistry {
    pub fn new() -> Self {
        Self { hooks: Vec::new() }
    }

    pub fn register(&mut self, hook: Arc<dyn Hook>) {
        self.hooks.push(hook);
    }

    pub async fn trigger_conversation_start(&self, ctx: &mut HookContext) -> HookResult {
        for hook in &self.hooks {
            hook.on_conversation_start(ctx).await?;
        }
        Ok(())
    }

    pub async fn trigger_inbound(&self, ctx: &mut HookContext) -> HookResult {
        for hook in &self.hooks {
            hook.on_inbound(ctx).await?;
        }
        Ok(())
    }

    pub async fn trigger_tool_call(
        &self,
        ctx: &mut HookContext,
        tool_call: &ToolCall,
    ) -> HookResult {
        for hook in &self.hooks {
            hook.on_tool_call(ctx, tool_call).await?;
        }
        Ok(())
    }

    pub async fn trigger_conversation_end(&self, ctx: &mut HookContext) -> HookResult {
        for hook in &self.hooks {
            hook.on_conversation_end(ctx).await?;
        }
        Ok(())
    }
}

// ==================== Job system ====================

/// Job trait - for background task execution
#[async_trait]
pub trait Job: Send + Sync {
    /// Job execution result
    type Output: Send + Sync;

    /// Execute Job
    async fn execute(&self, ctx: &JobContext) -> Result<Self::Output, JobError>;

    /// Job type identifier
    fn job_type() -> &'static str
    where
        Self: Sized;

    /// Timeout (default 5 minutes)
    fn timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(300)
    }
}

/// Job context
#[derive(Debug, Clone)]
pub struct JobContext {
    pub job_id: String,
    pub metadata: HashMap<String, serde_json::Value>,
}

impl JobContext {
    pub fn new(job_id: impl Into<String>) -> Self {
        Self {
            job_id: job_id.into(),
            metadata: HashMap::new(),
        }
    }
}

/// Job schedule error
#[derive(Debug, thiserror::Error)]
pub enum JobScheduleError {
    #[error("Job queue is full")]
    QueueFull,
    #[error("Invalid job type: {0}")]
    InvalidJobType(String),
    #[error("Scheduler unavailable: {0}")]
    Unavailable(String),
}

/// Job error
#[derive(Debug, thiserror::Error)]
pub enum JobError {
    #[error("Job execution failed: {0}")]
    Execution(String),
    #[error("Job timeout")]
    Timeout,
    #[error("Job cancelled")]
    Cancelled,
}

// ==================== LLM integration ====================

/// LLM Provider trait - for main flow LLM integration
#[async_trait]
pub trait LlmProvider: Send + Sync {
    /// LLM full response (with tool calls)
    async fn complete_with_tools(
        &self,
        messages: &[Message],
        tools: Vec<ToolSchema>,
        timeout_secs: f64,
    ) -> Result<LlmResponse, String>;
}

/// LLM response structure
#[derive(Debug, Clone)]
pub struct LlmResponse {
    pub content: String,
    pub tool_calls: Vec<ToolCall>,
}

/// Job queue trait
///
/// Note: accepts erased Job type, allowing different Job types to coexist
#[async_trait]
pub trait JobQueue: Send + Sync {
    /// Schedule Job, returning job_id or schedule error
    async fn schedule(&self, job: Box<dyn AnyJob>) -> Result<String, JobScheduleError>;
}

/// Type-erased Job trait
#[async_trait]
pub trait AnyJob: Send + Sync {
    fn job_type(&self) -> &'static str;
    fn timeout(&self) -> std::time::Duration;
    async fn run(&self, ctx: &JobContext) -> Result<Box<dyn std::any::Any + Send>, JobError>;
}

/// Implement AnyJob for concrete Job types
#[async_trait]
impl<T> AnyJob for T
where
    T: Job + Send + Sync,
    T::Output: Send + 'static,
{
    fn job_type(&self) -> &'static str {
        T::job_type()
    }

    fn timeout(&self) -> std::time::Duration {
        Job::timeout(self)
    }

    async fn run(&self, ctx: &JobContext) -> Result<Box<dyn std::any::Any + Send>, JobError> {
        let result = self.execute(ctx).await?;
        Ok(Box::new(result))
    }
}

// ==================== Tool system ====================

/// Tool trait - for LLM tool calls
#[async_trait]
pub trait Tool: Send + Sync {
    /// Input type
    type Input: serde::de::DeserializeOwned + Send + schemars::JsonSchema;
    /// Output type
    type Output: serde::Serialize + Send;

    /// Execute tool
    async fn execute(&self, input: Self::Input) -> Result<Self::Output, ToolError>;

    /// Tool name
    fn name() -> &'static str
    where
        Self: Sized;

    /// Tool description
    fn description() -> &'static str
    where
        Self: Sized;

    /// Tool parameter JSON Schema
    fn schema() -> serde_json::Value
    where
        Self: Sized,
    {
        let schema = schemars::schema_for!(Self::Input);
        serde_json::to_value(schema).unwrap_or_else(|_| serde_json::json!({}))
    }
}

/// Tool error
#[derive(Debug, thiserror::Error)]
pub enum ToolError {
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("Execution failed: {0}")]
    Execution(String),
    #[error("Tool not found: {0}")]
    NotFound(String),
}

/// Tool registry
#[derive(Default)]
pub struct ToolRegistry {
    schemas: Vec<ToolSchema>,
}

#[derive(Debug, Clone)]
pub struct ToolSchema {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

impl ToolRegistry {
    pub fn new() -> Self {
        Self {
            schemas: Vec::new(),
        }
    }

    pub fn register<T: Tool>(&mut self) {
        self.schemas.push(ToolSchema {
            name: T::name().to_string(),
            description: T::description().to_string(),
            parameters: T::schema(),
        });
    }

    pub fn list(&self) -> Vec<ToolSchema> {
        self.schemas.clone()
    }

    pub fn describe_all(&self) -> Vec<ToolSchema> {
        self.schemas.clone()
    }
}

// ==================== Default implementations ====================

/// Default Job queue implementation (in-memory queue)
pub struct DefaultJobQueue;

impl Default for DefaultJobQueue {
    fn default() -> Self {
        Self::new()
    }
}

impl DefaultJobQueue {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl JobQueue for DefaultJobQueue {
    async fn schedule(&self, job: Box<dyn AnyJob>) -> Result<String, JobScheduleError> {
        let job_id = uuid::Uuid::new_v4().to_string();
        let job_id_clone = job_id.clone();
        let job_type = job.job_type();
        let timeout = job.timeout();

        // Execute Job immediately (using tokio::spawn for async execution)
        tokio::spawn(async move {
            let ctx = JobContext::new(&job_id_clone);
            tracing::info!(job_id = %job_id_clone, job_type, "[Evolution] Job started");

            match tokio::time::timeout(timeout, job.run(&ctx)).await {
                Ok(Ok(_)) => {
                    tracing::info!(job_id = %job_id_clone, job_type, "[Evolution] Job completed successfully");
                }
                Ok(Err(e)) => {
                    tracing::error!(job_id = %job_id_clone, job_type, error = %e, "[Evolution] Job failed");
                }
                Err(_) => {
                    tracing::error!(job_id = %job_id_clone, job_type, "[Evolution] Job timed out");
                }
            }
        });

        Ok(job_id)
    }
}
