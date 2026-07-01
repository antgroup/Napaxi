//! Per-turn scene prompt detection and runtime guidance injection.
//!
//! A "scene" is a recognised user-intent pattern (e.g. video processing) that
//! benefits from domain-specific guidance injected into the LLM prompt before
//! the agent processes the turn.  This module:
//!
//! 1. Matches the current message + attachments against known scene patterns.
//! 2. Builds a `<scene_guidance>` XML block that the turn module prepends to
//!    the system prompt when a match is found.
//! 3. Appends any host-application policy the integrator has configured for
//!    the matched scene.
//!
//! Scenes are opt-in: the `ScenePromptConfig.enabled` flag must be `true` and
//! the host must supply the config at engine creation time.  When disabled no
//! guidance is injected and this module is effectively a no-op.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::capabilities::{CapabilitySelection, MOBILE_DEVELOPMENT_SCENARIO_ID};
use crate::channels::IncomingAttachment;

pub const VIDEO_PROCESSING_SCENE_ID: &str = "video_processing";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ScenePromptConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub host_policies: HashMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScenePromptMatch {
    pub scene_id: String,
    pub guidance: String,
}

// Default-language convenience wrapper. Production callers pass the resolved
// response language via `build_scene_guidance_with_language`; this shim is
// exercised by the unit tests below.
#[allow(dead_code)]
pub fn build_scene_guidance(
    config: Option<&ScenePromptConfig>,
    message: &str,
    attachments: &[IncomingAttachment],
) -> Vec<ScenePromptMatch> {
    build_scene_guidance_with_language(config, message, attachments, "en")
}

pub fn build_scene_guidance_with_language(
    config: Option<&ScenePromptConfig>,
    message: &str,
    attachments: &[IncomingAttachment],
    response_language: &str,
) -> Vec<ScenePromptMatch> {
    let Some(config) = config else {
        return Vec::new();
    };
    if !config.enabled {
        return Vec::new();
    }

    let mut matches = Vec::new();
    if matches_video_processing(message, attachments) {
        let is_chinese = uses_chinese_prompt(response_language);
        let mut guidance = video_processing_guidance(is_chinese).to_string();
        if let Some(policy) = config.host_policies.get(VIDEO_PROCESSING_SCENE_ID) {
            let policy = policy.trim();
            if !policy.is_empty() {
                if is_chinese {
                    guidance.push_str("\n\nHost 应用策略：\n");
                } else {
                    guidance.push_str("\n\nHost application policy:\n");
                }
                guidance.push_str(policy);
            }
        }
        matches.push(ScenePromptMatch {
            scene_id: VIDEO_PROCESSING_SCENE_ID.to_string(),
            guidance,
        });
    }

    matches
}

pub fn build_scenario_runtime_guidance(
    selection: &CapabilitySelection,
    response_language: &str,
) -> Vec<ScenePromptMatch> {
    let scenario_id = selection
        .config
        .get("scenario_id")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase();
    if scenario_id != MOBILE_DEVELOPMENT_SCENARIO_ID {
        return Vec::new();
    }

    let configured = selection
        .config
        .get("git_provider_configured")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    let healthy = selection
        .config
        .get("git_provider_healthy")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    vec![ScenePromptMatch {
        scene_id: MOBILE_DEVELOPMENT_SCENARIO_ID.to_string(),
        guidance: mobile_development_guidance(
            uses_chinese_prompt(response_language),
            configured && healthy,
        ),
    }]
}

pub fn format_scene_guidance(matches: &[ScenePromptMatch]) -> String {
    if matches.is_empty() {
        return String::new();
    }

    let mut out = String::from("<scene_guidance>\n");
    for matched in matches {
        out.push_str(&format!("  <scene id=\"{}\">\n", matched.scene_id));
        out.push_str(&indent(&matched.guidance, 4));
        out.push_str("\n  </scene>\n");
    }
    out.push_str("</scene_guidance>");
    out
}

