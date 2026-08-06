# 第三方许可证

Napaxi 源码采用 GPL-3.0-or-later，详见 [`LICENSE`](LICENSE)。但分发的移动 SDK 会包含第三方原生运行时组件，其中包括 GPL/LGPL 组件。英文原文见 [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md)。

## 组件概览

| 组件 | 位置 | 许可证 | 说明 |
| --- | --- | --- | --- |
| PRoot 5.1.0 | `packages/flutter/android/jniLibs/arm64-v8a/libproot.so` | GPL-2.0-only | Android sandbox 相关执行组件。 |
| Samba talloc | `packages/flutter/android/assets/libtalloc.so.2` | LGPL-3.0-or-later | 动态库。 |
| musl libc loader | `packages/flutter/android/jniLibs/arm64-v8a/libldmusl.so` | MIT | 动态 loader。 |
| Alpine minirootfs | `packages/flutter/android/assets/alpine-rootfs.bin`、`packages/ios/Sources/Napaxi/Resources/alpine-rootfs.bin` | mixed | rootfs 内各包按各自许可证。 |
| `libloader.so` | `packages/flutter/android/jniLibs/arm64-v8a/libloader.so` | GPL-3.0-or-later | Napaxi 第一方 sandbox loader shim。 |

Android runtime binary 的来源、hash 与完整说明见：

- [`packages/flutter/android/jniLibs/THIRD-PARTY.md`](packages/flutter/android/jniLibs/THIRD-PARTY.md)

iOS QEMU runtime 产物尚未入仓；落地后需要在这里补充来源、hash 和许可证。

## Copyleft 义务

PRoot、talloc 等 GPL/LGPL 组件要求分发方提供对应源码或源码获取方式。Napaxi 记录了这些组件的上游来源；下游 App 在分发包含 Napaxi SDK 的产物时，也需要满足自身分发场景下的许可证义务。

这份说明不是法律意见。商业或公开分发前，请结合目标应用、链接方式、应用商店要求和公司合规流程进行法律审查。

## 实务建议

- 发布前确认 Git LFS 资产已完整拉取。
- 不要删除 `NOTICE`、`THIRD-PARTY-LICENSES.md` 和各平台 `THIRD-PARTY.md`。
- 在面向用户或客户的分发包中保留第三方许可证说明。
- 如果替换、修改或升级第三方 binary，同步更新 hash、版本、来源和许可证。
