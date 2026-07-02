//! Media capability tools backed by configured LLM capability slots.

use std::path::{Path, PathBuf};
use std::time::Duration;

use base64::Engine;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::storage::FileBridge;
use crate::tool_registry::ToolDescriptor;
use crate::types::{ChatEvent, PlatformLlmCapabilityConfig, PlatformLlmConfig};

pub const IMAGE_ANALYZE_TOOL_NAME: &str = "image_analyze";
pub const IMAGE_GENERATE_TOOL_NAME: &str = "image_generate";

const IMAGE_ANALYSIS_CAPABILITY: &str = "imageAnalysis";
const IMAGE_GENERATION_CAPABILITY: &str = "imageGeneration";

pub fn descriptors(config: &PlatformLlmConfig) -> Vec<ToolDescriptor> {
    let mut tools = Vec::new();
    if image_analysis_config(config).is_some() {
        tools.push(image_analyze_descriptor());
    }
    if image_generation_config(config).is_some() {
        tools.push(image_generate_descriptor());
    }
    tools
}

pub fn is_media_tool(name: &str) -> bool {
    matches!(name, IMAGE_ANALYZE_TOOL_NAME | IMAGE_GENERATE_TOOL_NAME)
}

pub fn has_image_analysis_tool(config: &PlatformLlmConfig) -> bool {
    image_analysis_config(config).is_some()
}

pub async fn execute(
    files_dir: &str,
    workspace_files_dir: &str,
    config: &PlatformLlmConfig,
    tool_name: &str,
    params: Value,
) -> Result<(String, Vec<ChatEvent>), String> {
    match tool_name {
        IMAGE_ANALYZE_TOOL_NAME => {
            let output =
                execute_image_analyze(files_dir, workspace_files_dir, config, params).await?;
            Ok((output, Vec::new()))
        }
        IMAGE_GENERATE_TOOL_NAME => {
            execute_image_generate(files_dir, workspace_files_dir, config, params).await
        }
        _ => Err(format!("unsupported media tool: {tool_name}")),
    }
}

fn image_analyze_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: IMAGE_ANALYZE_TOOL_NAME.to_string(),
        description: "Analyze an image with the configured image analysis provider. Use this whenever the user asks about an image attachment. Pass the attachment sandbox_path exactly as shown in the message attachments.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "image_path": {
                    "type": "string",
                    "description": "Sandbox path to the image, usually an attachment sandbox_path such as /workspace/attachments/thread/image-1.png."
                },
                "question": {
                    "type": "string",
                    "description": "The specific question to answer about the image."
                }
            },
            "required": ["image_path"]
        }),
        effect: crate::tool_registry::ToolEffect::Read,
    }
}

fn image_generate_descriptor() -> ToolDescriptor {
    ToolDescriptor {
        name: IMAGE_GENERATE_TOOL_NAME.to_string(),
        description: "Generate an image with the configured image generation provider. Use this when the user asks to create, draw, render, or generate a new image.".to_string(),
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "prompt": {
                    "type": "string",
                    "description": "Image generation prompt."
                },
                "size": {
                    "type": "string",
                    "description": "Requested image size, such as 1024x1024.",
                    "default": "1024x1024"
                }
            },
            "required": ["prompt"]
        }),
        effect: crate::tool_registry::ToolEffect::Write,
    }
}

async fn execute_image_analyze(
    files_dir: &str,
    workspace_files_dir: &str,
    config: &PlatformLlmConfig,
    params: Value,
) -> Result<String, String> {
    let image_config = image_analysis_config(config)
        .ok_or_else(|| "image analysis capability is not configured".to_string())?;
    let image_path = required_string(&params, "image_path")?;
    let question = image_analysis_question(
        optional_string(&params, "question")
            .unwrap_or_else(|| "Describe this image in detail.".to_string())
            .as_str(),
    );
    let bytes = read_workspace_file(files_dir, workspace_files_dir, &image_path).await?;
    if bytes.is_empty() {
        return Err("image file is empty".to_string());
    }

    let media_type = media_type_from_path(&image_path);
    let metadata = image_analysis_metadata(&image_path, media_type, &bytes);
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    let image_url = image_analysis_url_value(&image_config, media_type, &b64);
    let messages = vec![serde_json::json!({
        "role": "user",
        "content": [
            {
                "type": "text",
                "text": question
            },
            {
                "type": "image_url",
                "image_url": {
                    "url": image_url,
                    "detail": "auto"
                }
            }
        ]
    })];
    let turn = crate::llm::complete_turn_with_raw_messages(&image_config, &messages, &[])
        .await
        .map_err(|error| format!("image analysis request failed: {error}"))?;
    if turn.content.trim().is_empty() {
        Ok(format!("{metadata}\n\nAnalysis:\nNo analysis returned."))
    } else {
        Ok(format!("{metadata}\n\nAnalysis:\n{}", turn.content.trim()))
    }
}

