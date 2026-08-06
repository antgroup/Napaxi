`alpine-rootfs.bin` is the shared baked Alpine rootfs consumed by both Android
and the pending iOS QEMU sandbox. Keep this path aligned with the Android
artifact:

```text
packages/flutter/android/assets/alpine-rootfs.bin
```

The native Swift Package treats the rootfs as ready, but shell/Codex sandbox
capability remains disabled until the compiled iOS QEMU backend is linked and
`NAPAXI_IOS_QEMU` is defined.
