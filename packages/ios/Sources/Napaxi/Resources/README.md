`alpine-rootfs.bin` is the lightweight Alpine rootfs consumed by the iOS QEMU
sandbox. Keep the file name stable, but do not use the Android full APK-build
rootfs here.

Bake it with:

```text
./tools/scripts/bake_ios_rootfs.sh
```

The iOS profile includes Python, Node/npm, shell, curl/wget, zip/unzip, and git.
It intentionally excludes Codex CLI, OpenJDK, Android SDK/build-tools,
qemu-x86_64, and the x86_64 sysroot. The shell sandbox capability remains
disabled until the compiled iOS QEMU backend is linked and `NAPAXI_IOS_QEMU` is
defined; the Codex agent-engine capability remains disabled on iOS.