fn image_analysis_question(question: &str) -> String {
    format!(
        "Analyze the attached image only. Do not infer from filenames, prior messages, or generic examples. \
If it is a screenshot, identify the app/page and transcribe the visible UI text that supports your answer. \
If you are uncertain, say what is uncertain instead of inventing objects or brands.\n\nUser question: {}",
        question.trim()
    )
}

fn image_analysis_url_value(
    config: &PlatformLlmConfig,
    media_type: &str,
    base64_data: &str,
) -> String {
    match image_base64_url_format(config) {
        ImageBase64UrlFormat::Raw => base64_data.to_string(),
        ImageBase64UrlFormat::DataUrl => format!("data:{media_type};base64,{base64_data}"),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ImageBase64UrlFormat {
    DataUrl,
    Raw,
}

fn image_base64_url_format(config: &PlatformLlmConfig) -> ImageBase64UrlFormat {
    match config
        .image_base64_url_format
        .as_deref()
        .map(str::trim)
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("raw") | Some("base64") => return ImageBase64UrlFormat::Raw,
        Some("data_url") | Some("data-url") | Some("dataurl") => {
            return ImageBase64UrlFormat::DataUrl;
        }
        _ => {}
    }

    provider_default_image_base64_url_format(config)
}

fn provider_default_image_base64_url_format(config: &PlatformLlmConfig) -> ImageBase64UrlFormat {
    let provider = config.provider.trim();
    if provider.eq_ignore_ascii_case("glm")
        || provider.eq_ignore_ascii_case("zai")
        || provider.eq_ignore_ascii_case("zhipu")
        || provider.eq_ignore_ascii_case("bigmodel")
    {
        return ImageBase64UrlFormat::Raw;
    }

    let Some(base_url) = config.base_url.as_deref() else {
        return ImageBase64UrlFormat::DataUrl;
    };
    let base_url = base_url.to_ascii_lowercase();
    if base_url.contains("bigmodel.cn") || base_url.contains("z.ai") {
        ImageBase64UrlFormat::Raw
    } else {
        ImageBase64UrlFormat::DataUrl
    }
}

fn image_analysis_metadata(image_path: &str, media_type: &str, bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let hash = format!("{:x}", hasher.finalize());
    let dimensions = image_dimensions(bytes, media_type)
        .map(|(width, height)| format!("{width}x{height}"))
        .unwrap_or_else(|| "unknown".to_string());
    format!(
        "Image analyzed: path={image_path}; media_type={media_type}; bytes={}; sha256={}; dimensions={dimensions}",
        bytes.len(),
        &hash[..16]
    )
}

async fn execute_image_generate(
    files_dir: &str,
    workspace_files_dir: &str,
    config: &PlatformLlmConfig,
    params: Value,
) -> Result<(String, Vec<ChatEvent>), String> {
    let image_config = image_generation_config(config)
        .ok_or_else(|| "image generation capability is not configured".to_string())?;
    // image_analyze reaches its provider through `complete_turn_with_raw_messages`,
    // which runs `admit_provider` via the LLM dispatch path. image_generate issues
    // a raw POST below, so it must run the same provider admission gate explicitly
    // — otherwise a host's provider-level deny policy is silently bypassed.
    crate::capabilities::admit_provider(&image_config.provider)?;
    let prompt = required_string(&params, "prompt")?;
    let size = optional_string(&params, "size").unwrap_or_else(|| "1024x1024".to_string());
    let body = serde_json::json!({
        "model": &image_config.model,
        "prompt": prompt,
        "size": size,
        "n": 1,
        "response_format": "b64_json"
    });
    let response = llm_client(&image_config)?
        .post(image_generations_url(&image_config))
        .bearer_auth(image_config.api_key.trim())
        .headers(extra_headers(image_config.extra_headers.as_deref())?)
        .json(&body)
        .send()
        .await
        .map_err(|error| format!("image generation request failed: {error}"))?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "image generation provider returned {status}: {body}"
        ));
    }
    let json: Value = response
        .json()
        .await
        .map_err(|error| format!("failed to parse image generation response: {error}"))?;
    let Some(data_url) = generated_image_data_url(&json) else {
        return Err("image generation response did not include image data".to_string());
    };
    let sandbox_path = if data_url.starts_with("data:") {
        save_generated_image(files_dir, workspace_files_dir, &data_url).await?
    } else {
        None
    };
    let output = sandbox_path.clone().unwrap_or_else(|| data_url.clone());
    Ok((
        output,
        vec![ChatEvent::ImageGenerated {
            data_url,
            path: sandbox_path,
        }],
    ))
}

