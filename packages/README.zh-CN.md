# Packages

`packages/` 存放 SDK adapter 和 binding bridge packages。

| 路径 | 作用 |
| --- | --- |
| `api_contract/` | Contract-first SDK adapter 目标、method inventory、capability matrix 和标准 wire error envelope。 |
| `api_bridge/` | 基于 `napaxi_core::api` 的 Rust FFI/FRB bridge。 |
| `flutter/` | Flutter adapter package。 |
| `ios/` | 基于 stable C ABI 的 native Swift Package adapter。 |
| `android/` | 基于 shared JNI bridge 的 native Kotlin Android adapter。 |
| `agent_provider/` | Provider-side protocol helper packages。 |

## SDK Adapter 目标

`packages/` 正在收敛到 contract-first adapter model：

```text
napaxi_core::api contract
  -> api_bridge wire methods
  -> Flutter / iOS / Android typed facades
  -> cross-platform golden tests
```

新的公开 package API 应先从 `api_contract/` 出发，携带稳定性标签，并避免新增 `false`、`0` 或空字符串这类错误 sentinel。

## 规则

- 所有 SDK adapter 和 bridge packages 都放在 `packages/`，不要新增平级 `sdk/` 目录。
- 不要重新引入通用 `napaxi_sdk` package；adapter package 名称应描述其角色。
- `api_bridge/` 只委托给 `napaxi_core::api`，不拥有 runtime policy。
- `api_bridge/` 保持扁平结构：root Rust entrypoints、`bridge/` 手写模块、`generated/` codegen 输出。
- `flutter/lib/` 按职责保持扁平，不新增持久 `lib/src/` 层。
- generated bridge 文件由 codegen 管理，不手动编辑。
- `flutter/android/` 的 manifest、assets、JNI libraries 和 resources 保留在 Android package root。
