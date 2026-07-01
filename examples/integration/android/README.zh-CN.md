# Napaxi Android Native Demo

这是一个 native Android SDK demo 和 integration check，通过 Gradle composite build 消费 `packages/android`。它只包含 host-app code；可复用 SDK 行为保留在 `packages/android` 和 `crates/core`。

## 展示能力

启动页提供手动 demo actions，覆盖 Android SDK public facades：

- Engine/config、capability registry、custom tools、platform tools、browser tools。
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

该 smoke 会安装 Smart Desk provider app 和 Android integration app，触发 provider action result handoff，并等待 UI 汇报 SDK smoke results。

## 手动 tour

App 内的 **Run Full Interface Tour** 会遍历当前 Android SDK facades，并输出每个 section 的摘要。