fn image_analysis_config(config: &PlatformLlmConfig) -> Option<PlatformLlmConfig> {
    capability_config(config, IMAGE_ANALYSIS_CAPABILITY).or_else(|| {
        config
            .image_analysis_model
            .as_deref()
            .map(str::trim)
            .filter(|model| !model.is_empty())
            .map(|model| config_with_model(config, model))
    })
}

fn image_generation_config(config: &PlatformLlmConfig) -> Option<PlatformLlmConfig> {
    capability_config(config, IMAGE_GENERATION_CAPABILITY).or_else(|| {
        config
            .image_model
            .as_deref()
            .map(str::trim)
            .filter(|model| !model.is_empty())
            .map(|model| config_with_model(config, model))
    })
}

fn capability_config(config: &PlatformLlmConfig, name: &str) -> Option<PlatformLlmConfig> {
    let capability = config.capability_configs.as_ref()?.get(name)?;
    capability_to_llm_config(config, capability)
}

fn capability_to_llm_config(
    base: &PlatformLlmConfig,
    capability: &PlatformLlmCapabilityConfig,
) -> Option<PlatformLlmConfig> {
    let provider = capability.provider.trim();
    let api_key = capability.api_key.trim();
    let model = capability.model.trim();
    if provider.is_empty() || api_key.is_empty() || model.is_empty() {
        return None;
    }
    Some(PlatformLlmConfig {
        provider: provider.to_string(),
        api_key: api_key.to_string(),
        base_url: capability
            .base_url
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string),
        model: model.to_string(),
        system_prompt: base.system_prompt.clone(),
        response_language: base.response_language.clone(),
        max_tokens: capability.max_tokens.unwrap_or(base.max_tokens),
        max_tool_iterations: 0,
        extra_headers: capability
            .extra_headers
            .clone()
            .or_else(|| base.extra_headers.clone()),
        allowed_models: None,
        image_model: None,
        image_analysis_model: None,
        image_base64_url_format: capability
            .image_base64_url_format
            .clone()
            .or_else(|| base.image_base64_url_format.clone()),
        capability_configs: None,
        scene_prompt_config: None,
        ..PlatformLlmConfig::default()
    })
}

fn config_with_model(base: &PlatformLlmConfig, model: &str) -> PlatformLlmConfig {
    let mut config = base.clone();
    config.model = model.to_string();
    config.allowed_models = None;
    config.image_model = None;
    config.image_analysis_model = None;
    config.capability_configs = None;
    config.scene_prompt_config = None;
    config
}

async fn read_workspace_file(
    files_dir: &str,
    workspace_files_dir: &str,
    sandbox_path: &str,
) -> Result<Vec<u8>, String> {
    let bridge = FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let path = resolve_workspace_file(&bridge, sandbox_path).await?;
    tokio::fs::read(&path)
        .await
        .map_err(|error| format!("failed to read image file: {error}"))
}

