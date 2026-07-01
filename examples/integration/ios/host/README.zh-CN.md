# Napaxi iOS Host Integration

这是一个独立 native iOS host package，用于验证外部 Swift host 能消费 `packages/ios`。

## 用途

- 编译独立 host package。
- 运行 host-side smoke tests。
- 验证 Swift Package integration 不依赖 Flutter app。

## 验证

从仓库根目录运行：

```sh
./tools/scripts/build.sh check-ios-integration
```

该命令会编译 `examples/integration/ios/host` 和 XCTest target，并在 macOS 上运行 host-side smoke tests。
