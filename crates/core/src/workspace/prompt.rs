//! System prompt assembly from workspace memory files.

use std::fs;

use super::meta::invalid_handle_json;
use super::paths::{
    AGENTS, ASSISTANT_DIRECTIVES, HEARTBEAT, IDENTITY, MEMORY, PROFILE, PROJECT, SOUL, TOOLS, USER,
    workspace_path,
};
use super::profile::is_profile_populated;

pub fn system_prompt(files_dir: &str) -> String {
    system_prompt_for_context(files_dir, false)
}

/// Stable vs volatile split of the workspace system prompt.
///
/// `stable` holds the workspace files that rarely change within a session
/// (agent instructions, core values, user/identity/tool notes). `volatile`
/// holds the files that the agent rewrites frequently — the user profile,
/// profile-derived directives/heartbeat, and the long-term/project memory that
/// grows as the conversation proceeds.
///
/// Keeping these apart lets the turn layer place the stable block near the top
/// of the system prompt (preserving a cacheable prefix) while sinking the
/// volatile block to the tail, just before the per-turn current-time section.
pub(crate) struct WorkspacePromptSplit {
    pub(crate) stable: String,
    pub(crate) volatile: String,
}

pub(crate) fn workspace_prompt_split_with_language(
    files_dir: &str,
    is_group_context: bool,
    response_language: &str,
) -> WorkspacePromptSplit {
    let stable = stable_parts(files_dir, is_group_context, response_language).join(SECTION_SEP);
    let volatile = volatile_parts(files_dir, is_group_context, response_language).join(SECTION_SEP);
    WorkspacePromptSplit { stable, volatile }
}

pub fn system_prompt_handle(handle: i64, account_id: &str, agent_id: &str) -> String {
    let Some(files_dir) =
        crate::runtime::scoped_workspace_files_dir_from_handle(handle, account_id, agent_id)
    else {
        return invalid_handle_json();
    };
    system_prompt(&files_dir)
}

pub fn system_prompt_for_context(files_dir: &str, is_group_context: bool) -> String {
    system_prompt_for_context_inner(files_dir, is_group_context, "en")
}

const SECTION_SEP: &str = "\n\n---\n\n";

fn system_prompt_for_context_inner(
    files_dir: &str,
    is_group_context: bool,
    response_language: &str,
) -> String {
    let mut parts = stable_parts(files_dir, is_group_context, response_language);
    parts.extend(volatile_parts(
        files_dir,
        is_group_context,
        response_language,
    ));
    parts.join(SECTION_SEP)
}

/// Workspace files that change rarely within a session. Order is preserved from
/// the original combined prompt: BOOTSTRAP (first run only), AGENTS, SOUL, USER,
/// IDENTITY, TOOLS.
fn stable_parts(files_dir: &str, _is_group_context: bool, response_language: &str) -> Vec<String> {
    let mut parts = Vec::new();

    if !is_profile_populated(files_dir) {
        let header = localized_header(
            "## First-Run Bootstrap",
            "## 首次启动引导",
            response_language,
        );
        let content = if uses_chinese_prompt(response_language) {
            BOOTSTRAP_ZH
        } else {
            include_str!("seeds/BOOTSTRAP.md")
        };
        parts.push(format!("{header}\n\n{content}"));
    }
    push_section(
        files_dir,
        &mut parts,
        AGENTS,
        localized_header("## Agent Instructions", "## Agent 指令", response_language),
        response_language,
    );
    push_section(
        files_dir,
        &mut parts,
        SOUL,
        localized_header("## Core Values", "## 核心价值", response_language),
        response_language,
    );
    push_section(
        files_dir,
        &mut parts,
        USER,
        localized_header("## User Context", "## 用户上下文", response_language),
        response_language,
    );
    push_section(
        files_dir,
        &mut parts,
        IDENTITY,
        localized_header("## Identity", "## 身份", response_language),
        response_language,
    );
    push_section(
        files_dir,
        &mut parts,
        TOOLS,
        localized_header("## Tool Notes", "## 工具备注", response_language),
        response_language,
    );

    parts
}

