# Napaxi 发布指南

本文件是 [`RELEASING.md`](RELEASING.md) 的中文 companion，用于帮助维护者理解发布流程。具体命令和英文原文保持一致。

## 版本策略

Napaxi 使用 Semantic Versioning。workspace 中主要 Rust crate 与 Flutter SDK 版本应保持同一发布节奏：

- `napaxi-core`
- `napaxi_skills`
- `napaxi_evolution`
- `napaxi_api_bridge`
- `napaxi_flutter`

在 `1.0.0` 前，破坏性变更可能出现在 `0.MINOR.0`。

## 发布前检查

从干净工作区运行：

```sh
git status
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo check --workspace
cargo test --workspace --no-fail-fast
./tools/scripts/build.sh check-boundary
NAPAXI_RELEASE=1 ./tools/scripts/build.sh check-hygiene
cargo deny check
cargo audit
( cd packages/flutter && flutter analyze && flutter test )
( cd examples/flutter && flutter analyze && flutter test )
cargo bench --workspace -- --quick
```

`NAPAXI_RELEASE=1` 会把 placeholder 检查从 warning 提升为 failure。发布前必须修复所有 placeholder。

## 发布步骤

1. 更新 Rust crates 和 `packages/flutter/pubspec.yaml` 中的版本。
2. 更新 `CHANGELOG.md`：把 `Unreleased` 内容移动到正式版本日期下。
3. 构建 Android 和 iOS 原生产物：

   ```sh
   ./tools/scripts/build.sh release android
   ./tools/scripts/build.sh release ios
   ```

4. 同步 Flutter SDK release repo：

   ```sh
   ./tools/scripts/sync_prebuilt_to_release_repo.sh
   ./tools/scripts/sync_prebuilt_to_release_repo.sh path/to/napaxi_flutter_release
   ```

5. 提交版本变更，打 tag，并推送：

   ```sh
   git commit -am "release: X.Y.Z"
   git tag -a vX.Y.Z -m "Napaxi X.Y.Z"
   git push origin HEAD
   git push origin vX.Y.Z
   ```

6. 基于 tag 创建 GitHub Release，粘贴 changelog，并按需附加预构建产物。

## 发布后

- 确认 `CHANGELOG.md` 已重新保留空的 `Unreleased` 段。
- 按项目约定决定是否进入下一个 `-dev` 版本。
- 在项目讨论或发布渠道公告。

## Hotfix

Hotfix 从最近 release tag 拉分支，而不是从默认开发分支直接发布。Cherry-pick 修复、 bump patch 版本、重新跑发布前检查，然后重复构建、tag 和 release 流程。

## 相关文档

- [`CHANGELOG.md`](CHANGELOG.md)
- [`docs/sdk-integration.zh-CN.md`](docs/sdk-integration.zh-CN.md)
- [`THIRD-PARTY-LICENSES.zh-CN.md`](THIRD-PARTY-LICENSES.zh-CN.md)
