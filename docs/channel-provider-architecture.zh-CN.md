# Channel Provider 架构

本文件是 [`channel-provider-architecture.md`](channel-provider-architecture.md) 的中文 companion，说明 Channel Provider 与 Agent Provider 的边界，以及第三方如何扩展 channel。

## 分层

Channel/provider ownership 分为几层：

- `crates/core`：可复用 runtime、provider contract、capability/policy gates、sans-IO protocol helpers。
- `packages/api_bridge`：只把 `napaxi_core::api` 暴露给 adapter。
- SDK adapters：Flutter/Android/iOS 负责 host context、生命周期、权限、background glue、provider host wrappers 和 FFI。
- Provider implementations：真实平台 I/O，例如 vendor SDK、webhook、socket、QR login、Bluetooth、TTS/STT、secure storage。
- Demo apps：只做配置、状态展示和 SDK API 调用，不拥有可复用 runtime 逻辑。

## Channel Provider 与 Agent Provider

- **Agent Provider**：外部 app/backend 暴露 action 给 Agent，核心对象是 package、proposal、result。
- **Channel Provider**：外部消息源或设备通道把消息送入 Agent，并把回复交付出去，核心对象是 channel、route、inbound/outbound envelope。

两者都通过 capability 和 policy gate 接入 runtime，但场景不同：Agent Provider 处理“动作执行”，Channel Provider 处理“消息/设备通道”。

## 第三方扩展路径

外部开发者应能在不修改 `crates/` 的情况下新增 channel：

1. 实现 provider manifest。
2. 注册 channel。
3. 提交 normalized inbound messages。
4. lease/deliver outbound messages。
5. 让 core 处理 routing、session、history、ask-human、policy 和 outbound queue。

只有当共享 channel contract 不足时，才应新增 core API。

## Transport 归属

以下能力默认留在 provider/host 侧：

- OS permissions。
- Vendor SDKs。
- Secure storage。
- Background execution。
- Long-lived sockets。
- Heartbeat timers。
- QR/login UI。
- Bluetooth/audio transport。
- Host network policy。

Core 可拥有平台无关的 sans-IO protocol helper，例如 payload shaping、endpoint routing、inbound normalization、signing checks、Markdown/fallback mapping 和 error/retry classification。

## Slash command 与 route

Channel route 和 command namespace 应保持通用，避免把某个 IM 或设备 provider 的细节写进 core。未来 WeChat、Feishu、QQ、Bluetooth、vehicle 或 drone provider 应共享同样的 channel-agent contract。

## 安全要求

- Provider credential 不进入 core。
- 高风险 outbound 或 device action 需要宿主 UI 和 policy gate。
- Channel 绑定 agent/session 时必须可审计。
- 入站消息应携带来源、channel、account、timestamp 和 route metadata。
- 出站消息应支持 lease、ack、fail，避免重复交付和状态丢失。