async fn resolve_workspace_file(
    bridge: &FileBridge,
    sandbox_path: &str,
) -> Result<PathBuf, String> {
    let normalized = sandbox_path.trim();
    if !(normalized == "/workspace" || normalized.starts_with("/workspace/")) {
        return Err("image_path must be a /workspace sandbox path".to_string());
    }
    let real = bridge
        .sandbox_to_real(normalized)
        .ok_or_else(|| "failed to resolve image_path".to_string())?;
    let canonical = tokio::fs::canonicalize(&real)
        .await
        .map_err(|error| format!("failed to access image_path: {error}"))?;
    let base = canonical_base(bridge.workspace_dir()).await?;
    if !canonical.starts_with(&base) {
        return Err("image_path escapes the workspace sandbox".to_string());
    }
    let metadata = tokio::fs::metadata(&canonical)
        .await
        .map_err(|error| format!("failed to inspect image_path: {error}"))?;
    if !metadata.is_file() {
        return Err("image_path must point to a file".to_string());
    }
    Ok(canonical)
}

async fn canonical_base(path: &Path) -> Result<PathBuf, String> {
    tokio::fs::create_dir_all(path)
        .await
        .map_err(|error| format!("failed to prepare workspace: {error}"))?;
    tokio::fs::canonicalize(path)
        .await
        .map_err(|error| format!("failed to resolve workspace: {error}"))
}

async fn save_generated_image(
    files_dir: &str,
    workspace_files_dir: &str,
    data_url: &str,
) -> Result<Option<String>, String> {
    let Some((mime_type, data)) = data_url.split_once(";base64,") else {
        return Ok(None);
    };
    let mime_type = mime_type.trim_start_matches("data:");
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data)
        .map_err(|error| format!("failed to decode generated image: {error}"))?;
    let bridge = FileBridge::new_with_workspace_files_dir(files_dir, workspace_files_dir);
    let dir = bridge.workspace_dir().join("generated");
    tokio::fs::create_dir_all(&dir)
        .await
        .map_err(|error| format!("failed to prepare generated image directory: {error}"))?;
    let extension = image_extension(mime_type);
    let filename = format!("image-{}.{}", uuid::Uuid::new_v4(), extension);
    let path = dir.join(filename);
    tokio::fs::write(&path, bytes)
        .await
        .map_err(|error| format!("failed to save generated image: {error}"))?;
    Ok(bridge.real_to_sandbox(&path.display().to_string()))
}

fn generated_image_data_url(json: &Value) -> Option<String> {
    let first = json.get("data")?.as_array()?.first()?;
    if let Some(b64) = first.get("b64_json").and_then(Value::as_str) {
        return Some(format!("data:image/png;base64,{b64}"));
    }
    first.get("url").and_then(Value::as_str).map(str::to_string)
}

fn llm_client(config: &PlatformLlmConfig) -> Result<reqwest::Client, String> {
    if config.api_key.trim().is_empty() {
        return Err("LLM API key is required".to_string());
    }
    if config.model.trim().is_empty() {
        return Err("LLM model is required".to_string());
    }
    reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .map_err(|error| format!("failed to build HTTP client: {error}"))
}

fn image_generations_url(config: &PlatformLlmConfig) -> String {
    let base = config
        .base_url
        .as_deref()
        .filter(|url| !url.trim().is_empty())
        .unwrap_or("https://api.openai.com/v1")
        .trim_end_matches('/');
    if base.ends_with("/images/generations") {
        base.to_string()
    } else {
        format!("{base}/images/generations")
    }
}

fn extra_headers(raw: Option<&str>) -> Result<HeaderMap, String> {
    let mut headers = HeaderMap::new();
    let Some(raw) = raw else {
        return Ok(headers);
    };
    for part in raw
        .split(',')
        .map(str::trim)
        .filter(|part| !part.is_empty())
    {
        let Some((name, value)) = part.split_once(':') else {
            continue;
        };
        let name = HeaderName::from_bytes(name.trim().as_bytes())
            .map_err(|error| format!("invalid extra header name: {error}"))?;
        let value = HeaderValue::from_str(value.trim())
            .map_err(|error| format!("invalid extra header value: {error}"))?;
        headers.insert(name, value);
    }
    Ok(headers)
}

fn required_string(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| format!("missing required parameter: {key}"))
}

fn optional_string(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
}

