# Scripts

共享 build、codegen、hygiene 和 packaging 脚本位于 `tools/scripts/`。请从仓库根目录运行。

常用命令：

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-android-parity
./tools/scripts/build.sh check-ios-parity
./tools/scripts/build.sh check-ios
./tools/scripts/build.sh check-android-integration
./tools/scripts/build.sh check-android-integration-device
./tools/scripts/build.sh check-ios-native
./tools/scripts/build.sh check-ios-app
./tools/scripts/build.sh check-ios-device
./tools/scripts/build.sh check-ios-app-device
```

## Android parity

```sh
./tools/scripts/check-android-flutter-parity.js
```

用于检查 public Android SDK migration surface 是否与 Flutter 对齐。

## iOS parity

```sh
./tools/scripts/build.sh check-ios-parity
```

用于检查 public iOS SDK migration surface，包括 Flutter generated bridge function names 与 Swift entrypoints。

## iOS acceptance gate

```sh
./tools/scripts/build.sh check-ios
```

该命令会运行 iOS/Flutter public surface parity、native Swift Package compile/tests 和 Flutter iOS package build。

## Flutter iOS package

```sh
./tools/scripts/build.sh check-ios-app
./tools/scripts/build.sh check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
```

`check-ios-app` 会构建并校验 `examples/flutter` 生成的 IPA。`check-ios-app-device` 会构建、签名、安装并启动 iOS 包，因此需要：

- 可用的 Xcode command-line tools。
- 已连接且可用的 iPhone。
- 已启用 Developer Mode。
- 有效的 Apple ID、Team 和 provisioning profile。
- 如有需要，环境变量 `IOS_DEVELOPMENT_TEAM`。

如果 Xcode 报 `No Account for Team` 或找不到对应 app 的 profile，请先在 Xcode Accounts 中刷新 Apple ID 和 team，再重跑 Release IPA 流程。
