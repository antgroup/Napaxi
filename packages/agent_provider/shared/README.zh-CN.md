# Agent Provider Shared

`packages/agent_provider/shared` 存放 Android 和 iOS provider SDK 共享的协议说明、fixtures 或生成输入。

原则：

- Provider package/action/proposal/result 结构应跨平台一致。
- 高风险 action 需要 provider-owned confirmation。
- Trusted install/proposal validation 需要校验签名、过期时间、nonce、idempotency 和 replay。
- 共享协议更新后，应同步 Android、iOS 实现和文档。

相关文档：

- [`../../../docs/agent-provider-protocol.zh-CN.md`](../../../docs/agent-provider-protocol.zh-CN.md)
- [`../../../docs/agent-app-actions.zh-CN.md`](../../../docs/agent-app-actions.zh-CN.md)
