# Napaxi iOS SDK

`packages/ios` 是 host-side iOS integration 的 native Swift Package。它通过 `packages/api_bridge/include/napaxi_api_bridge.h` 中的 stable C ABI 使用与 Flutter 相同的 Rust core API。

当前 package 声明 iOS 16 为最低部署版本，后续 iOS QEMU runtime 编译产物也按该部署下限接入。

## 构建

打开 Xcode 前，先运行：

```sh
./tools/scripts/build.sh fast check-ios-native
```

该命令会准备本地 SwiftPM binary target：

```text
packages/ios/Frameworks/napaxi_api_bridge.xcframework
```

并对 Swift SDK、iOS QEMU bridge 占位接口和 Rust bridge 做 iPhoneOS SwiftPM build。

只需要重新生成 Flutter 和 native iOS xcframework 时，可运行：

```sh
./tools/scripts/build.sh fast ios-all
```

## API 形态

Swift SDK 提供：

- typed engine lifecycle helpers；
- raw JSON API escape hatch；
- Codable Swift models；
- Flutter-compatible model helpers，例如 `fromJson(...)`、`toJson()`；
- `NapaxiEngine` facades：`chat`、`sessions`、`agents`、`agentApp`、`automation`、`workspace`、`fileBridge`、`mcp`、`groups`。

新 Swift 代码优先使用 typed facades；raw aliases 主要用于 Flutter generated bridge 迁移和兼容。

## Platform context

`NapaxiPlatformContextResolver` 会生成与 Flutter resolver 对齐的 platform context，包括：

- `platform`
- `files_dir`
- capability profile/selection
- skill-readiness metadata

## Browser / Agent / Automation / Skills

iOS SDK 暴露与 Flutter 兼容的 typed models 和 facade names，用于：

- browser tool hosting
- agents and agent definitions
- sessions and chat events
- groups
- automation jobs and wake records
- Agent App packages/proposals/results
- skills and catalog APIs

具体方法列表以英文 README 和 Swift source 为准。

## iOS QEMU sandbox

iOS shell-like platform execution 已切到 Napaxi iOS QEMU backend。当前仓库保留 `napaxi_api_ios_qemu_*` 稳定 bridge、Swift wiring、稳定的 `alpine-rootfs.bin` 资源名，并通过 vendored 底层 QEMU C bridge/静态库提供实际 runner；没有接入隔壁 adjacent sandbox SDK wrapper。

`Sources/Napaxi/Resources/alpine-rootfs.bin` 使用独立 lightweight iOS bake profile：保留 Python、Node/npm、shell、curl/wget、zip/unzip、git；不打包 Codex CLI、OpenJDK、Android SDK/build-tools、qemu-x86_64 或 x86_64 sysroot。iOS Codex agent-engine capability 保持 disabled。

## 验证

```sh
./tools/scripts/build.sh check-ios
./tools/scripts/build.sh check-ios-native
./tools/scripts/build.sh check-ios-integration
./tools/scripts/build.sh check-ios-app
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
```

详细签名和真机说明见 [`../../docs/sdk-integration.zh-CN.md`](../../docs/sdk-integration.zh-CN.md)。
