# Tools

`tools/` 存放项目脚本和本地工具。主要脚本位于 `tools/scripts/`。

常用入口：

```sh
./tools/scripts/build.sh check-boundary
./tools/scripts/build.sh check-hygiene
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
```

脚本职责：

- build：Rust、Flutter、Android、iOS 构建入口。
- codegen：bridge 和 adapter 生成代码。
- hygiene：开源前检查、命名残留、release placeholder、文件大小 advisory。
- packaging：移动端 native artifact 构建和发布同步。

运行具体脚本前，请优先查看脚本内 usage 或 [`../docs/sdk-integration.zh-CN.md`](../docs/sdk-integration.zh-CN.md)。
