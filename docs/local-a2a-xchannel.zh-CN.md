# Local A2A over xChannel

本文件是 [`local-a2a-xchannel.md`](local-a2a-xchannel.md) 的中文 companion，说明本地 A2A 如何复用 xChannel 层。

## 目标

Local A2A 让附近设备或本地 peer 可以通过 xChannel 与 Napaxi Agent 建立任务协作。它面向：

- 端内或近场多 Agent 协作。
- 跨设备任务传递。
- 本地 pairing、invite、task handoff。
- 后续扩展到设备和外设 channel。

## 基本流程

1. Host 创建 local A2A capability profile。
2. 设备或 peer 通过 QR、deeplink、近场连接或 host-defined transport 建立 pairing。
3. xChannel 提交 inbound task/message。
4. Core 解析 route，绑定 agent/session。
5. Agent 执行任务并生成 outbound reply。
6. Provider/host 通过 xChannel 交付结果。

## 边界

- Pairing UI、transport、secret storage 和 OS permission 属于 host/provider。
- Route、session、history、policy、task state 属于 core runtime。
- Demo 可展示流程，但不可拥有可复用 pairing/runtime 逻辑。

## 安全建议

- Pairing secret 应加密存储，避免 plaintext 持久化。
- inbound task 应包含来源、过期时间和 replay 防护。
- 高风险 task 应走用户确认或 host policy。
- 断连、重试和重复消息需要可审计状态。
