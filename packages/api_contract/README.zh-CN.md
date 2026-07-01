# Napaxi SDK API Contract

`packages/api_contract/` 是 adapter layer 的 contract home，用于定义 bridge methods 和 SDK facade 应收敛到的目标形态。

## 目标

让 `packages/` 成为 contract-first SDK adapter layer：

```text
napaxi_core::api contract
  -> packages/api_bridge wire methods
  -> Flutter / iOS / Android typed SDK facades
  -> cross-platform golden tests
```

Adapter 应翻译 host platform concern 和 typed model，不重新实现 runtime policy。共享行为属于 `napaxi_core::api`。

## Contract files

- `goals.md`：SDK Adapter 2.0 目标和迁移规则。
- `errors.yaml`：标准 wire result 和 error envelope。
- `methods.yaml`：method namespace inventory 和 stability labels。
- `capability_matrix.yaml`：跨 adapter capability coverage 和 status。
- `workspace.json`：workspace methods 的首个可执行 vertical slice。

## Stability labels

- `stable`：新 host integration 推荐使用。
- `experimental`：可用但允许演进。
- `compat`：保留给 source migration 或历史 Flutter-shaped entrypoint。
- `raw`：core API 的 JSON passthrough escape hatch。
- `generated`：codegen-owned，不手动编辑。

## 新 package API 规则

1. 新增 public adapter method 前先更新 contract。
2. 新 wire method 使用 `errors.yaml` 的标准 `ResultEnvelope`。
3. Public typed facade 标注 stability label。
4. Raw JSON escape hatch 必须保留同样的 error envelope 和 method identity。
5. 跨多个 adapter 的 surface 需要 shared fixtures 或 parity tests。
6. Contract fixtures 应绑定对应 method response shape，并覆盖 unknown fields preservation。
7. 修改 contract 或 covered adapter surface 后运行 `./tools/scripts/build.sh release check-api-contract`。
