# Mobile Capabilities

本文件是 [`mobile-capabilities.md`](mobile-capabilities.md) 的中文 companion，说明 Napaxi capability model、scenario pack、platform tools 和新增能力流程。

## Capability model

Mobile capabilities 是由 core 拥有、adapter 承载的编译期 SDK contracts。它们覆盖：

- LLM providers
- built-in tools
- platform tools
- MCP surfaces
- host custom tools
- media features
- background services
- policy gates
- agent engines

V1 capabilities 不是运行时 native plugin。它们来自 core registry，由 platform/host declaration 声明可用，并由 runtime config 或显式 selection 启用。

每个 capability 包含：

| 字段 | 说明 |
| --- | --- |
| `id` | 稳定 SDK ID，例如 `napaxi.llm.openai`。 |
| `kind` | `llm_provider`、`tool`、`platform_tool`、`mcp`、`policy`、`service`、`agent_engine`。 |
| `version` | contract version。 |
| `platforms` | 支持平台或 `all`。 |
| `config_schema` | adapter-neutral JSON config schema。 |
| `risk` | low、medium、high、critical。 |
| `requirements` | host permission、network、approval、workspace、sandbox 等要求。 |
| `default_enabled` | 可用时是否默认 enabled。 |
| `activation` | always、config、host、policy。 |

状态分三层：

- Registered：core 内有定义。
- Available：当前 platform 和 host profile 可承载。
- Enabled：config/selection 允许参与执行。

## Scenario packs

Scenario pack 是由 capability 支撑的 runtime posture。它允许同一个 Napaxi SDK installation 暴露不同场景行为，而不下载任意 native runtime code。

一个 pack 描述：

- 稳定 scene ID，例如 `napaxi.scenario.general`。
- required、recommended、optional capabilities。
- execution planes：core、host bridge、platform provider、remote workspace。
- host 可用于塑造体验的 UI surfaces 和 memory scopes。
- activation posture：manual、intent-routed、host-policy controlled。

内置 anchor packs：

| Scenario | 用途 |
| --- | --- |
| `napaxi.scenario.general` | 通用移动 assistant：chat、memory、files、skills、web fetch/search、host-carried tools。 |
| `napaxi.scenario.mobile_development` | 更高权限的移动开发 workbench：project context、git/build/test tools、approval UI、audit timeline。 |

安装 scenario pack 不会直接启用危险能力；它会返回 activation plan，由 host 决定 capability profile、selection 和用户可见的 policy contract。

## Platform tools

Platform tools 是 host-carried capabilities。Core 拥有 tool names、parameter schemas、risk levels 和 permission requirements。Adapter 或 host 负责真实平台执行。

示例 host profile：

```json
{
  "platform": "ios",
  "supported_capabilities": ["napaxi.platform_tool.*"],
  "disabled_capabilities": ["napaxi.platform_tool.install_apk"]
}
```

常见 platform tools 包括 contacts、calendar、camera、location、audio、notifications、URL handling、device info、clipboard、phone、alarms、APK install 等。

## 重点能力

- **Memory tools**：`napaxi.tool.memory` 覆盖 memory read/write/search 和 session recall。
- **Browser control**：`napaxi.tool.browser` 是 high-risk host-carried tool，adapter 负责 WebView、登录界面、审批 UI 和敏感字段处理。
- **Agent App Actions**：`napaxi.tool.agent_app_action` 连接外部 app/backend action，proposal/result lifecycle 由 core 管理。
- **Channel capabilities**：`napaxi.channel.im` 和 `napaxi.channel.device` 支撑 IM、设备和外设通道。
- **Agent engines**：core-owned runtime loop capabilities，用于不同 agent loop。

## 新增 capability

1. 在 `crates/core/src/capabilities/` 添加 definition 和 mapping。
2. 在 core domain module、feature crate 或现有 tool/provider runtime 中实现可复用行为。
3. 通过 `crates/core/src/api/` 暴露 adapter-facing operations。
4. `packages/api_bridge/` 只添加薄转发。
5. 如果 host app 需要公开 SDK surface，在 Flutter/Android/iOS adapter 中添加 wrapper/model。
6. 同步更新本文档和相关架构说明。

Demo apps 只能消费公开 SDK API，可以展示或验证 capability 行为，但不能拥有可复用 capability contract 或 runtime policy。