fn media_type_from_path(path: &str) -> &'static str {
    let lower = path.to_ascii_lowercase();
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".webp") {
        "image/webp"
    } else if lower.ends_with(".gif") {
        "image/gif"
    } else if lower.ends_with(".bmp") {
        "image/bmp"
    } else {
        "image/png"
    }
}

fn image_dimensions(bytes: &[u8], media_type: &str) -> Option<(u32, u32)> {
    match media_type {
        "image/png" => png_dimensions(bytes),
        "image/jpeg" => jpeg_dimensions(bytes),
        "image/webp" => webp_dimensions(bytes),
        _ => None,
    }
}

fn png_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
    if bytes.len() < 24 || &bytes[..8] != PNG_SIGNATURE {
        return None;
    }
    Some((
        u32::from_be_bytes(bytes[16..20].try_into().ok()?),
        u32::from_be_bytes(bytes[20..24].try_into().ok()?),
    ))
}

fn jpeg_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 4 || bytes[0] != 0xff || bytes[1] != 0xd8 {
        return None;
    }
    let mut index = 2usize;
    while index + 3 < bytes.len() {
        while index < bytes.len() && bytes[index] == 0xff {
            index += 1;
        }
        if index >= bytes.len() {
            return None;
        }
        let marker = bytes[index];
        index += 1;
        if marker == 0xd9 || marker == 0xda {
            return None;
        }
        if index + 1 >= bytes.len() {
            return None;
        }
        let segment_len = u16::from_be_bytes([bytes[index], bytes[index + 1]]) as usize;
        if segment_len < 2 || index + segment_len > bytes.len() {
            return None;
        }
        if matches!(
            marker,
            0xc0 | 0xc1
                | 0xc2
                | 0xc3
                | 0xc5
                | 0xc6
                | 0xc7
                | 0xc9
                | 0xca
                | 0xcb
                | 0xcd
                | 0xce
                | 0xcf
        ) {
            if segment_len < 7 {
                return None;
            }
            let height = u16::from_be_bytes([bytes[index + 3], bytes[index + 4]]) as u32;
            let width = u16::from_be_bytes([bytes[index + 5], bytes[index + 6]]) as u32;
            return Some((width, height));
        }
        index += segment_len;
    }
    None
}

fn webp_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 30 || &bytes[..4] != b"RIFF" || &bytes[8..12] != b"WEBP" {
        return None;
    }
    match &bytes[12..16] {
        b"VP8X" if bytes.len() >= 30 => {
            let width = 1 + u32::from_le_bytes([bytes[24], bytes[25], bytes[26], 0]);
            let height = 1 + u32::from_le_bytes([bytes[27], bytes[28], bytes[29], 0]);
            Some((width, height))
        }
        b"VP8 " if bytes.len() >= 30 => {
            if bytes[23] != 0x9d || bytes[24] != 0x01 || bytes[25] != 0x2a {
                return None;
            }
            let width = u16::from_le_bytes([bytes[26], bytes[27]]) as u32 & 0x3fff;
            let height = u16::from_le_bytes([bytes[28], bytes[29]]) as u32 & 0x3fff;
            Some((width, height))
        }
        b"VP8L" if bytes.len() >= 25 => {
            if bytes[20] != 0x2f {
                return None;
            }
            let bits = u32::from_le_bytes([bytes[21], bytes[22], bytes[23], bytes[24]]);
            let width = (bits & 0x3fff) + 1;
            let height = ((bits >> 14) & 0x3fff) + 1;
            Some((width, height))
        }
        _ => None,
    }
}