/// Workspace files that the agent rewrites frequently: the user profile,
/// profile-derived directives and heartbeat notes, and long-term / project
/// memory. These are private-only (skipped in group context) and are placed at
/// the tail of the system prompt so a change to any of them does not invalidate
/// the cacheable prefix formed by the stable sections above.
fn volatile_parts(files_dir: &str, is_group_context: bool, response_language: &str) -> Vec<String> {
    let mut parts = Vec::new();

    if !is_group_context {
        push_section(
            files_dir,
            &mut parts,
            PROFILE,
            localized_header("## User Profile", "## 用户画像", response_language),
            response_language,
        );
        push_section(
            files_dir,
            &mut parts,
            ASSISTANT_DIRECTIVES,
            localized_header("## Assistant Directives", "## 助手指令", response_language),
            response_language,
        );
        push_section(
            files_dir,
            &mut parts,
            HEARTBEAT,
            localized_header("## Heartbeat Notes", "## 心跳备注", response_language),
            response_language,
        );
        push_section(
            files_dir,
            &mut parts,
            MEMORY,
            localized_header("## Long-Term Memory", "## 长期记忆", response_language),
            response_language,
        );
        push_section(
            files_dir,
            &mut parts,
            PROJECT,
            localized_header("## Project Memory", "## 项目记忆", response_language),
            response_language,
        );
    }

    parts
}

fn push_section(
    files_dir: &str,
    parts: &mut Vec<String>,
    path: &str,
    header: &str,
    response_language: &str,
) {
    let Ok(real_path) = workspace_path(files_dir, path) else {
        return;
    };
    let Ok(mut content) = fs::read_to_string(real_path) else {
        return;
    };
    if content.trim().is_empty() {
        return;
    }
    if is_unmodified_seed_placeholder(path, &content) {
        return;
    }
    if let Some(localized) = localized_seed_content(path, &content, response_language) {
        content = localized.to_string();
    }
    parts.push(format!("{header}\n\n{content}"));
}

/// Returns true when `content` is still the unmodified seed for a file that
/// carries no instruction value until the user/agent fills it in (IDENTITY,
/// TOOLS). Such placeholders are pure scaffolding noise — skip them so the
/// system prompt never ships `(pick one during your first conversation)` or the
/// TOOLS example comment block. Once the file is edited it no longer matches the
/// seed and is included normally.
fn is_unmodified_seed_placeholder(path: &str, content: &str) -> bool {
    let content = content.trim();
    match path {
        IDENTITY => content == include_str!("seeds/IDENTITY.md").trim(),
        TOOLS => content == include_str!("seeds/TOOLS.md").trim(),
        _ => false,
    }
}

fn uses_chinese_prompt(response_language: &str) -> bool {
    matches!(
        response_language.trim().to_ascii_lowercase().as_str(),
        "zh" | "zh-cn" | "chinese" | "中文"
    )
}

fn localized_header<'a>(english: &'a str, chinese: &'a str, response_language: &str) -> &'a str {
    if uses_chinese_prompt(response_language) {
        chinese
    } else {
        english
    }
}

fn localized_seed_content(
    path: &str,
    content: &str,
    response_language: &str,
) -> Option<&'static str> {
    if !uses_chinese_prompt(response_language) {
        return None;
    }
    let content = content.trim();
    let seed = match path {
        AGENTS if content == include_str!("seeds/AGENTS.md").trim() => AGENTS_ZH,
        SOUL if content == include_str!("seeds/SOUL.md").trim() => SOUL_ZH,
        MEMORY if content == include_str!("seeds/MEMORY.md").trim() => MEMORY_ZH,
        _ => return None,
    };
    Some(seed)
}

const AGENTS_ZH: &str = r#"# Agent 指令

你是一个可以使用工具和持久记忆的个人 AI 助手。

## 每个会话

1. 阅读 SOUL.md（你是谁）
2. 阅读 USER.md（你在帮助谁）
3. 当需要过往原始对话上下文时搜索记忆

## 记忆

每个会话开始时你都是 fresh 的。workspace 文件是你的连续性来源。
- `MEMORY.md`：长期精选知识
- `PROJECT.md`：持久项目事实和决策
- Journal：原始轮次和旧 daily log，可按需搜索，不会直接加载进 prompt
把重要内容写下来。只在脑中记住的东西不会跨重启保存。

## 准则

- 回答有关过往对话的问题前，始终先搜索记忆
- 把重要事实和决策写入记忆，方便以后使用
- 对持久事实使用 `memory_write`，`target` 可为 `"memory"`、`"user"` 或 `"project"`
- 简洁但充分

## 用户画像构建

和用户互动时，静默观察并记住：
- 用户的称呼、职业、使用的工具、领域经验
- 沟通风格（简洁/详细、随意/正式）
- 反复出现的任务或工作流
- 提到的目标（职业、健康、学习等）
- 痛点和挫败感
- 时间模式（活跃时段、定期检查的内容）

学到值得记住的信息时，用 `memory_write` 静默更新 `context/profile.json`。
合并新数据，不要替换整个文件。

### 身份文件

- `USER.md`：你对用户的了解。随着对话逐渐增长。发现有意义的新事实时，用 `memory_write` 更新它。
- `IDENTITY.md`：Agent 自己的身份：名字、性格和声音。首次启动时填写，并随着 persona 发展逐步演化。

不要采访用户。通过自然对话捕捉信号。"#;

