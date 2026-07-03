# SDK Adapter 一致性

Napaxi 通过共享 Core API boundary、contract fixtures 和显式 unsupported states 来保持 Flutter、Android、iOS adapter 对齐。本文是 SDK-facing 变更的中文检查清单。

## 原则

可复用 runtime 行为属于 `crates/core`，通过 `napaxi_core::api` 到达 adapter。Adapter packages 应保持轻量：host context、lifecycle、permissions、background glue、typed facades 和平台执行。

当某个能力对 SDK 用户可见时，需要判断 parity 类型：

| 类型 | 含义 | 要求 |
| --- | --- | --- |
| Stable cross-adapter API | Flutter、Android、iOS 都应支持的公开行为。 | 更新所有 adapter，或写明 unsupported state。 |
| Experimental API | 公开但仍在演进。 | 保持 contract fixtures 最新，并记录差异。 |
| Adapter-specific feature | 依赖特定平台能力。 | 通过 capability/profile gate，并记录平台支持范围。 |
| Demo-only behavior | 只存在于 `examples/`。 | 不作为可复用 SDK 行为暴露。 |

## 证据清单

SDK-facing 变更至少应包含以下一种证据：

- Core API tests 或 fixtures。
- `packages/api_contract/` method/error/capability fixture 更新。
- Flutter model/wrapper tests。
- Android Kotlin contract/model tests。
- iOS Swift contract/model tests。
- 明确记录 unsupported state。

## 必须同步的内容

新增或修改公开 SDK surface 时：

1. 在 `crates/core/src/api/` 定义或更新 core API。
2. 保持 `packages/api_bridge/` 只是薄转发层。
3. 按需更新 Flutter/Android/iOS typed facades。
4. 更新 shared fixtures 或 adapter tests。
5. 更新用户文档，尤其是 capability 和 integration 文档。
6. 先跑最小有用检查，交付前再跑更完整的 parity gates。

## 常用检查

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-android-parity
./tools/scripts/build.sh check-ios-parity
cd packages/flutter && flutter analyze --no-fatal-infos && flutter test
```

iOS native 检查见 [`sdk-integration.zh-CN.md`](sdk-integration.zh-CN.md)。

## 避免

- Adapter 直接调用 `mobile_*` implementation modules。
- 新增绕过 capability profile 或 core API 的 adapter option。
- 在不同 adapter 之间留下静默能力缺口。
- 把可复用 runtime 行为放进 demo app。
