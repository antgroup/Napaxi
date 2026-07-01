use chrono::Utc;
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use std::collections::HashMap;

use crate::types::{ActivatedSkillInfo, AttachmentKind, IncomingAttachment, PlatformLlmConfig};

pub struct ChatRuntimeInput<'a> {
    pub files_dir: &'a str,
    pub workspace_files_dir: &'a str,
    pub agent_id: &'a str,
    pub thread_id: &'a str,
    pub message: &'a str,
    pub attachments: &'a [IncomingAttachment],
    pub has_shell_tool: bool,
    pub has_browser_tool: bool,
    pub is_group_context: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum PromptSectionSource {
    ResponseLanguage,
    Workspace,
    WorkspaceVolatile,
    HostSystem,
    ContextSummary,
    SkillCatalog,
    SceneGuidance,
    MediaTool,
    ActiveSkill,
    GroupContext,
    BrowserTool,
    CurrentTime,
    ShellTool,
    ApplyPatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum PromptSectionVisibility {
    Private,
    GroupSafe,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum PromptPriority {
    Required,
    High,
    Normal,
    Low,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PromptSection {
    pub(crate) source: PromptSectionSource,
    pub(crate) visibility: PromptSectionVisibility,
    pub(crate) priority: PromptPriority,
    pub(crate) content: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct PromptPlan {
    pub(crate) sections: Vec<PromptSection>,
    pub(crate) active_skills: Vec<ActivatedSkillInfo>,
    pub(crate) skill_catalog_names: Vec<String>,
    pub(crate) skill_catalog_hashes: HashMap<String, String>,
    pub(crate) skill_snapshot_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct PromptSectionSummary {
    pub(crate) source: PromptSectionSource,
    pub(crate) visibility: PromptSectionVisibility,
    pub(crate) priority: PromptPriority,
    pub(crate) char_count: usize,
    pub(crate) sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct PromptPlanSummary {
    pub(crate) sections: Vec<PromptSectionSummary>,
    pub(crate) compiled_char_count: usize,
    pub(crate) compiled_sha256: String,
}

impl PromptPlan {
    pub(super) fn summary(&self) -> PromptPlanSummary {
        let compiled_prompt = compile_prompt_content(self);
        PromptPlanSummary {
            sections: self
                .sections
                .iter()
                .map(|section| PromptSectionSummary {
                    source: section.source,
                    visibility: section.visibility,
                    priority: section.priority,
                    char_count: section.content.chars().count(),
                    sha256: sha256_hex(&section.content),
                })
                .collect(),
            compiled_char_count: compiled_prompt.chars().count(),
            compiled_sha256: sha256_hex(&compiled_prompt),
        }
    }
}

pub(super) fn compile_prompt_content(prompt: &PromptPlan) -> String {
    prompt
        .sections
        .iter()
        .map(|section| section.content.as_str())
        .collect::<Vec<_>>()
        .join("\n\n")
}

#[cfg_attr(test, allow(dead_code))]
fn sha256_hex(value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(value.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
pub(super) fn test_sha256_hex(value: &str) -> String {
    sha256_hex(value)
}

#[allow(dead_code)]
pub async fn prepare_chat_config(
    config: PlatformLlmConfig,
    input: ChatRuntimeInput<'_>,
) -> PlatformLlmConfig {
    let prompt = prepare_prompt_sections(&config, input).await;
    compile_prompt_sections(config, &prompt)
}

pub(crate) async fn prepare_prompt_sections(
    config: &PlatformLlmConfig,
    input: ChatRuntimeInput<'_>,
) -> PromptPlan {
    let workspace_files_dir = if input.workspace_files_dir.trim().is_empty() {
        input.files_dir
    } else {
        input.workspace_files_dir
    };

    let _ = crate::workspace::reseed_workspace(workspace_files_dir);

    let response_language = config.response_language.as_str();
    let workspace_split = crate::workspace::workspace_prompt_split_with_language(
        workspace_files_dir,
        input.is_group_context,
        response_language,
    );
    let skill_prompt = crate::skills::active_skill_prompt_with_metadata_for_turn(
        input.files_dir,
        input.agent_id,
        input.thread_id,
        input.message,
        response_language,
    )
    .await;
    let active_skills = skill_prompt.skills;
    let skill_catalog_names = skill_prompt.catalog_skill_names;
    let skill_catalog_hashes = skill_prompt.catalog_skill_hashes;
    let skill_snapshot_id = skill_prompt.snapshot_id;
    let skill_catalog_prompt = skill_prompt.catalog_prompt;
    let skill_prompt = skill_prompt.prompt;
    let time_prompt = current_time_prompt(config, response_language);
    let shell_prompt = if input.has_shell_tool {
        shell_tool_prompt(response_language)
    } else {
        String::new()
    };
    let browser_prompt = if input.has_browser_tool {
        browser_tool_prompt(response_language)
    } else {
        String::new()
    };
    let mut scene_matches = crate::scene_prompt::build_scene_guidance_with_language(
        config.scene_prompt_config.as_ref(),
        input.message,
        input.attachments,
        response_language,
    );
    scene_matches.extend(crate::scene_prompt::build_scenario_runtime_guidance(
        &config.capability_selection,
        response_language,
    ));
    let scene_prompt = crate::scene_prompt::format_scene_guidance(&scene_matches);
    let media_tool_prompt = media_tool_prompt(config, input.attachments, response_language);
    let language_prompt = response_language_prompt(response_language);

    let mut sections = Vec::new();
    push_prompt_section(
        &mut sections,
        PromptSectionSource::ResponseLanguage,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::Required,
        language_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::Workspace,
        if input.is_group_context {
            PromptSectionVisibility::GroupSafe
        } else {
            PromptSectionVisibility::Private
        },
        PromptPriority::High,
        workspace_split.stable,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::HostSystem,
        PromptSectionVisibility::Private,
        PromptPriority::High,
        config.system_prompt.clone(),
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::SceneGuidance,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::Normal,
        scene_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::SkillCatalog,
        PromptSectionVisibility::Private,
        PromptPriority::Low,
        skill_catalog_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::MediaTool,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::High,
        media_tool_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::ActiveSkill,
        PromptSectionVisibility::Private,
        PromptPriority::Normal,
        skill_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::GroupContext,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::Required,
        group_context_prompt(input.is_group_context, response_language),
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::BrowserTool,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::High,
        browser_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::ShellTool,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::High,
        shell_prompt,
    );
    push_prompt_section(
        &mut sections,
        PromptSectionSource::ApplyPatch,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::High,
        apply_patch_prompt(response_language),
    );
    // WorkspaceVolatile (user profile, profile-derived directives/heartbeat,
    // long-term/project memory) is sunk to the tail because the agent rewrites
    // these files frequently within a session. Keeping them below the static
    // instruction sections preserves a stable, cacheable prefix; a memory or
    // profile write only invalidates the cache from here onward instead of from
    // the second section. It sits just above CurrentTime, which still changes
    // every turn.
    push_prompt_section(
        &mut sections,
        PromptSectionSource::WorkspaceVolatile,
        if input.is_group_context {
            PromptSectionVisibility::GroupSafe
        } else {
            PromptSectionVisibility::Private
        },
        PromptPriority::Normal,
        workspace_split.volatile,
    );
    // CurrentTime is pushed last on purpose: it is the only section whose
    // content changes every turn. Keeping it at the tail of the system prompt
    // preserves a stable prefix for all preceding (static) sections, so the
    // provider-side prompt cache (Anthropic / OpenAI / Gemini auto prefix
    // caching) can hit on everything above it instead of missing from the
    // first changed byte onward.
    push_prompt_section(
        &mut sections,
        PromptSectionSource::CurrentTime,
        PromptSectionVisibility::GroupSafe,
        PromptPriority::Low,
        time_prompt,
    );
    PromptPlan {
        sections,
        active_skills,
        skill_catalog_names,
        skill_catalog_hashes,
        skill_snapshot_id,
    }
}

pub(crate) fn compile_prompt_sections(
    mut config: PlatformLlmConfig,
    prompt: &PromptPlan,
) -> PlatformLlmConfig {
    config.system_prompt = compile_prompt_content(prompt);
    config
}

fn push_prompt_section(
    sections: &mut Vec<PromptSection>,
    source: PromptSectionSource,
    visibility: PromptSectionVisibility,
    priority: PromptPriority,
    content: String,
) {
    if !content.trim().is_empty() {
        sections.push(PromptSection {
            source,
            visibility,
            priority,
            content,
        });
    }
}

fn response_language_prompt(response_language: &str) -> String {
    let normalized = response_language.trim().to_ascii_lowercase();
    let instruction = match normalized.as_str() {
        "" | "en" | "english" => {
            "Use English for the final answer and for any visible reasoning, thinking, planning, or trace text that may be shown to the user, unless the user explicitly asks for another language."
        }
        "zh" | "zh-cn" | "chinese" | "中文" => {
            "使用中文回答用户，并且任何可能展示给用户的推理、思考、计划或执行轨迹文本也使用中文，除非用户明确要求使用其他语言。"
        }
        _ => {
            "Match the language of the user's latest message for the final answer and for any visible reasoning, thinking, planning, or trace text that may be shown to the user. If the user writes in Chinese, keep those visible thinking/trace updates in Chinese too."
        }
    };
    if uses_chinese_prompt(&normalized) {
        format!(
            "## 响应语言\n\n{instruction} 命令名、代码、文件路径、API 名称和引用的工具输出必须保持原文。"
        )
    } else {
        format!(
            "## Response Language\n\n{instruction} Preserve exact command names, code, file paths, API names, and quoted tool output in their original language."
        )
    }
}

fn uses_chinese_prompt(response_language: &str) -> bool {
    matches!(
        response_language.trim().to_ascii_lowercase().as_str(),
        "zh" | "zh-cn" | "chinese" | "中文"
    )
}

fn group_context_prompt(is_group_context: bool, response_language: &str) -> String {
    if is_group_context {
        if uses_chinese_prompt(response_language) {
            "## 群组上下文\n不要在群组或共享 Agent 上下文中泄露用户的私有记忆。".to_string()
        } else {
            "## Group Context\nDo not reveal private user memory in group or shared-agent contexts."
                .to_string()
        }
    } else {
        String::new()
    }
}

fn current_time_prompt(config: &PlatformLlmConfig, response_language: &str) -> String {
    let now_utc = Utc::now();
    let uses_chinese = uses_chinese_prompt(response_language);
    let heading = if uses_chinese {
        "## 当前时间"
    } else {
        "## Current Time"
    };
    let utc_label = if uses_chinese {
        "当前 UTC 时间"
    } else {
        "Current Time UTC"
    };
    let mut lines = vec![
        heading.to_string(),
        format!("{utc_label}: {}", now_utc.format("%Y-%m-%d %H:%M %:z")),
    ];

    if let Some(raw_timezone) = normalized_user_timezone(config.user_timezone.as_deref()) {
        let Some(timezone) = valid_user_timezone(&raw_timezone) else {
            if uses_chinese {
                lines.push(format!(
                    "用户时区: {} (无效 IANA 时区，本地时间不可用)",
                    raw_timezone
                ));
            } else {
                lines.push(format!(
                    "User Timezone: {} (invalid IANA timezone; local time unavailable)",
                    raw_timezone
                ));
            }
            return lines.join("\n");
        };
        let local = now_utc.with_timezone(&timezone);
        if uses_chinese {
            lines.push(format!("用户时区: {}", raw_timezone));
            lines.push(format!(
                "当前本地时间: {}",
                local.format("%Y-%m-%d %H:%M %:z")
            ));
            lines.push(
                "使用当前本地时间解释相对日期和本地时间请求；存储、时间戳和 wire 值仍使用 UTC。"
                    .to_string(),
            );
        } else {
            lines.push(format!("User Timezone: {}", raw_timezone));
            lines.push(format!(
                "Current Local Time: {}",
                local.format("%Y-%m-%d %H:%M %:z")
            ));
            lines.push(
                "Interpret relative dates and local-time requests using Current Local Time; use UTC for storage, timestamps, and wire values."
                    .to_string(),
            );
        }
    }

    lines.join("\n")
}

fn normalized_user_timezone(timezone: Option<&str>) -> Option<String> {
    timezone
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn valid_user_timezone(timezone: &str) -> Option<Tz> {
    timezone.parse::<Tz>().ok()
}

fn media_tool_prompt(
    config: &PlatformLlmConfig,
    attachments: &[IncomingAttachment],
    response_language: &str,
) -> String {
    if !attachments
        .iter()
        .any(|attachment| attachment.kind == AttachmentKind::Image)
    {
        return String::new();
    }
    let has_image_tool = crate::media_tools::has_image_analysis_tool(config);
    if uses_chinese_prompt(response_language) {
        if has_image_tool {
            "## 媒体附件\n图片附件会以沙箱文件路径的形式出现在最新用户消息中。当用户询问图片内容时，先用附件里的 `sandbox_path` 调用 `image_analyze` 工具，再回答。必须原样传入 `sandbox_path`。如果 `image_analyze` 对该路径返回非错误结果，就视为文件已成功读取，不要重复分析同一路径；基于分析结果回答，并在不确定时说明不确定。不要根据文件名或元数据臆测图片内容。"
                .to_string()
        } else {
            "## 媒体附件\n图片附件只会作为沙箱文件引用提供。除非已配置并调用图片分析工具，否则不要声称已经查看图片内容。如果需要视觉检查，请说明当前没有配置图片分析能力。"
                .to_string()
        }
    } else if has_image_tool {
        "## Media Attachments\nImage attachments are provided as sandbox file paths in the latest user message. When the user asks about image contents, call the `image_analyze` tool with the attachment `sandbox_path` before answering. Pass the `sandbox_path` exactly as shown. If `image_analyze` returns a non-error result for that path, treat the file as successfully read and do not retry the same path; answer from the analysis and note uncertainty instead of repeating path checks. Do not infer visual content from filenames or metadata."
            .to_string()
    } else {
        "## Media Attachments\nImage attachments are provided only as sandbox file references. Do not claim to have inspected image contents unless an image analysis tool is available and has been called. If visual inspection is required, say that the image analysis capability is not configured."
            .to_string()
    }
}

fn browser_tool_prompt(response_language: &str) -> String {
    if uses_chinese_prompt(response_language) {
        "## 浏览器工具\n只对绝对 `http://` 或 `https://` URL 的实时网页使用浏览器工具。\
浏览器默认使用移动端模式，和用户应用内的移动 WebView 一样。除非用户要求桌面网页，或者移动页面被阻塞/受限，否则不要切换到桌面模式。\
如果移动端样式页面提示只支持原生客户端/app，可以用 `browser_open` 的 `desktop` 模式重试一次；如果已经是桌面模式或重试后仍被阻塞，请说明站点限制并请用户手动继续。\
对于复杂 JavaScript 页面，先调用 `browser_snapshot`，并使用 `element_id`；决策一个非标准 div/span 不可点击前，检查 `viewport_map`、`action_hint`、`interaction_source`、`clickable_reason`、遮罩层和诊断信息。\
如果 snapshot 返回截图元数据且 `image_analyze` 可用，在 DOM/布局 JSON 含糊时用它理解视觉内容；如果没有配置视觉模型，则依赖 `viewport_map`，不要声称已经查看截图。\
点击后检查 `last_action_effect`；如果它报告无效果，使用返回的 failure_code/candidates，不要重复相同点击。\
绝不要对 `file://` URL、本地文件系统路径、`/workspace/...` 路径、沙箱路径、生成的 HTML 文件或刚创建的文件调用 `browser_open`。\
不要试图通过 shell 启动本地 HTTP server 来绕过这一点。\
对于生成文件或本地文件，把文件路径/附件报告给用户，需要时使用文件工具读取或修改。"
            .to_string()
    } else {
        "## Browser Tool\nUse the browser tools only for live web pages with absolute `http://` or `https://` URLs. \
The browser defaults to mobile mode, like the user's in-app mobile WebView. Do not switch to desktop mode unless the user asks for a desktop page or the mobile page is blocked/limited. \
If a mobile-style page says it only supports the native client/app, you may retry once with `browser_open` mode `desktop`; if desktop mode is already active or still blocked, explain the site restriction and ask the user to continue manually. \
For complex JavaScript pages, call `browser_snapshot` first and use `element_id`; inspect `viewport_map`, `action_hint`, `interaction_source`, `clickable_reason`, overlays, and diagnostics before deciding a non-standard div/span is not clickable. \
If snapshot returns screenshot metadata and `image_analyze` is available, use it for visual understanding when DOM/layout JSON is ambiguous; if no visual model is configured, rely on `viewport_map` and do not claim to have inspected the screenshot. \
After a click, inspect `last_action_effect`; if it reports no effect, use the returned failure_code/candidates instead of repeating the same click. \
Never call `browser_open` for `file://` URLs, local filesystem paths, `/workspace/...` paths, sandbox paths, generated HTML files, or files you just created. \
Do not try to bypass this by starting a local HTTP server from shell for generated HTML. \
For generated or local files, report the file path/attachment to the user and use file tools to read or modify it if needed."
            .to_string()
    }
}

fn shell_tool_prompt(response_language: &str) -> String {
    if uses_chinese_prompt(response_language) {
        "## Linux Shell\n你可以通过 `shell` 工具使用 Linux shell 环境。\
使用 `/workspace` 存放持久文件，使用 `/skills` 访问已安装的 skill 文件。\
当用户要求你检查文件或运行 shell 命令时，使用 shell 工具，不要拒绝。\
shell 命令必须结束；不要启动长时间运行的本地 server、dev server 或 HTTP server 来预览 `/workspace/*.html` 文件。\n\n\
## 文件工具优先级\n读取文件内容时，优先使用 `read_file` 工具；除非用户明确要求 shell，或确实只能用 shell 工作流，否则不要用 `cat`、`sed`、`awk`、`python` 等 shell 命令读取。\n\
创建、编辑或删除文件时，只能使用 `apply_patch` 工具（精确格式见该工具自身的说明）。\
除非用户明确要求使用 shell，否则不要用 shell heredoc 或重定向写文件，例如 `cat > file`、`printf > file`、`tee` 或 `echo ... > file`。"
            .to_string()
    } else {
        "## Linux Shell\nYou have a Linux shell environment available via the `shell` tool. \
Use `/workspace` for persistent files and `/skills` for installed skill files. \
When the user asks you to inspect files or run shell commands, use the shell tool instead of refusing. \
Shell commands must finish; do not start long-running local servers, dev servers, or HTTP servers to preview `/workspace/*.html` files.\n\n\
## File Tool Priority\nFor reading file contents, prefer the `read_file` tool over shell commands such as `cat`, `sed`, `awk`, or `python` unless the user explicitly asks for shell usage or a shell-only workflow is genuinely necessary.\n\
For creating, editing, or deleting files, use the `apply_patch` tool exclusively (see that tool's own description for the exact format). \
Do not use shell heredocs or shell redirection such as `cat > file`, `printf > file`, `tee`, or `echo ... > file` to write files unless the user explicitly asks to use shell."
            .to_string()
    }
}

fn apply_patch_prompt(response_language: &str) -> String {
    if uses_chinese_prompt(response_language) {
        "## apply_patch — 文件编辑\n创建、编辑或删除文件只能使用 `apply_patch` 工具。\
精确的 envelope 格式、硬性规则与示例见该工具自身的说明（tool description）。\
不要用 shell heredoc 或重定向（`cat > file`、`tee`、`echo ... > file`）写文件。"
            .to_string()
    } else {
        "## apply_patch — file editing\nUse the `apply_patch` tool exclusively to create, edit, or delete files. \
The exact envelope format, hard rules, and worked examples live in that tool's own description. \
Do not use shell heredocs or redirection (`cat > file`, `tee`, `echo ... > file`) to write files."
            .to_string()
    }
}
