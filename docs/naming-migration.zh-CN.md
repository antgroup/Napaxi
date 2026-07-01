# Naming Migration

本文件是 [`naming-migration.md`](naming-migration.md) 的中文 companion，用于说明 legacy naming 的迁移方向。

## 背景

Napaxi 早期代码中存在一些 legacy internal naming，例如 `Mobile*` 或旧 implementation module 名称。它们不代表新的公开 API 方向。

## 原则

- 对外使用 Napaxi 和 adapter-neutral SDK 命名。
- 新公开 API 优先使用 typed、capability-driven、adapter-neutral 名称。
- `mobile_*` module name 只作为 legacy internal implementation 过渡存在。
- 不新增 public `mobile_*` API surface。
- 不在 `crates/core/src/api` 中做 broad `pub use crate::mobile_*::*`。

## 迁移节奏

在破坏性版本窗口中逐步：

1. 为新名称补充 typed API 和 adapter wrapper。
2. 保留兼容 alias 或 legacy bridge surface。
3. 更新 Flutter/Android/iOS adapter parity fixtures。
4. 更新文档和 changelog。
5. 在计划版本中移除或隐藏 legacy public surface。

## 贡献者注意

如果你新增 SDK-facing 能力，请直接使用新命名，不要扩大 legacy naming 的使用范围。涉及公开 API 的重命名，需要同时更新 adapter parity、fixtures、docs 和 release notes。
