# 概览

Napaxi 是用于构建端侧 Agent 体验的 mobile-native SDK。Rust runtime kernel 负责 agent session、workspace policy、storage、tools、skills、group collaboration、MCP 和 platform hooks；轻量 adapter packages 通过稳定 Core API (`crates/core/src/api/`) 将这些能力暴露给宿主 App。

宿主 App 嵌入 SDK，而不是调用桌面或服务端 gateway。除宿主批准的云端模型访问外，workspace 数据、session 状态、文件、工具元数据和本地执行过程都留在端上。

仓库刻意保持 mobile-generic。Flutter 是第一个完整 adapter 和 demo target，但 SDK 不是 Flutter-only：Android、iOS、Flutter 和未来 adapter 共享同一套 runtime 行为。因此，可复用逻辑放在 `crates/`，adapter glue 放在 `packages/`，demo-only 代码放在 `examples/`。

第一次阅读建议：

- [`../README.zh-CN.md`](../README.zh-CN.md)：项目入口、快速开始、亮点和文档索引。
- [`sdk-integration.zh-CN.md`](sdk-integration.zh-CN.md)：SDK 构建和接入。
- [`mobile-capabilities.zh-CN.md`](mobile-capabilities.zh-CN.md)：能力模型和扩展方式。
- [`architecture.md`](architecture.md)：详细架构和 ownership boundary。
