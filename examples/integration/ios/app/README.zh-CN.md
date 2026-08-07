# Napaxi iOS Integration App

这是 native iOS integration app，用于验证 `packages/ios` Swift Package、Rust bridge、iOS QEMU sandbox 和 engine lifecycle 可以在真实 iOS app 中工作。

## 用途

- 链接 `packages/ios` Swift Package。
- 创建 Napaxi engine。
- 验证 native bridge handle。
- 验证 iOS QEMU/rootfs 相关资源状态。
- 生成 smoke report 供脚本读取。

## 构建

通常从仓库根目录通过脚本构建：

```sh
./tools/scripts/build.sh check-ios-app
```

真机运行：

```sh
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
# 如果已有不同 bundle id 的开发证书/描述文件：
IOS_DEVELOPMENT_TEAM=ABCDE12345 IOS_BUNDLE_IDENTIFIER=dev.napaxi.integration ./tools/scripts/build.sh check-ios-app-device
# 如果走已有 profile 的手动签名：
IOS_BUNDLE_IDENTIFIER=dev.napaxi.integration IOS_PROVISIONING_PROFILE_SPECIFIER="Profile Name" ./tools/scripts/build.sh check-ios-app-device
```

需要有效 Xcode Accounts、Team、provisioning profile 和已连接 iPhone。真机脚本会校验 app 内打包的 Alpine rootfs、QEMU 符号、QEMU ready 状态，并通过 shell smoke 命令确认 iOS QEMU 沙箱真的可用。若 Xcode 报 `No Account for Team` 或找不到 `dev.napaxi.integration.iosapp` 的 profile，可以在 Xcode 登录对应 Team，或通过 `IOS_BUNDLE_IDENTIFIER` 指定已有开发 profile 的 bundle id；手动签名时可传 `IOS_PROVISIONING_PROFILE_SPECIFIER`/`IOS_PROVISIONING_PROFILE_UUID` 和可选的 `IOS_CODE_SIGN_IDENTITY`。更多说明见 [`../../../docs/sdk-integration.zh-CN.md`](../../../docs/sdk-integration.zh-CN.md)。
