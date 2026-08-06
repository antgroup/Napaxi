# SDK 集成

本文件是 [`sdk-integration.md`](sdk-integration.md) 的中文 companion，面向接入 Napaxi SDK 的应用团队。

## Flutter Demo 依赖

仓库内 Flutter demo 通过 path dependency 使用本地 SDK：

```yaml
dependencies:
  napaxi_flutter:
    path: ../../packages/flutter
```

`packages/flutter` 通过 Cargo path dependencies 使用本仓库 Rust crates，包括 `crates/core`。

## 原生构建

在仓库根目录构建 native artifacts：

```sh
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
./tools/scripts/build.sh fast ios-all
```

在 Windows 上手动执行 `build.sh` 时，请使用 Git Bash。Android Gradle
构建会自动探测 Git Bash；如果探测失败，请把 `NAPAXI_BASH` 设置为 Git Bash
的 `bash.exe` 完整路径。

生成产物默认被 git 忽略：

- `packages/flutter/android/jniLibs/*/libnapaxi_api_bridge.so`
- `packages/flutter/ios/Frameworks/napaxi_api_bridge.xcframework`
- `packages/ios/Frameworks/napaxi_api_bridge.xcframework`

Android proot runtime assets 和 helper libraries 是 SDK source assets，需要通过 Git LFS 拉取。来源、hash 和许可证见：

- [`../THIRD-PARTY-LICENSES.zh-CN.md`](../THIRD-PARTY-LICENSES.zh-CN.md)
- [`../packages/flutter/android/jniLibs/THIRD-PARTY.md`](../packages/flutter/android/jniLibs/THIRD-PARTY.md)

iOS Swift Package (`packages/ios`) 现在接入 iOS QEMU 沙箱 backend：iOS 保留稳定文件名 `alpine-rootfs.bin`，但使用独立 lightweight rootfs profile，不复用 Android 的完整 APK 构建镜像。iOS rootfs 包含 Python、Node/npm、shell、curl/wget、zip/unzip、git；不打包 Codex CLI、OpenJDK、Android SDK/build-tools、qemu-x86_64 或 x86_64 sysroot。QEMU runtime 已链接、rootfs 资源已打包且 host 开启对应能力时，iOS shell 沙箱能力可用；iOS Codex agent-engine capability 保持 disabled。打开 Xcode 或运行 SwiftPM iOS build 前，仍需要先生成 `packages/ios/Frameworks/napaxi_api_bridge.xcframework`。

## 验证

常用验证命令：

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-ios
./tools/scripts/build.sh check-ios-native
./tools/scripts/build.sh check-ios-integration
./tools/scripts/build.sh check-ios-app
./tools/scripts/build.sh check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
./tools/scripts/build.sh check-ios-parity
cd packages/flutter && flutter analyze --no-fatal-infos && flutter test
cd examples/flutter && flutter analyze --no-fatal-infos && flutter test
```

如果设置了 `HTTP_PROXY` 或 `HTTPS_PROXY`，运行 Flutter tests 前请确保 `NO_PROXY` 包含 `localhost`、`127.0.0.1` 和 `::1`。

## iOS 真机

`check-ios-app-device` 会构建、签名、安装并启动 iOS integration app，因此需要：

- 可用的 Xcode command-line tools。
- 已连接且可用的 iPhone。
- 已启用 Developer Mode。
- 有效的 Apple ID、Team 和 provisioning profile。
- 环境变量 `IOS_DEVELOPMENT_TEAM`。

如果 Xcode 报 `No Account for Team` 或 `No profiles ... were found`，请先在 Xcode Accounts 中刷新 Apple ID 和 team，再重跑 device smoke。

## 已知权衡

### iOS QEMU sandbox

Native iOS SDK 通过 stable C ABI 调用与 Flutter 相同的 `napaxi_core::api`。Shell-like platform execution 已切到 Napaxi iOS QEMU backend。当前仓库保留稳定 API、Swift wiring、稳定的 `alpine-rootfs.bin` 资源名，并通过 vendored 底层 QEMU C bridge/静态库提供实际 runner；没有接入隔壁 adjacent sandbox SDK wrapper。iOS rootfs 使用 lightweight profile，不包含 Codex CLI 或 Android APK 构建工具链。

### Vendored `libsql`

`vendor/libsql-patched/` 是带移动端构建修复的 `libsql` vendored copy，通过 workspace `Cargo.toml` 中的 `[patch.crates-io]` 使用。

目标是当 upstream 能干净支持 `aarch64-linux-android` 和 `aarch64-apple-ios` 后删除该 vendor 目录。
