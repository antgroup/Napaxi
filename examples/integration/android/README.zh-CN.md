# Napaxi Android Native Demo

这是一个 native Android SDK demo 和 integration check，通过 Gradle composite build 消费 `packages/android`。它只包含 host-app code；可复用 SDK 行为保留在 `packages/android` 和 `crates/core`。

## 展示能力

启动页提供手动 demo actions，覆盖 Android SDK public facades：

- Engine/config、capability registry、custom tools、platform tools、browser tools、Codex app-server engine probe。
- Sessions、chat streaming、session runs、agents、groups、workspace、memory、file bridge、skills、evolution。
- Background service/notifications、automation jobs、MCP、A2A、Agent App packages/results、Agent Provider discovery/install/action handoff、APK installer。

缺少真实 API key、server、provider app、camera/microphone flow 或 APK path 时，demo 会展示稳定 SDK error/result shape，而不是把环境缺失当成 demo 失败。

## 构建

```sh
cd examples/integration/android
../../flutter/android/gradlew assembleDebug
```

## 真机 smoke

从仓库根目录运行：

```sh
./tools/scripts/build.sh check-android-integration-device
```

如果需要验证真实 Codex app-server probe，可以在启动真机检查前通过环境变量提供所选 profile 的 API key。脚本会把它作为 debug app 的 launch intent 传入，App 只写入 `local-dev` profile 的本地配置，不在源码中硬编码密钥。如果真机网络需要 OpenAI-compatible 网关，请显式传入 Base URL 和模型，不要改源码硬编码：

```sh
NAPAXI_ANDROID_INTEGRATION_API_KEY=... \
NAPAXI_ANDROID_INTEGRATION_BASE_URL=https://gateway.example/v1 \
NAPAXI_ANDROID_INTEGRATION_MODEL=gpt-4.1 \
  ./tools/scripts/build.sh check-android-integration-device
```

如果设备必须通过代理访问 Codex CLI 网络，可以显式传入代理配置。这些值只写入 Codex probe agent 的 `engine_config.network_env`，并且只导出给沙箱内的 `codex app-server` 进程：

```sh
NAPAXI_ANDROID_INTEGRATION_API_KEY=... \
NAPAXI_ANDROID_INTEGRATION_HTTPS_PROXY=http://proxy.example:7890 \
NAPAXI_ANDROID_INTEGRATION_NO_PROXY=localhost,127.0.0.1 \
  ./tools/scripts/build.sh check-android-integration-device
```

设置 `NAPAXI_ANDROID_INTEGRATION_RUN_CODEX_PROBE=1` 后，真机检查会自动点击
**Codex Engine Probe**，并要求 UI 输出 `codexConfigSuccess`、`hostApiNetwork`、
`codexNetworkEnv`、`chatTimedOut` 等脱敏诊断。只有在设备确实能访问真实模型端点时，
再设置 `NAPAXI_ANDROID_INTEGRATION_EXPECT_CODEX_LIVE=1`；该严格模式还会要求 turn
不超时，证明模型回复中包含文本附件和 PNG 图片中的哨兵信息，并拿到 custom dynamic tool 与 `get_device_info` platform tool result。

该 smoke 会安装 Smart Desk provider app 和 Android integration app，触发 provider action result handoff，并等待 UI 汇报 SDK smoke results。

## 手动 Codex probe

App 内的 **Codex Engine Probe** 会把当前模型同步到 Codex app-server engine，创建 Codex-backed agent，通过 host path 发送本地文本和 PNG 附件，要求回复回显文本/图片哨兵，放行 custom host tool 与非跳转型 `napaxi.platform_tool.get_device_info`，并输出 stream event/tool 证据。当所选 profile 显式配置了 Base URL 时，Probe 还会输出脱敏的 `hostApiNetwork` Android App 进程 HTTPS 检查结果，用来区分 App 网络、Codex 沙箱内网络和 app-server 链路问题，同时避免在 demo 中内置端点默认值。该功能用于真机或模拟器验证 app-server 链路，同时不把可复用 runtime 行为放进 demo app。

## 手动 tour

App 内的 **Run Full Interface Tour** 会遍历当前 Android SDK facades，并输出每个 section 的摘要。
