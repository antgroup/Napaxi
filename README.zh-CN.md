<p align="center">
  <img src="docs/assets/napaxi-logo.png" alt="Napaxi" width="720">
</p>

<p align="center">
  <strong>用于在移动应用中嵌入 Agent 体验的 mobile-native SDK。</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: GPL-3.0-or-later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg"></a>
  <img alt="Status: SDK 1.0" src="https://img.shields.io/badge/status-SDK%201.0-blue.svg">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-1.92%2B-dea584?logo=rust&amp;logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-SDK-02569B?logo=flutter&amp;logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.3%2B-0175C2?logo=dart&amp;logoColor=white">
  <img alt="Kotlin" src="https://img.shields.io/badge/Kotlin-Android-7F52FF?logo=kotlin&amp;logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-iOS-F05138?logo=swift&amp;logoColor=white">
  <img alt="Git LFS" src="https://img.shields.io/badge/Git%20LFS-required-lightgrey.svg">
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

Napaxi 为应用团队提供共享的 Rust Agent 运行时、轻量移动 SDK 适配层，以及用于验证公开 API 的 demo app。宿主 App 继续负责 UI、账号、模型配置、权限和产品策略；Napaxi 负责可复用的运行时能力：session、workspace 状态、存储、工具、技能、MCP、平台 hook、后台执行和 adapter contract。

Flutter 是第一个完整 adapter 和 demo 目标。Android 与 iOS SDK adapter 与它并列存在，并共享同一个 Core API 边界。

[文档](docs/README.zh-CN.md) · [Flutter SDK](packages/flutter/README.md) ·
[架构](docs/architecture.md) · [安全](SECURITY.zh-CN.md) ·
[贡献指南](CONTRIBUTING.zh-CN.md) · [CLA](CLA.zh-CN.md) · [发布指南](RELEASING.zh-CN.md)

## 为什么选择 Napaxi

- **纯端 Agent 运行时**
  Napaxi 原生运行在移动 App 内。除宿主 App 明确批准的云端模型访问外，运行时不依赖 Napaxi 云端服务器，也不依赖远程开发服务器；workspace 数据、session 状态、文件、工具元数据和 Agent 执行过程都留在手机端。
- **可信沙箱，安全执行**
  本地工具执行被移动端沙箱、core policy gate 和宿主授权机制隔离保护。宿主 App 可以控制 Agent 能访问哪些外部权限、平台工具、文件、channel 和后台能力。
- **插件化可扩展工具**
  Napaxi 支持 14+ 移动端特色内置工具、模型工具化、多模型编排、MCP 工具和宿主自定义工具。工具面向扩展设计，同时不把产品策略从宿主 App 中拿走。
- **组件化场景**
  SDK 能力以可复用的 runtime 和 adapter 组件组织，团队可以按业务组合不同 Agent 场景，而不是为每个 App、设备或 workflow 重建一套独立栈。
- **端到端互联：xApp、xAgent、xChannel**
  Napaxi 连接应用、Agent、channel 和设备。xApp 支持移动端 Agent 应用新范式和应用间交互；xAgent 支持端内多 Agent 协作和端外 Agent 互联；xChannel 面向更广义的 channel 与设备连接，包括 QQ 等 IM 工具、蓝牙耳机、车机、无人机以及更多智能设备表面。

## 可以构建什么

当你需要一个嵌入 App 的 Agent 时，Napaxi 可以帮助你：

- 基于 App 自有 session 和 history 进行对话；
- 使用 workspace 文件、记忆、技能、内置工具和 MCP 工具；
- 暴露由宿主批准的平台工具，例如文件、浏览器、设备和后台能力；
- 在同一个宿主 App 内支持多 Agent 和 group 协作；
- 使用宿主选择的 LLM provider 和模型配置；
- 让 SDK 行为在 Flutter、Android、iOS adapter 间保持可迁移。

SDK 不内置产品 UI。宿主 App 决定具体体验；Napaxi 提供运行时和移动端集成层。

## 使用示例

下面三个示例分别展示 Napaxi 的三类集成层：端侧开发工具、沙箱化文件工具，
以及 provider 驱动的设备动作。

### 纯移动端开发

直接在手机上完成移动 App 的生成、修改、构建和安装。宿主 App 可以接入
Codex、Claude Code 等引擎，但执行链路留在手机端：Agent 在移动端 workspace
中生成或更新 Android 应用代码，通过宿主授权的端侧工具构建 APK，并把结果
直接安装回当前设备。除宿主批准的模型请求外，这个流程不依赖云端开发服务器。

| 生成移动应用 | 更新、构建并安装 |
| --- | --- |
| <img src="docs/assets/mobile-dev-generate.gif" alt="Napaxi 在手机上生成移动应用" width="260"> | <img src="docs/assets/mobile-dev-update.gif" alt="Napaxi 更新移动应用并将 APK 安装到手机" width="260"> |