fn mobile_development_guidance(is_chinese: bool, git_ready: bool) -> String {
    if is_chinese {
        let mut lines = vec![
            "当前处于开发工作台场景。针对项目准备、clone、status、diff、分支切换、remote 设置、fetch 等 Git 操作，优先使用宿主暴露的 Git 工具（`git_clone`、`git_status`、`git_diff`、`git_list_branches`、`git_switch_branch`、`git_list_remotes`、`git_set_remote`、`git_fetch`）。",
            "当用户要求开发 App、小游戏、工具、Demo 或 APK，且没有明确要求网页/H5/HTML 时，默认创建 Android 项目：先调用 `android_create_project` 生成 Git 管理的项目，再按需要修改源码，最后调用 `android_build_apk` 产出签名 APK；不要默认写 HTML 页面来代替 Android 应用。",
            "不要为了探测 Git 能力而通过 shell 安装 Git，也不要把专用 Git 工具已经覆盖的 Git 工作退回到 shell。",
        ];
        if git_ready {
            lines.push("Git provider 已配置并可用；需要拉取或检查仓库时直接调用 Git 工具。");
        } else {
            lines.push("Git provider 尚未配置；公开 HTTPS 仓库仍可直接用 Git 工具拉取，私有仓库或需要认证的操作再请用户在场景设置里配置 Git 账号或凭证。");
        }
        lines.join("\n")
    } else {
        let mut lines = vec![
            "The mobile development workbench scenario is active. For project preparation, clone, status, diff, branch switching, remote setup, and fetch tasks, prefer host-provided Git tools (`git_clone`, `git_status`, `git_diff`, `git_list_branches`, `git_switch_branch`, `git_list_remotes`, `git_set_remote`, `git_fetch`).",
            "When the user asks to develop an app, mini-game, tool, demo, or APK and did not explicitly ask for web/H5/HTML, create an Android project by calling `android_create_project`, edit the project source as needed, then call `android_build_apk` for a signed APK. Do not default to an HTML page as a substitute for an Android app.",
            "Do not install Git through shell just to discover Git capability, and do not fall back to shell for Git work that the dedicated Git tools cover.",
        ];
        if git_ready {
            lines.push("The Git provider is configured and ready; use Git tools directly when repository work is requested.");
        } else {
            lines.push("The Git provider is not configured; public HTTPS repositories can still be cloned with Git tools, while private repositories or authenticated operations require Git account credentials in scenario settings.");
        }
        lines.join("\n")
    }
}

fn matches_video_processing(message: &str, attachments: &[IncomingAttachment]) -> bool {
    if attachments.iter().any(is_video_attachment) {
        return true;
    }

    let lower = message.to_lowercase();
    let has_video_term = contains_any(
        &lower,
        &[
            "video",
            "animation",
            "animate",
            "mp4",
            "mov",
            "webm",
            "mkv",
            "avi",
            "ffmpeg",
            "concat",
            "clip",
            "clips",
            "preview",
            "player",
            "视频",
            "动画",
            "剪辑",
            "拼接",
            "合成",
            "片段",
            "转码",
            "预览",
            "播放器",
            "成片",
        ],
    );

    if !has_video_term {
        return false;
    }

    contains_any(
        &lower,
        &[
            "create", "generate", "make", "edit", "compose", "combine", "merge", "concat",
            "stitch", "cut", "export", "render", "制作", "生成", "剪辑", "拼接", "合成", "编排",
            "导出", "处理", "转码",
        ],
    ) || contains_any(&lower, &["60s", "60秒", "5s", "5秒"])
}

fn is_video_attachment(attachment: &IncomingAttachment) -> bool {
    if attachment.mime_type.to_lowercase().starts_with("video/") {
        return true;
    }

    attachment
        .filename
        .as_deref()
        .map(|name| {
            let lower = name.to_lowercase();
            [".mp4", ".mov", ".webm", ".mkv", ".avi"]
                .iter()
                .any(|ext| lower.ends_with(ext))
        })
        .unwrap_or(false)
}

fn contains_any(value: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| value.contains(needle))
}

fn uses_chinese_prompt(response_language: &str) -> bool {
    matches!(
        response_language.trim().to_ascii_lowercase().as_str(),
        "zh" | "zh-cn" | "chinese" | "中文"
    )
}

fn video_processing_guidance(is_chinese: bool) -> &'static str {
    if is_chinese {
        "这是一个视频处理/合成任务。使用 shell 工具创建、编辑、拼接或导出视频时，工作流要优先保证移动 App 预览兼容性。\n\
    - 除非已经验证所有流完全一致，否则不要直接用 stream copy（`-c copy`）拼接异构片段。\n\
    - 拼接前先规范化每个源片段：分辨率、帧率、time base、视频编码、像素格式和音频布局保持一致。\n\
    - 预览输出优先使用 H.264/AVC 视频和 yuv420p 像素格式。避免 yuv444p 和 H.264 High 4:4:4 Predictive。\n\
    - 如果存在音频，规范化为 AAC、44.1 kHz 或 48 kHz、双声道。如果部分片段没有音频，拼接前显式处理。\n\
    - 拼接后执行一次最终兼容性导出，并加入 faststart 元数据，让 MP4 可以在完整下载前开始播放。\n\
    - 将移动端可预览的 MP4 路径作为主要结果返回。"
    } else {
        "This is a video processing/composition task. When using shell tools to create, edit, concatenate, or export video, optimize the workflow for mobile app preview compatibility.\n\
    - Do not directly concat heterogeneous clips with stream copy (`-c copy`) unless you have verified all streams are identical.\n\
    - Normalize every source clip before concatenation: same resolution, frame rate, time base, video codec, pixel format, and audio layout.\n\
    - Prefer H.264/AVC video with yuv420p pixel format for preview outputs. Avoid yuv444p and H.264 High 4:4:4 Predictive.\n\
    - If audio exists, normalize it to AAC, 44.1 kHz or 48 kHz, stereo. If some clips have no audio, handle that explicitly before concat.\n\
    - After concatenation, run one final compatibility export pass with faststart metadata so the MP4 can start playback before the whole file is downloaded.\n\
    - Return the mobile-preview-compatible MP4 path as the primary result."
    }
}

