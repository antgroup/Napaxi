# 安全策略

Napaxi 是 mobile-native Agent SDK。漏洞可能影响终端用户设备，因此我们采用协调披露流程。英文原文见 [`SECURITY.md`](SECURITY.md)。

## 支持版本

Napaxi 目前处于 pre-1.0。安全修复优先面向当前默认开发分支和最近发布 tag。

| 版本 | 支持状态 |
| --- | --- |
| 默认开发分支 HEAD | 支持 |
| 最近 release tag | 支持 |
| 更早 tag | 尽力而为 |

## 报告漏洞

请不要在公开 GitHub issue、PR、discussion 或聊天中披露安全漏洞。

请私下发送邮件到 **`wenyu.mwt@antgroup.com`**，并尽量包含：

- 问题描述和你观察到的影响。
- 复现步骤，最好有最小样例或 proof of concept。
- 受影响组件，例如 `crates/core/...`、`packages/flutter/...`、`packages/agent_provider/...`。
- 你测试的 commit hash 或 release tag。
- 你对严重程度的判断和可能的缓解建议。

如果需要加密通道，请在第一封邮件中说明，我们会提供 PGP key fingerprint。

## 响应流程

我们会尽力：

- 在 **3 个工作日** 内确认收到报告。
- 在 **10 个工作日** 内给出初步评估。
- 在问题公开前交付修复或缓解方案，并与你协调披露时间。

如果无法复现，我们会继续沟通，而不是静默关闭。

## 范围

范围内：

- `crates/core/` 下的 Rust runtime kernel、API boundary、capability registry、tool admission、MCP、LLM provider routing。
- `packages/api_bridge/` 下的 Flutter Rust Bridge 层。
- `packages/flutter/` 下的 Flutter adapter、platform tools、browser surface、background services。
- `packages/android/` 和 `packages/ios/` 下的 native SDK adapter。
- `packages/agent_provider/` 下的 provider-side SDK、安装/动作协议、签名校验和 trust store。
- `tools/scripts/` 中会影响 release artifact 的构建和打包脚本。
- `vendor/` 中 Napaxi patch 引入的问题。

范围外：

- 未修改第三方依赖自身的漏洞，请优先报告给上游。
- `examples/` demo app 的生产配置问题。demo 用于验证 SDK，不是生产应用。
- 宿主 App 自行错误配置，例如授予了 SDK 明确提示为高风险的 capability。

## 集成方加固建议

- Capability profile 只声明宿主能安全承载的能力。
- 高风险工具、平台工具、后台任务和外部 action 应要求用户确认或宿主策略审核。
- Provider/action 集成必须校验来源、签名、过期时间、nonce 和重放。
- 任何文件、浏览器、shell、设备、channel 能力都应有清晰的用户可见授权。
- 不要把用户密钥、模型凭据或 provider secret 写入 demo-only 存储路径。

## 致谢

如果你希望在修复发布后获得公开致谢，请在报告中说明展示名称和链接。也可以选择匿名。
