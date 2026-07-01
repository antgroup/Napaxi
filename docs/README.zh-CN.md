# Napaxi 文档

这个目录是 Napaxi 的公开文档入口。英文文档通常是最详细的规范；中文文档用于帮助中文读者快速理解和接入。

新读者可以先看 [`overview.zh-CN.md`](overview.zh-CN.md)，SDK 接入看 [`sdk-integration.zh-CN.md`](sdk-integration.zh-CN.md)，贡献流程看 [`../CONTRIBUTING.zh-CN.md`](../CONTRIBUTING.zh-CN.md)，Contributor License Agreement 要求看 [`../CLA.zh-CN.md`](../CLA.zh-CN.md)，安全披露看 [`../SECURITY.zh-CN.md`](../SECURITY.zh-CN.md)。

## 中文文档

| 文档 | 用途 |
| --- | --- |
| [`overview.zh-CN.md`](overview.zh-CN.md) | 项目概览。 |
| [`sdk-integration.zh-CN.md`](sdk-integration.zh-CN.md) | SDK 构建、集成、验证和原生产物说明。 |
| [`sdk-adapter-parity.zh-CN.md`](sdk-adapter-parity.zh-CN.md) | Flutter、Android、iOS adapter 一致性规则。 |
| [`mobile-capabilities.zh-CN.md`](mobile-capabilities.zh-CN.md) | Capability registry、状态、场景包和新增能力规则。 |
| [`api-contract.zh-CN.md`](api-contract.zh-CN.md) | Core API contract 与错误模型。 |
| [`capability-admission.zh-CN.md`](capability-admission.zh-CN.md) | Capability admission gate 和 policy hook。 |
| [`agent-app-actions.zh-CN.md`](agent-app-actions.zh-CN.md) | Host-side Agent App Action 流程。 |
| [`agent-provider-protocol.zh-CN.md`](agent-provider-protocol.zh-CN.md) | Provider-side SDK 协议。 |
| [`channel-capabilities.zh-CN.md`](channel-capabilities.zh-CN.md) | IM/device channel capability contract。 |
| [`channel-provider-architecture.zh-CN.md`](channel-provider-architecture.zh-CN.md) | Channel Provider 架构和扩展边界。 |
| [`local-a2a-xchannel.zh-CN.md`](local-a2a-xchannel.zh-CN.md) | Local A2A over xChannel 流程。 |
| [`demo-guide.zh-CN.md`](demo-guide.zh-CN.md) | demo 和 examples 说明。 |
| [`naming-migration.zh-CN.md`](naming-migration.zh-CN.md) | legacy naming 迁移计划。 |

## 保留英文的文档

以下文档偏内部实现、架构深潜或 AI coding 规则，暂不维护中文 companion：

- [`architecture.md`](architecture.md)
- [`ai-coding-guidelines.md`](ai-coding-guidelines.md)
- `module-*.md`
- [`../AGENTS.md`](../AGENTS.md)

需要修改 SDK 边界、core 模块或长期架构时，请以英文详细文档和代码为准。
