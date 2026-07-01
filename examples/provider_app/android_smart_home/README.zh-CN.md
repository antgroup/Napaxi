# Smart Home Provider Demo

这是一个虚拟 smart-home dashboard，展示 Android app 与 Napaxi 的两种集成方式。大多数应用只需要其中一种；本 demo 把两种方式放在一起，帮助理解边界。

## 两种集成模式

| | Local embedded SDK | Provider protocol |
| --- | --- | --- |
| 依赖 | `com.napaxi:android` (`NapaxiEngine`) | `agent.provider:android_agent_provider` |
| Agent 运行位置 | 本 app 进程内 | 外部 Napaxi host app |
| 入口 | `SmartHomeAgentRuntime` | `SmartHomePackage` + install/action Activity |
| 作用 | 配置 LLM、注册 light tools、本地运行 chat loop | 向 host 暴露 app-owned actions |
| 触发 | app 内 assistant panel | host install/handoff intents 或 background triggers |

## Local embedded SDK

`SmartHomeAgentRuntime` 创建 `NapaxiEngine`，注册 light tools，并收集 `sendToSessionFlow()` 的结果。

没有 keyword routing。每条用户消息都进入 local engine。当请求超出本地 light control 能力时，模型可调用 `request_napaxi_collaboration`，UI 再展示 **交给 Napaxi** 按钮。

## Provider protocol

外部 Napaxi host 通过 `AgentInstallActivity` 连接后，可以把 `ActionProposal` 发给 `AgentActionActivity`。Provider 负责 trusted proposal validation、用户确认、业务执行和返回 signed `ActionResult`。

完整协议见 [`../../../docs/agent-provider-protocol.zh-CN.md`](../../../docs/agent-provider-protocol.zh-CN.md)。

## Demo-only shortcuts

- Mijia notification bridge 通过中文关键词解析通知文本，只是 demo convenience。
- API key 为简化存储在 `SharedPreferences` 中；生产应用应使用 Keystore 或加密存储。
- Yeelight LAN 控制是可选真实设备路径；保持关闭可完全虚拟运行。

## 运行

```sh
cd examples/provider_app/android_smart_home
./gradlew assembleDebug
```

App 内：

1. 打开 **助手 → 模型** 配置 provider/base url/model/api key。
2. 发送 “打开客厅落地灯”，走本地 embedded SDK。
3. 发送超出 lights 的问题，触发协作 handoff。
4. 点击 **连接** 安装 provider agent 到运行中的 Napaxi host，再测试 provider protocol 路径。