### 移动端文件工具：图片压缩

通过同一套沙箱化工具链暴露日常文件能力。这个流程中，Agent 接收宿主授权的
图片文件，按目标大小压缩，写回 workspace，并返回结果路径，方便宿主 App
继续预览、分享或作为附件使用。

<p align="center">
  <img src="docs/assets/mobile-image-compression.png" alt="Napaxi 在手机上压缩图片文件" width="300">
</p>

### 智能设备互联：智能家居

把 Agent 决策路由到宿主授权的 provider app，并执行具体设备动作，例如控制
智能家居灯光。Core 负责保持 session state、routing、policy 和 action result
contract 的一致性，真实设备 I/O 由 provider 负责。

<p align="center">
  <img src="docs/assets/mobile-smart-home.gif" alt="Napaxi 在手机上控制智能家居灯光" width="480">
</p>

## 快速开始

前置依赖：

- Rust stable toolchain，以及你计划构建的移动端 target。
- Flutter SDK，用于 `packages/flutter` 和 `examples/flutter`。
- Git LFS，用于拉取仓库内移动运行时资产。
- Android NDK 和/或 Xcode command-line tools，用于原生移动构建。

克隆仓库并拉取运行时资产：

```sh
git clone <repo-url> napaxi
cd napaxi
git lfs pull
```

运行 core 边界检查：

```sh
./tools/scripts/build.sh check-boundary
```

运行 Flutter demo：

```sh
cd examples/flutter
flutter run
```

demo 使用仓库内本地 Flutter SDK：

```yaml
dependencies:
  napaxi_flutter:
    path: ../../packages/flutter
```

宿主 Flutter App 从公开 SDK 入口导入：

```dart
import 'package:napaxi_flutter/napaxi_flutter.dart';
```

SDK API 示例见 [`packages/flutter/README.md`](packages/flutter/README.md)。

## 构建原生产物

在仓库根目录构建移动 SDK 产物：

```sh
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
```

生成产物是本地构建结果，默认不提交：

- `packages/flutter/android/jniLibs/*/libnapaxi_api_bridge.so`
- `packages/flutter/ios/Frameworks/napaxi_api_bridge.xcframework`
- `packages/ios/Frameworks/napaxi_api_bridge.xcframework`

iOS 真机检查、签名、provisioning 和 Swift Package 细节见 [`docs/sdk-integration.zh-CN.md`](docs/sdk-integration.zh-CN.md)。

## 架构速览

```text
Host app
  -> SDK adapter (Flutter / Android / iOS)
  -> packages/api_bridge
  -> napaxi_core::api
  -> Rust runtime domains
```

仓库结构：

```text
napaxi/
  crates/
    core/             Rust runtime kernel 与 adapter-facing Core API。
    features/         core 使用的 feature-domain crates。
  packages/
    api_bridge/       基于 napaxi_core::api 的 Rust FFI/FRB bridge。
    api_contract/     Adapter API contract：methods、errors、fixtures。
    flutter/          Flutter SDK package，对外为 napaxi_flutter。
    android/          Native Android Kotlin SDK adapter。
    ios/              Native iOS Swift Package adapter。
    agent_provider/   Agent App actions 的 provider-side SDK。
  examples/
    flutter/          使用 ../../packages/flutter 的 Flutter 集成 demo。
    provider_app/     Agent App actions 的 provider 示例 app。
  vendor/             patch 或 vendored 的第三方依赖。
  tools/scripts/      build、codegen、hygiene 和 packaging helper。
  docs/               架构、集成和贡献文档。
```

依赖方向刻意保持收敛：

```text
crates/features/* -> crates/core -> packages/api_bridge -> SDK adapters -> examples
```

Adapter 必须通过 `napaxi_core::api`。Packages 不应直接依赖 `crates/features/*`，demo app 必须调用公开 SDK API。

## 安全模型

Napaxi 运行在宿主 App 内，并可能暴露强大的本地能力。请把每一个 Agent action surface 都视为 App policy，而不只是 SDK plumbing。

- 宿主 App 选择模型 provider、账号、权限和启用的工具。
- Core policy 负责 tool descriptor admission、tool invocation admission、provider admission 和 model switching gate。
- Platform tools 和后台执行由 adapter 拥有，必须通过 SDK API 显式暴露。
- Channel/provider 集成应归一化 inbound messages，并让 core 处理 routing、sessions、history、policy 和 outbound queue state。
- 安全问题请遵循 [`SECURITY.zh-CN.md`](SECURITY.zh-CN.md)，不要提交公开 issue。

发布带原生运行时资产的 App 前，请检查 [`THIRD-PARTY-LICENSES.zh-CN.md`](THIRD-PARTY-LICENSES.zh-CN.md) 中的许可证和再分发说明。

## 验证变更