fn indent(text: &str, spaces: usize) -> String {
    let prefix = " ".repeat(spaces);
    text.lines()
        .map(|line| format!("{}{}", prefix, line))
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AttachmentKind, IncomingAttachment};

    fn enabled_config() -> ScenePromptConfig {
        ScenePromptConfig {
            enabled: true,
            host_policies: HashMap::new(),
        }
    }

    fn attachment(mime_type: &str, filename: Option<&str>) -> IncomingAttachment {
        IncomingAttachment {
            id: "att-1".to_string(),
            kind: AttachmentKind::from_mime_type(mime_type),
            mime_type: mime_type.to_string(),
            filename: filename.map(ToString::to_string),
            size_bytes: None,
            source_url: None,
            storage_key: None,
            local_path: None,
            extracted_text: None,
            data: Vec::new(),
            duration_secs: None,
        }
    }

    #[test]
    fn chinese_video_task_matches() {
        let matches = build_scene_guidance(
            Some(&enabled_config()),
            "制作一段60s动画，每个片段不超过5s，然后剪辑到一起",
            &[],
        );
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].scene_id, VIDEO_PROCESSING_SCENE_ID);
    }

    #[test]
    fn english_ffmpeg_concat_task_matches() {
        let matches = build_scene_guidance(
            Some(&enabled_config()),
            "Use ffmpeg concat to merge these mp4 clips and make a previewable video",
            &[],
        );
        assert_eq!(matches.len(), 1);
    }

    #[test]
    fn unrelated_task_does_not_match() {
        let matches = build_scene_guidance(
            Some(&enabled_config()),
            "Explain how hash maps work in Rust",
            &[],
        );
        assert!(matches.is_empty());
    }

    #[test]
    fn video_attachment_matches() {
        let matches = build_scene_guidance(
            Some(&enabled_config()),
            "处理这个文件",
            &[attachment("video/mp4", Some("clip.mp4"))],
        );
        assert_eq!(matches.len(), 1);
    }

    #[test]
    fn video_filename_matches_even_without_video_mime() {
        let matches = build_scene_guidance(
            Some(&enabled_config()),
            "处理这个文件",
            &[attachment("application/octet-stream", Some("clip.mov"))],
        );
        assert_eq!(matches.len(), 1);
    }

    #[test]
    fn host_policy_is_appended() {
        let mut config = enabled_config();
        config.host_policies.insert(
            VIDEO_PROCESSING_SCENE_ID.to_string(),
            "Use Flutter video_player compatible output.".to_string(),
        );

        let matches = build_scene_guidance(Some(&config), "剪辑一个视频", &[]);
        assert!(matches[0].guidance.contains("Host application policy"));
        assert!(matches[0].guidance.contains("Flutter video_player"));
    }

    #[test]
    fn mobile_development_runtime_guidance_prefers_git_tools() {
        let selection = crate::capabilities::CapabilitySelection {
            config: HashMap::from([
                (
                    "scenario_id".to_string(),
                    serde_json::json!(crate::capabilities::MOBILE_DEVELOPMENT_SCENARIO_ID),
                ),
                (
                    "git_provider_configured".to_string(),
                    serde_json::json!(true),
                ),
                ("git_provider_healthy".to_string(), serde_json::json!(true)),
            ]),
            ..crate::capabilities::CapabilitySelection::default()
        };

        let matches = build_scenario_runtime_guidance(&selection, "zh");

        assert_eq!(matches.len(), 1);
        assert!(matches[0].guidance.contains("git_clone"));
        assert!(matches[0].guidance.contains("android_create_project"));
        assert!(matches[0].guidance.contains("android_build_apk"));
        assert!(matches[0].guidance.contains("HTML"));
        assert!(matches[0].guidance.contains("不要"));
    }

    #[test]
    fn disabled_config_does_not_inject() {
        let config = ScenePromptConfig {
            enabled: false,
            host_policies: HashMap::new(),
        };
        let matches = build_scene_guidance(Some(&config), "剪辑一个视频", &[]);
        assert!(matches.is_empty());
    }
}
