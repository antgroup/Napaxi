# Napaxi Examples

这个目录包含 integration examples 和 demo applications，用于展示如何在宿主应用中嵌入 Napaxi SDK。

## Flutter Demo (`flutter/`)

主 demo 是一个基于 `package:napaxi_flutter` 的轻量 chat UI，展示：

1. Engine 创建和 LLM 配置。
2. Chat session 创建、流式消息和 event rendering。
3. Host-owned custom tools 注册与结果回传。
4. Android foreground service 后台执行。
5. Agent Provider 安装和 action 触发。

运行：

```sh
cd examples/flutter
flutter run
```

验证：

```sh
flutter analyze --no-fatal-infos
flutter test
dart run tool/check_a2a_user_contract.dart
```

## Integration Tests (`integration/`)

平台 smoke tests 用于验证 native library 加载和 engine 启动：

- `integration/android/`：Android instrumentation test。
- `integration/ios/`：iOS host/app smoke。

常用命令：

```sh
./tools/scripts/build.sh check-android-integration-device
./tools/scripts/build.sh check-ios-app-device
```

## Provider App Examples (`provider_app/`)

provider app examples 展示 Agent Provider protocol 的 provider 侧能力：

| App | 平台 | 说明 |
| --- | --- | --- |
| `android_smart_desk` | Android | 桌面升降控制。 |
| `android_smart_home` | Android | 多 action smart home。 |
| `android_virtual_wallet` | Android | 钱包查询和 HMAC signing。 |
| `ios_virtual_wallet` | iOS | iOS proposal validation。 |

完整协议见 [`../docs/agent-provider-protocol.zh-CN.md`](../docs/agent-provider-protocol.zh-CN.md)。

## 接入自己的应用

1. 在项目中添加 `napaxi_flutter`、Android SDK dependency 或 Swift Package。
2. 构建 native library：`./tools/scripts/build.sh fast android` 或 `fast ios`。
3. 使用 LLM config 和 workspace directory 创建 engine。
4. 打开 chat session 并处理 stream events。
5. 按需注册 custom tools 和 provider actions。
