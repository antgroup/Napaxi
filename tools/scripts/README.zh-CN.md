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

## Layer 3：物理设备回归

`./tools/scripts/layer3_device_regression.sh` 在物理设备上跑 Maestro smoke
flow：Android 手机通过 `adb`，iPhone 通过 `devicectl`。先用保留数据的
`adb install -r` 构建并安装 example app，再驱动
`examples/flutter/.maestro` 下的 flow。

典型调用（仅 Android，指定设备）：

```sh
./tools/scripts/layer3_device_regression.sh --android-only --android-serial 7e78be85
```

结果落在 `$HOME/testing/results/<时间戳>-layer3/` 下，每个平台一份 JSON
（`android.json` / `ios.json`），并打印一行整体 `verdict`。每个 JSON 含
`steps.build / install / maestro`、`verdict`（`PASS` / `FAIL` / `SKIP`），
Android 版额外带一块 `autoclick.taps` / `autoclick.exit_reason` 观测字段，
该字段**不影响 verdict**。

### Android 安装自动点击

MIUI 的「继续安装」弹窗会卡住无人值守的 `adb install -r`。
`tools/scripts/android_install_autoclick.sh` 是入库的自动点击脚本；layer 3
在 Maestro 运行前在后台启动它、结束后再 kill，原始日志落到
`$RESULT_DIR/android-autoclick.log`。检测只使用
`adb shell dumpsys window | grep -m1 mCurrentFocus` 与 `adb shell input tap`，
**刻意避开 UI Automator dump**——该桥会挂载无障碍服务，导致 Flutter
integration_test 收尾出现假失败 `A SemanticsHandle was active at the end of
the test`。

一次性前置（通过 `adb shell` 设置）：

```sh
# 开发者选项 -> "USB 调试（安全设置）" = 开
# （需人工开一次，否则 `adb shell input tap` 报 INJECT_EVENTS 安全异常）
# 每次运行前屏幕需保持解锁。
adb shell settings put global stay_on_while_plugged_in 7
adb shell settings put system screen_off_timeout 2147483647
```

保持屏幕常亮，避免安装过程中息屏触发
`INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`。可用
`--tap-x` / `--tap-y` 或环境变量 `AUTOCLICK_TAP_X` / `AUTOCLICK_TAP_Y`
按机型覆盖坐标（默认 `346 2483`，小米 15「继续安装」中心）。
