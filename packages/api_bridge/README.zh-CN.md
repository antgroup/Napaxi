# Napaxi API Bridge

`packages/api_bridge` 是把 `napaxi_core::api` 暴露给平台 adapter 的 Rust FFI bridge。

它生成 `libnapaxi_api_bridge`，供 Flutter Rust Bridge、Android JNI 和 iOS Swift Package adapter 链接。

## 组成

- `c_api/`：`extern "C"` API，接收 engine handle 和 JSON 字符串，返回标准 result envelope。Android JNI 和 iOS Swift adapter 使用这一层。
- `bridge/`：Flutter Rust Bridge 使用的 typed bridge surface。
- `generated/`：codegen 输出，不手动编辑。

## 安全保证

- 每个 `unsafe` block 都需要 `// SAFETY:` 注释。
- `extern "C"` entrypoint 包在 `catch_unwind` 中，panic 会转成结构化 error envelope。
- C string helper 会处理 null pointer 和 interior NUL。
- 释放函数有明确 ownership contract，调用方必须拥有 pointer。

## Wire format

成功：

```json
{ "ok": true, "value": {} }
```

失败：

```json
{ "ok": false, "error": { "code": "<stable-code>", "message": "<human-readable>" } }
```

错误码见 [`../../docs/api-contract.zh-CN.md`](../../docs/api-contract.zh-CN.md)。

## 构建与测试

```sh
cargo test -p napaxi_api_bridge
cargo build -p napaxi_api_bridge --release
./tools/scripts/build.sh fast android
./tools/scripts/build.sh fast ios
```

## 相关包

- [`../../crates/core`](../../crates/core/)：提供 `napaxi_core::api` 的 runtime kernel。
- [`../flutter`](../flutter/)：Flutter adapter。
- [`../android`](../android/)：Android adapter。
- [`../ios`](../ios/)：iOS adapter。
