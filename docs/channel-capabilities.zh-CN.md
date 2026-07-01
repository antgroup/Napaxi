# Channel Capabilities

本文件是 [`channel-capabilities.md`](channel-capabilities.md) 的中文 companion，说明 Napaxi 如何把 IM、设备和外设通道抽象为 host-carried channel capability。

## 目标

Channel capabilities 让外部消息源进入 Agent runtime，并让 Agent 回复通过宿主或 provider 交付出去。它覆盖：

- IM channel，例如 QQ Bot、WeChat、Feishu、Slack、Telegram 等。
- Device/peripheral channel，例如蓝牙耳机、车机、无人机、传感器或其它设备入口。
- Host-private channel，例如企业内部 IM、应用内消息、IoT 网关。

Core 不拥有真实 transport、登录态、socket、webhook secret 或设备权限。Core 拥有 adapter-neutral contract：channel registration、inbound envelope、route/session、outbound queue、policy 和 history。

## Capability

V1 使用两类 host-carried service capabilities：

- `napaxi.channel.im`
- `napaxi.channel.device`

Host 或 provider 声明自己能承载的 channel。Core 负责稳定数据结构和 routing 规则，adapter/provider 负责平台生命周期、权限、网络、登录和最终消息交付。

## 核心 contract

Channel provider 通常需要：

1. 注册 channel：`register_channel`。
2. 提交 inbound message：`submit_inbound`。
3. 让 core 绑定 agent、session 和 route。
4. Agent 产生 outbound message 后，provider 通过 lease/ack/fail contract 交付。
5. 需要人工介入时，走 ask-human continuation。

常见 API 形态：

- `list_channels`
- `register_channel`
- `unregister_channel`
- `submit_inbound`
- `take_inbound`
- `enqueue_outbound`
- `lease_outbound`
- `ack_outbound`
- `fail_outbound`

## xChannel

xChannel 是更广义的连接层：它不只服务 IM，也服务设备、外设和跨应用入口。Napaxi 通过 xChannel 把 QQ 等 IM 工具、蓝牙耳机、车机、无人机和更多智能设备表面连接到 Agent runtime。

设计原则：

- Provider transport 留在 host/provider 侧。
- Payload normalization、routing、session/history、policy、outbound queue 等共享逻辑由 core 拥有。
- 新 channel 应优先实现 SDK provider contract，而不是修改 core。
- 官方 first-party channel 可以在 core 中增加 sans-IO protocol helper，但真实 transport 仍在 adapter/provider。

## UI 与安全

Host UI 应清楚展示：

- channel 类型、绑定的 agent、连接状态。
- 需要的权限和登录状态。
- inbound/outbound history。
- 高风险 channel action 的用户确认。
- provider failure、retry 和 ask-human 状态。

涉及设备、麦克风、蓝牙、位置、后台、IM 账号或 webhook secret 时，应由宿主 App 明确授权并进行合规处理。

## Flutter SDK

Flutter SDK 暴露 provider host 和 channel-agent bridge，用于 provider 生命周期、agent/session routing 和状态查询。具体 live transport 仍由 provider/host 实现。

当前示例方向包括：

- QQBot IM provider。
- Bluetooth headset audio-device provider。

这些 provider 可作为实现参考，但 demo apps 只能存储凭据、展示配置/状态 UI，并调用 SDK API。
