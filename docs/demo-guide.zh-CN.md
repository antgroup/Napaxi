# Demo 指南

`examples/` 下的应用用于展示如何在真实 host app 中接入 Napaxi SDK。它们只消费 `packages/` 中的 SDK adapter，不承载可复用 SDK 实现逻辑。

## Flutter Demo

主 demo 位于：

```text
examples/flutter/
```

它展示：

- 创建 `NapaxiEngine`。
- 配置 LLM provider。
- 创建 chat session 并流式处理 chat events。
- 注册宿主自定义工具。
- Android 后台执行。
- Agent Provider 安装和 action 触发。

运行：

```sh
cd examples/flutter
flutter run
```

验证：

```sh
flutter analyze
flutter test
dart run tool/check_a2a_user_contract.dart
```

## Integration Tests

平台 smoke tests 位于：

- `examples/integration/android/`
- `examples/integration/ios/host/`
- `examples/integration/ios/app/`

它们用于验证 native library 加载、engine 启动、workspace I/O 和 iOS rootfs 等关键路径，不是教学 demo。

## Provider App Examples

`examples/provider_app/` 展示 Agent Provider protocol 的 provider 侧接入方式：

| App | 平台 | 展示内容 |
| --- | --- | --- |
| `android_smart_desk` | Android | 桌面升降控制和安装校验。 |
| `android_smart_home` | Android | 多 action smart home 和后台触发。 |
| `android_virtual_wallet` | Android | 钱包查询和 HMAC signing。 |
| `ios_virtual_wallet` | iOS | iOS provider proposal validation。 |

完整 provider 协议见 [`agent-provider-protocol.zh-CN.md`](agent-provider-protocol.zh-CN.md)。
