# Napaxi iOS Integration App

这是 native iOS integration app，用于验证 `packages/ios` Swift Package、Rust bridge、iSH runtime 和 engine lifecycle 可以在真实 iOS app 中工作。

## 用途

- 链接 `packages/ios` Swift Package。
- 创建 Napaxi engine。
- 验证 native bridge handle。
- 验证 iSH/rootfs 相关资源可用。
- 生成 smoke report 供脚本读取。

## 构建

通常从仓库根目录通过脚本构建：

```sh
./tools/scripts/build.sh check-ios-app
```

真机运行：

```sh
IOS_DEVELOPMENT_TEAM=ABCDE12345 ./tools/scripts/build.sh check-ios-app-device
```

需要有效 Xcode Accounts、Team、provisioning profile 和已连接 iPhone。更多说明见 [`../../../docs/sdk-integration.zh-CN.md`](../../../docs/sdk-integration.zh-CN.md)。
