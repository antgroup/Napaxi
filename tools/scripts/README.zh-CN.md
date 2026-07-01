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
./tools/scripts/build.sh check-ios-integration
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

该命令会运行 iOS/Flutter public surface parity、native Swift Package compile/tests、independent host package integration 和 no-codesign Xcode app build。真机 launch smoke 需单独运行 `check-ios-app-device`。

## 真机 iOS smoke

```sh
./tools/scripts/build.sh check-ios-device
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
```

`IOS_DEVELOPMENT_TEAM` 必填。需要 Xcode 自动创建或更新 provisioning profile 时设置 `IOS_ALLOW_PROVISIONING_UPDATES=1`。

更多背景见 [`../../docs/sdk-integration.zh-CN.md`](../../docs/sdk-integration.zh-CN.md)。
