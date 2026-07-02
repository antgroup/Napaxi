# 贡献指南

感谢你关注 Napaxi。本指南面向中文贡献者，说明如何准备开发环境、理解仓库边界，以及怎样提交一个可审查的变更。更详细的英文原文见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 行为准则

本项目遵循 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。参与 issue、讨论、PR、代码评审或其它社区活动，即表示你同意遵守该准则。

## 安全问题

请不要在公开 issue、PR 或讨论中披露安全漏洞。安全问题请按 [`SECURITY.zh-CN.md`](SECURITY.zh-CN.md) 私下报告。

## 开发环境

你需要：

- Rust stable toolchain，edition 2024，`rust-version >= 1.92`。移动端构建需要额外安装对应 target，例如 `aarch64-linux-android` 或 `aarch64-apple-ios`。
- Flutter SDK 3.19+ 和 Dart 3.3+，用于 `packages/flutter/` 和 `examples/flutter/`。
- `ripgrep` (`rg`)，边界检查脚本会使用它。
- Android NDK 或 Xcode command-line tools，用于原生移动构建。

克隆并验证：

```sh
git clone <repo-url> napaxi
cd napaxi
cargo check --manifest-path crates/core/Cargo.toml
./tools/scripts/build.sh check-boundary
```

## 仓库边界

| 路径 | 作用 |
| --- | --- |
| `crates/core/` | Rust runtime kernel 与 adapter-facing API (`napaxi_core::api`)。 |
| `crates/features/*` | core 使用的 feature-domain crates，不能依赖 core。 |
| `packages/api_bridge/` | 基于 `napaxi_core::api` 的 FFI/Flutter Rust Bridge 层。 |
| `packages/flutter/` | Flutter SDK adapter (`napaxi_flutter`)。 |
| `packages/android/` | Native Android Kotlin SDK adapter。 |
| `packages/ios/` | Native iOS Swift Package adapter。 |
| `packages/agent_provider/` | Agent App actions 的 provider-side SDK。 |
| `examples/` | demo 和 integration apps，只消费 SDK，不承载可复用 SDK 逻辑。 |
| `vendor/` | patched 或 vendored 第三方依赖。 |
| `tools/scripts/` | build、codegen、hygiene、packaging helper。 |
| `docs/` | 架构、接入、设计和贡献文档。 |

核心规则：

- 可复用 runtime 行为放在 `crates/`，尤其是 `crates/core/`。
- SDK adapter 和 binding bridge 放在 `packages/`。
- demo-only UI、state、mock clients 和 panels 放在 `examples/`。
- adapter 通过 `napaxi_core::api` 进入 Rust，不直接调用 core 内部实现模块。
- packages 不直接依赖 `crates/features/*`。
- generated bridge 文件由 codegen 维护，不手动编辑。

新增 LLM provider、built-in tool、MCP surface、platform tool、policy hook 或后台服务时，请先定义 capability contract，并同步更新相关文档。

## 工作流

1. 大变更先开 issue 说明问题或设计，小修可以直接提交 PR。
2. 从默认开发分支创建 topic branch，例如 `feat/<area>-<short>`、`fix/<area>-<short>`、`docs/<short>`。
3. 保持提交聚焦，提交信息使用简洁的 scoped imperative 风格，例如：
   - `feat(core): add capability admission for browser tool`
   - `fix(flutter): debounce capability profile updates`
   - `docs(sdk): clarify Android integration setup`
4. 按变更范围运行验证命令。
5. 打开 PR，说明用户影响、实现范围和测试计划。
6. PR 合并前需要完成适用的 Contributor License Agreement（CLA）。见
   [`CLA.zh-CN.md`](CLA.zh-CN.md)。
7. 贡献代码即表示你同意将贡献按 GPL-3.0-or-later 授权，并遵守上述 CLA 要求。

## 本地验证

优先运行最小有用检查；交付前再跑更完整的 gate。

```sh
# Rust + boundary
./tools/scripts/build.sh check-boundary
cargo check --manifest-path crates/core/Cargo.toml
cargo test --manifest-path crates/core/Cargo.toml -- --quiet

# Flutter SDK
cd packages/flutter
flutter analyze
flutter test

# Flutter demo
cd examples/flutter
flutter analyze
flutter test
```

原生构建：

```sh
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
```

## PR 期望

- 变更范围清晰，避免顺手重构无关代码。
- SDK-facing 变更要遵循 [`docs/sdk-adapter-parity.zh-CN.md`](docs/sdk-adapter-parity.zh-CN.md)，考虑 Flutter、Android、iOS adapter parity。
- 行为变更要补充测试或说明为什么现有测试足够。
- 文档、示例和 capability registry 与实现保持一致。
- 不提交本地构建产物、密钥、证书、设备 provisioning 或私有路径。

## 许可证

Napaxi 源码采用 GPL-3.0-or-later。贡献即表示你同意贡献按该许可证发布。

## 贡献者许可协议

外部贡献在合并前需要完成 Contributor License Agreement（CLA）。以个人身份提交
贡献时使用个人 CLA；如果贡献由雇主或其它法律实体拥有或控制，则应使用公司
CLA。

蚂蚁集团官方 CLA 表单和签署要求见 [`CLA.zh-CN.md`](CLA.zh-CN.md)。自动化 CLA
检查依赖代码托管平台配置；在该检查启用前，maintainer 可以在合并外部 PR 前
人工确认 CLA 完成情况。