先运行最小有用检查，再在交付或发布前运行更完整的 gate。

```sh
# Rust/core/API boundary
./tools/scripts/build.sh check-boundary
cargo check --manifest-path crates/core/Cargo.toml
cargo test --manifest-path crates/core/Cargo.toml -- --quiet

# Flutter SDK
cd packages/flutter
flutter analyze --no-fatal-infos
flutter test

# Flutter demo
cd examples/flutter
flutter analyze --no-fatal-infos
flutter test
```

发布卫生检查：

```sh
./tools/scripts/build.sh check-hygiene
NAPAXI_RELEASE=1 ./tools/scripts/build.sh check-hygiene
```

完整发布流程见 [`RELEASING.zh-CN.md`](RELEASING.zh-CN.md)。

## 按目标阅读文档

| 目标 | 入口 |
| --- | --- |
| 了解项目 | [`docs/overview.zh-CN.md`](docs/overview.zh-CN.md) |
| 理解所有权边界 | [`docs/architecture.md`](docs/architecture.md) |
| 集成或构建 SDK 产物 | [`docs/sdk-integration.zh-CN.md`](docs/sdk-integration.zh-CN.md) |
| 使用 Flutter SDK | [`packages/flutter/README.md`](packages/flutter/README.md) |
| 保持 adapter 同步 | [`docs/sdk-adapter-parity.zh-CN.md`](docs/sdk-adapter-parity.zh-CN.md) |
| 新增 capability | [`docs/mobile-capabilities.zh-CN.md`](docs/mobile-capabilities.zh-CN.md) |
| 开发 provider app | [`docs/agent-provider-protocol.zh-CN.md`](docs/agent-provider-protocol.zh-CN.md) |
| 了解 Agent App actions | [`docs/agent-app-actions.zh-CN.md`](docs/agent-app-actions.zh-CN.md) |
| 贡献代码 | [`CONTRIBUTING.zh-CN.md`](CONTRIBUTING.zh-CN.md) |
| 完成 CLA | [`CLA.zh-CN.md`](CLA.zh-CN.md) |
| 报告安全问题 | [`SECURITY.zh-CN.md`](SECURITY.zh-CN.md) |

本地生成 API 文档：

```sh
cargo doc --no-deps -p napaxi-core --open
cd packages/flutter
dart doc
```

## 开发边界

- 可复用运行时行为属于 `crates/`，尤其是 `crates/core/`。
- Feature-domain 逻辑属于 `crates/features/`，并且不能依赖 core。
- SDK adapter、平台 glue 和 binding bridge package 属于 `packages/`。
- Demo-only UI、state、mock clients 和 panels 属于 `examples/`。
- Build、codegen、hygiene 和 packaging helper 属于 `tools/scripts/`。
- 稳定架构和集成说明属于 `docs/`。
- 不要手动编辑生成的 bridge 文件。

如果某个行为需要被多个 host app 或 adapter 共享，应放入 Rust core 或 SDK package，并通过公开 API 暴露。

## 状态

Napaxi SDK `1.0.0` 是首个公开 SDK release。`crates/core/src/api/` 下的 Core API 是稳定的 adapter-facing 边界，更底层的 runtime internals 仍会继续演进。公开 API 变更记录见 [`CHANGELOG.md`](CHANGELOG.md)。

## 联系我们

公开项目问题、合作沟通或 release 协调，请联系维护者：
[wenyu.mwt@antgroup.com](mailto:wenyu.mwt@antgroup.com)。安全问题请按
[`SECURITY.zh-CN.md`](SECURITY.zh-CN.md) 的流程私下报告，不要通过公开 issue
或邮件线程披露。

## 贡献

欢迎提交 issue 和 pull request。较大变更前，请先阅读 [`CONTRIBUTING.zh-CN.md`](CONTRIBUTING.zh-CN.md)，了解环境配置、边界规则、验证要求和许可证条款。外部贡献需要完成适用的 Contributor License Agreement，见 [`CLA.zh-CN.md`](CLA.zh-CN.md)。

## 许可证

Napaxi 源码采用 GNU General Public License v3.0 or later（`GPL-3.0-or-later`）。见 [`LICENSE`](LICENSE) 和 [`NOTICE`](NOTICE)。

分发的移动 SDK 还包含第三方原生运行时组件，它们有各自的许可证，包括 sandbox 相关资产的 GPL/LGPL 义务。再分发构建产物前，请阅读 [`THIRD-PARTY-LICENSES.zh-CN.md`](THIRD-PARTY-LICENSES.zh-CN.md)、[`packages/flutter/android/jniLibs/THIRD-PARTY.md`](packages/flutter/android/jniLibs/THIRD-PARTY.md) 和 [`packages/ios/Vendor/iSHCore/THIRD-PARTY.md`](packages/ios/Vendor/iSHCore/THIRD-PARTY.md)。
