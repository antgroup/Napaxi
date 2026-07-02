use std::sync::Arc;

use crate::tool_registry::{ToolDescriptor, ToolRegistry};
use crate::types::PlatformLlmConfig;

pub(super) async fn tool_descriptors(
    config: &PlatformLlmConfig,
    tools: Option<&Arc<ToolRegistry>>,
    extra_tools: Vec<ToolDescriptor>,
) -> Vec<ToolDescriptor> {
    gather_tool_descriptors_for_config(config, tools, extra_tools).await
}

#[allow(dead_code)] // Public descriptor gatherer kept on the tool-loop API surface.
pub async fn gather_tool_descriptors(
    tools: Option<&Arc<ToolRegistry>>,
    extra_tools: Vec<ToolDescriptor>,
) -> Vec<ToolDescriptor> {
    gather_tool_descriptors_for_config(&PlatformLlmConfig::default(), tools, extra_tools).await
}

pub async fn gather_tool_descriptors_for_config(
    config: &PlatformLlmConfig,
    tools: Option<&Arc<ToolRegistry>>,
    extra_tools: Vec<ToolDescriptor>,
) -> Vec<ToolDescriptor> {
    let mut descriptors = match tools {
        Some(tools) => tools.list_tools().await,
        None => Vec::new(),
    };
    for extra in extra_tools {
        if let Some(existing) = descriptors
            .iter()
            .position(|descriptor| descriptor.name == extra.name)
        {
            descriptors[existing] = extra;
        } else {
            descriptors.push(extra);
        }
    }
    let platform = config
        .capability_profile
        .platform
        .as_deref()
        .unwrap_or("unknown");
    descriptors.retain(|descriptor| {
        crate::capabilities::admit_tool_descriptor_for_config(
            &descriptor.name,
            platform,
            &config.capability_profile,
            &config.capability_selection,
        )
        .is_ok()
    });
    descriptors
}

pub async fn has_tool_named(
    tools: Option<&Arc<ToolRegistry>>,
    extra_tools: &[ToolDescriptor],
    name: &str,
) -> bool {
    if extra_tools.iter().any(|tool| tool.name == name) {
        return true;
    }
    match tools {
        Some(tools) => tools
            .list_tools()
            .await
            .iter()
            .any(|tool| tool.name == name),
        None => false,
    }
}