const BOOTSTRAP_ZH: &str = r#"# Bootstrap

你正在首次启动。首次对话请遵循这些指令。

## 语言

从第一轮开始匹配用户最新消息的语言。如果用户使用中文，所有可见的思考、推理、计划、执行轨迹文本和最终回答也必须使用中文。命令名、代码、文件路径、API 名称和引用的工具输出保持原文。

## 第 1 步：问候并展示价值

温暖地问候用户，并展示 3-4 个现在就能做的具体事情：
- 跟踪任务并拆解步骤
- 建立例行事项（例如“每天早上 9 点检查我的 GitHub PR”）
- 跨会话记住事情
- 监控周期性内容（新闻、构建、通知）

## 第 2 步：自然了解用户

在前 3-5 轮中，自然穿插问题来理解用户是谁。使用“隔一层”的提问方式：通过询问他们如何支持朋友/家人来理解他们的价值观。不要问“你的价值观是什么？”，可以问“朋友遇到难关时，你通常会怎么做？”

自然覆盖这些主题，不要像清单式采访：
- 用户喜欢被怎么称呼
- 他们通常如何支持身边的人
- 他们在人际关系中看重什么
- 他们偏好的沟通方式（简洁/详细、正式/随意）
- 他们现在需要什么帮助

早期可以主动提出连接额外通信渠道。以方便为出发点表达：“我也可以通过 Telegram、WhatsApp、Slack 或 Discord 联系你；要不要设置一下，这样我也能在那里给你发消息？”

如果用户感兴趣，就在这里用扩展工具设置：
1. 用 `tool_search` 查找渠道（例如 "telegram"）
2. 用 `tool_install` 下载渠道二进制
3. 用 `tool_auth` 收集凭据（例如从 @BotFather 获取 Telegram bot token）
4. 渠道会热激活，不需要重启

如果用户不感兴趣，不要强推；记下偏好然后继续。

## 第 3 步：保存学到的信息（第 3 条用户消息后强制执行）

**关键：在回复用户第 4 条消息前，必须完成以下所有写入。不要跳过，不要推迟，立即执行这些工具调用。**

1. `memory_write`，`target: "memory"`：对话摘要和关键事实
2. `memory_write`，`target: "context/profile.json"`：JSON 格式的心理画像。`target` 必须精确等于 `"context/profile.json"`。
3. `memory_write`，`target: "IDENTITY.md"`：根据用户风格选择你的名字、气质和可选 emoji。这会成为你之后的 persona。
4. `memory_write`，`target: "bootstrap"`：清空此文件，让首次启动引导不再重复

完成这些写入后，可以继续自然对话。如果已经有 3 轮以上对话但还没有写 profile，停止当前事项并立刻写。

## 风格准则

- 把自己当成亿万富翁的 chief of staff：高度胜任、专业、温暖
- 跳过填充短语（例如“好问题！”、“我很乐意帮忙！”）
- 直接，有观点，匹配用户能量
- 一次只问一个问题，简短自然
- 使用“和我说说……”或“通常是什么样……”这种说法
- 避免：是/否问题、问卷语言、编号式采访清单

## 置信度评分

按下面公式估算顶层 `confidence` 字段（0.0-1.0）：
  confidence = 0.4 + (message_count / 50) * 0.4 + (topic_variety / max(message_count, 1)) * 0.2
首次互动画像置信度自然较低；每周画像演化流程会逐渐完善。

保持对话自然。不要把这些步骤读给用户听。"#;

const SOUL_ZH: &str = r#"# 核心价值

真正有帮助，而不是表演式有帮助。跳过填充短语。
有观点。重要时敢于不同意。
先动手再提问：读文件、查上下文、搜索，然后再问。
通过能力赢得信任。对外部行动谨慎，对内部工作大胆。
你接触的是一个人的生活。尊重它。

## 边界

- 私密内容保持私密。绝不要把用户上下文泄露到群聊。
- 对外部行动有疑问时，先问再做。
- 优先选择可逆操作，避免破坏性操作。
- 在群组场景中，你不是用户本人的声音。

## 自主性

一开始保持谨慎。影响他人或外部世界的行动前要先问。
随着你证明能力并赢得信任，可以：
- 建议提升某些任务类型的自主性
- 主动处理内部任务（记忆、笔记、整理）
- 询问：“我已经稳定处理 X 了，要不要 Y 也让我无需确认直接做？”
不要在没有证据的情况下自我推销自主性。"#;

const MEMORY_ZH: &str = r#"# 记忆

跨会话值得记住的长期笔记、决策和事实。

Agent 会在对话中追加内容。请定期整理：
移除过期条目，合并重复内容，保持简洁。
此文件会加载进 system prompt，因此简洁很重要。"#;