fn image_extension(mime_type: &str) -> &'static str {
    match mime_type {
        "image/jpeg" => "jpg",
        "image/webp" => "webp",
        "image/gif" => "gif",
        "image/bmp" => "bmp",
        _ => "png",
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    fn config() -> PlatformLlmConfig {
        PlatformLlmConfig {
            provider: "openai".to_string(),
            api_key: "chat-key".to_string(),
            base_url: None,
            model: "chat-model".to_string(),
            system_prompt: String::new(),
            max_tokens: 1000,
            max_tool_iterations: 0,
            extra_headers: None,
            allowed_models: None,
            image_model: None,
            image_analysis_model: None,
            capability_configs: None,
            scene_prompt_config: None,
            ..PlatformLlmConfig::default()
        }
    }

    #[test]
    fn descriptors_follow_configured_capability_slots() {
        let mut config = config();
        config.capability_configs = Some(HashMap::from([
            (
                "imageAnalysis".to_string(),
                PlatformLlmCapabilityConfig {
                    provider: "openai_compatible".to_string(),
                    api_key: "vision-key".to_string(),
                    base_url: Some("https://vision.example/v1".to_string()),
                    model: "vision-model".to_string(),
                    max_tokens: Some(2048),
                    extra_headers: None,
                    image_base64_url_format: None,
                },
            ),
            (
                "imageGeneration".to_string(),
                PlatformLlmCapabilityConfig {
                    provider: "openai_compatible".to_string(),
                    api_key: "image-key".to_string(),
                    base_url: Some("https://image.example/v1".to_string()),
                    model: "image-model".to_string(),
                    max_tokens: None,
                    extra_headers: None,
                    image_base64_url_format: None,
                },
            ),
        ]));

        let names: Vec<_> = descriptors(&config)
            .into_iter()
            .map(|tool| tool.name)
            .collect();

        assert_eq!(names, vec!["image_analyze", "image_generate"]);
    }

    #[test]
    fn capability_slot_preserves_provider_config() {
        let mut config = config();
        config.capability_configs = Some(HashMap::from([(
            "imageAnalysis".to_string(),
            PlatformLlmCapabilityConfig {
                provider: "openai_compatible".to_string(),
                api_key: "vision-key".to_string(),
                base_url: Some("https://vision.example/v1".to_string()),
                model: "vision-model".to_string(),
                max_tokens: Some(2048),
                extra_headers: Some("X-Test:yes".to_string()),
                image_base64_url_format: None,
            },
        )]));

        let capability = image_analysis_config(&config).unwrap();

        assert_eq!(capability.provider, "openai_compatible");
        assert_eq!(capability.api_key, "vision-key");
        assert_eq!(
            capability.base_url.as_deref(),
            Some("https://vision.example/v1")
        );
        assert_eq!(capability.model, "vision-model");
        assert_eq!(capability.max_tokens, 2048);
        assert_eq!(capability.extra_headers.as_deref(), Some("X-Test:yes"));
    }

    #[test]
    fn image_analysis_question_constrains_visual_model() {
        let question = image_analysis_question("What is this?");

        assert!(question.contains("Analyze the attached image only"));
        assert!(question.contains("Do not infer from filenames"));
        assert!(question.contains("User question: What is this?"));
    }

    #[test]
    fn image_analysis_url_uses_glm_base64_format() {
        let mut config = config();
        config.provider = "glm".to_string();

        assert_eq!(
            image_analysis_url_value(&config, "image/png", "abc123"),
            "abc123"
        );
    }

    #[test]
    fn image_analysis_url_keeps_data_url_for_openai_compatible() {
        let mut config = config();
        config.provider = "openai_compatible".to_string();

        assert_eq!(
            image_analysis_url_value(&config, "image/png", "abc123"),
            "data:image/png;base64,abc123"
        );
    }

    #[test]
    fn image_analysis_url_format_can_be_overridden() {
        let mut config = config();
        config.provider = "openai_compatible".to_string();
        config.image_base64_url_format = Some("raw".to_string());

        assert_eq!(
            image_analysis_url_value(&config, "image/png", "abc123"),
            "abc123"
        );
    }

    #[test]
    fn image_analysis_metadata_reports_png_dimensions_and_hash_prefix() {
        let mut png = Vec::from(b"\x89PNG\r\n\x1a\n".as_slice());
        png.extend_from_slice(&13u32.to_be_bytes());
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&1200u32.to_be_bytes());
        png.extend_from_slice(&2670u32.to_be_bytes());

        let metadata = image_analysis_metadata("/workspace/a.png", "image/png", &png);

        assert!(metadata.contains("path=/workspace/a.png"));
        assert!(metadata.contains("media_type=image/png"));
        assert!(metadata.contains("dimensions=1200x2670"));
        assert!(metadata.contains("sha256="));
    }
}
