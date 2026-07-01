use anyhow::Result;

use crate::capabilities::LlmProviderRoute;
use crate::types::PlatformLlmConfig;

pub(super) fn resolve_provider_route(config: &PlatformLlmConfig) -> Result<LlmProviderRoute> {
    let platform = config
        .capability_profile
        .platform
        .as_deref()
        .unwrap_or("unknown");
    crate::capabilities::resolve_llm_provider_for_config(
        &config.provider,
        platform,
        &config.capability_profile,
        &config.capability_selection,
    )
    .map_err(anyhow::Error::msg)
}
