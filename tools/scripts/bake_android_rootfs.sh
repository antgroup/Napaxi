#!/usr/bin/env bash
# Bake a curated set of Alpine packages into the Android sandbox rootfs
# (packages/flutter/android/assets/alpine-rootfs.bin) so the sandbox ships
# common dev tools (python3, nodejs, npm, curl, bash, zip, OpenJDK 17,
# qemu-x86_64, the minimal Android APK build-tools/platform jar, and the
# x86_64 runtime library closure required by aapt2/zipalign) offline instead of
# installing them on demand from the environment panel.
#
# The rootfs is a clean busybox Alpine aarch64 base provided externally. This
# script enriches it reproducibly with Docker (OrbStack on macOS works): drop a
# fresh clean base at the asset path (or pass it as <input>) and re-run.
#
# Requires Docker with linux/arm64 support (native on Apple Silicon, emulated
# elsewhere) and host tar for extraction/verification. Repacking runs inside
# Docker so the output uses Linux tar/gzip consistently across host platforms.
# The Alpine version is read from the rootfs so the in-container apk matches
# the rootfs apk database.
#
# Usage:
#   ./tools/scripts/bake_android_rootfs.sh                   # enrich the committed asset in place
#   ./tools/scripts/bake_android_rootfs.sh <input>           # enrich <input>, overwrite it
#   ./tools/scripts/bake_android_rootfs.sh <input> <output>  # enrich <input> into <output>
#
# Downloads are cached under ~/.cache/napaxi/android-rootfs-bake by default.
# Set BAKE_CACHE_DIR to use a different persistent cache directory.
#
# Edit BAKE_PACKAGES below to add or remove tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDK_DIR="$ROOT_DIR/packages/flutter"

# Packages to bake in. Add or remove here; the script picks up changes on the
# next run. Mirrors the general-purpose part of the old iOS iSH rootfs toolset
# (python3, node, npm, curl, bash, zip) that the clean Android base lacks.
# OpenJDK and qemu support the offline Android APK build pipeline.
readonly BAKE_PACKAGES=(
    python3
    py3-pip
    nodejs
    npm
    curl
    bash
    zip
    unzip
    qemu-x86_64
    gcompat
    libstdc++
    libgcc
    zlib
    zopfli
)

readonly OPENJDK_PACKAGE=openjdk17-jdk
readonly ANDROID_BUILD_TOOLS_VERSION=33.0.2
readonly ANDROID_PLATFORM_API=33
readonly UBUNTU_SYSROOT_VERSION=22.04
readonly ANDROID_BUILD_TOOLS_URL="https://dl.google.com/android/repository/build-tools_r33.0.2-linux.zip"
readonly ANDROID_PLATFORM_URL="https://dl.google.com/android/repository/platform-33_r02.zip"
readonly UBUNTU_SYSROOT_URL="https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz"
readonly ANDROID_BUILD_TOOLS_SHA256="ff19ccbe3a5098b5dd10722063ebcd40218a30d23b50133e386fc39ea5240e79"
readonly ANDROID_PLATFORM_SHA256="f851b13fe89f8510a1250df5e8593e86176b2428f4f3cbe0e304a85818c07bc8"
readonly UBUNTU_SYSROOT_SHA256="df6fe77cee11bd216ac532f0ee082bdc4da3c0cc1f1d9cb20f3f743196bc4b07"

# Binaries asserted present after baking (sanity check). Paths match tar entry
# names (./-prefixed) produced by `tar -cf - -C <rootfs> .`.
readonly EXPECTED_BINARIES=(
    ./usr/bin/python3
    ./usr/bin/node
    ./usr/bin/npm
    ./usr/bin/curl
    ./bin/bash
    ./usr/bin/zip
    ./usr/bin/unzip
    ./usr/bin/java
    ./usr/bin/javac
    ./usr/bin/keytool
    ./usr/bin/qemu-x86_64
    ./opt/android/sdk/build-tools/33.0.2/aapt2
    ./opt/android/sdk/build-tools/33.0.2/d8
    ./opt/android/sdk/build-tools/33.0.2/apksigner
    ./opt/android/sdk/build-tools/33.0.2/zipalign
    ./opt/android/sdk/build-tools/33.0.2/lib/d8.jar
    ./opt/android/sdk/build-tools/33.0.2/lib/apksigner.jar
    ./opt/android/sdk/build-tools/33.0.2/lib64/libc++.so
    ./opt/android/sdk/build-tools/33.0.2/lib64/libc++.so.1
    ./opt/android/sdk/platforms/android-33/android.jar
    ./opt/x86root/sysroot/lib
    ./opt/x86root/sysroot/lib64/ld-linux-x86-64.so.2
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/libc.so.6
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/libdl.so.2
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/libgcc_s.so.1
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/libm.so.6
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/libpthread.so.0
    ./opt/x86root/sysroot/usr/lib/x86_64-linux-gnu/librt.so.1
)

readonly EXPECTED_ABSENT_PREFIXES=(
    ./usr/bin/git
    ./usr/lib/jvm/java-17-openjdk/jmods
    ./usr/lib/jvm/java-17-openjdk/bin/jlink
    ./usr/lib/jvm/java-17-openjdk/bin/jmod
    ./opt/android/sdk/build-tools/33.0.2/aidl
    ./opt/android/sdk/build-tools/33.0.2/lld-bin
    ./opt/android/sdk/build-tools/33.0.2/renderscript
    ./opt/android/sdk/platforms/android-33/data
    ./opt/x86root/sysroot/usr/bin
)

DEFAULT_ASSET="$SDK_DIR/android/assets/alpine-rootfs.bin"
INPUT="${1:-$DEFAULT_ASSET}"
OUTPUT="${2:-$INPUT}"
OUTPUT_TMP="${OUTPUT}.tmp"
CACHE_DIR="${BAKE_CACHE_DIR:-$HOME/.cache/napaxi/android-rootfs-bake}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

require_command tar
require_command docker

[ -f "$INPUT" ] || err "Input rootfs not found: $INPUT"
OUTPUT_PARENT="$(dirname "$OUTPUT")"
[ -d "$OUTPUT_PARENT" ] || err "Output directory not found: $OUTPUT_PARENT"
OUTPUT_DIR="$(cd "$OUTPUT_PARENT" && pwd)"
OUTPUT_TMP_BASENAME="$(basename "$OUTPUT_TMP")"
if [ -e "$OUTPUT_TMP" ]; then
    info "Removing stale temp output: $OUTPUT_TMP"
    rm -f "$OUTPUT_TMP"
fi

docker info >/dev/null 2>&1 || err "Docker daemon is not running. Start Docker/OrbStack first."

mkdir -p "$CACHE_DIR/downloads"
CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
DOWNLOAD_CACHE_DIR="$CACHE_DIR/downloads"

human_size() {
    awk -v bytes="$1" 'BEGIN { printf "%dM", bytes / 1024 / 1024 }'
}

INPUT_SIZE=$(wc -c <"$INPUT" | tr -d '[:space:]')
info "Input:  $INPUT ($(human_size "$INPUT_SIZE"))"
info "Baking APK packages: ${BAKE_PACKAGES[*]}"
info "Baking OpenJDK package: $OPENJDK_PACKAGE"
info "Using download cache: $CACHE_DIR"

# Keep the work dir under $HOME so Docker/Colima on macOS can bind-mount it
# into the VM. The default mktemp dir under /var/folders is not shared into
# Colima/Docker Desktop VMs, which breaks the `-v "$ROOTFS:/rootfs"` mount.
WORK="$(mktemp -d "$HOME/.napaxi-bake-rootfs.XXXXXX")"
cleanup() {
    local status=$?
    rm -rf "$WORK"
    if [ "$status" -ne 0 ] && [ -e "$OUTPUT_TMP" ]; then
        warn "Removing failed temp output: $OUTPUT_TMP"
        rm -f "$OUTPUT_TMP"
    fi
}
trap cleanup EXIT

ROOTFS="$WORK/rootfs"
mkdir -p "$ROOTFS"
info "Extracting rootfs..."
tar -C "$ROOTFS" -xzf "$INPUT"

RELEASE_FILE="$ROOTFS/etc/alpine-release"
[ -f "$RELEASE_FILE" ] || err "Not an Alpine rootfs: missing etc/alpine-release"
RELEASE="$(tr -d '[:space:]' <"$RELEASE_FILE")"
# 3.23.4 -> major=3 minor=23 -> branch v3.23, image tag 3.23
MAJOR="${RELEASE%%.*}"
REST="${RELEASE#*.}"
MINOR="${REST%%.*}"
BRANCH="v${MAJOR}.${MINOR}"
TAG="${MAJOR}.${MINOR}"
APK_CACHE_DIR="$CACHE_DIR/apk/$BRANCH/aarch64"
mkdir -p "$APK_CACHE_DIR"
info "Alpine release $RELEASE -> branch $BRANCH, image alpine:$TAG"

info "Checking cached APK integrity..."
docker run --rm --platform linux/arm64 \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    sh -eu -c '
        for package in /apk-cache/*.apk; do
            [ -e "$package" ] || break
            if ! apk verify "$package" >/dev/null 2>&1; then
                echo "[WARN] Removing invalid cached APK: $(basename "$package")" >&2
                rm -f "$package"
            fi
        done
    '

# Pin the apk repositories to the aliyun mirror (matches the runtime mirror in
# crates/core/src/platform/android_linux_env.rs::configure_apk_mirror) so the
# bake uses the same source the device will use, and no stale base repositories
# leak through.
REPO_MAIN="https://mirrors.aliyun.com/alpine/${BRANCH}/main"
REPO_COMMUNITY="https://mirrors.aliyun.com/alpine/${BRANCH}/community"
mkdir -p "$ROOTFS/etc/apk"
printf '%s\n%s\n' "$REPO_MAIN" "$REPO_COMMUNITY" >"$ROOTFS/etc/apk/repositories"

info "Installing packages via Docker (linux/arm64)..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    /sbin/apk --root /rootfs --cache-dir /apk-cache \
        --cache-packages --cache-predownload --no-scripts --no-progress \
        add "${BAKE_PACKAGES[@]}"

# Provide unversioned python/pip symlinks to match the iOS rootfs layout.
[ -e "$ROOTFS/usr/bin/python3" ] && [ ! -e "$ROOTFS/usr/bin/python" ] && \
    ln -sf python3 "$ROOTFS/usr/bin/python"
[ -e "$ROOTFS/usr/bin/pip3" ] && [ ! -e "$ROOTFS/usr/bin/pip" ] && \
    ln -sf pip3 "$ROOTFS/usr/bin/pip"

# Install the JDK package directly instead of the heavier `openjdk17` meta
# package. Keep this separate from the small tool package set because OpenJDK is
# large and benefits from its own progress boundary. We intentionally use
# --no-scripts for deterministic offline rootfs baking, then create the command
# launchers explicitly below so java/javac/keytool work without apk trigger state.
info "Installing OpenJDK via apk in rootfs..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    /sbin/apk --root /rootfs --cache-dir /apk-cache \
        --cache-packages --cache-predownload --no-scripts --no-progress \
        add "$OPENJDK_PACKAGE"

# The default input is the previously baked asset, so removing a package from
# BAKE_PACKAGES alone would leave it in subsequent outputs. Explicitly prune
# Git while retaining curl and unzip as general-purpose sandbox tools.
info "Removing Git from the rootfs..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    sh -eu -c '
        if /sbin/apk --root /rootfs info -e git >/dev/null 2>&1; then
            /sbin/apk --root /rootfs --cache-dir /apk-cache \
                --no-scripts --no-progress del git
        fi
        test ! -e /rootfs/usr/bin/git
    '

JAVA_HOME="$ROOTFS/usr/lib/jvm/java-17-openjdk"
[ -x "$JAVA_HOME/bin/java" ] || err "OpenJDK install did not produce $JAVA_HOME/bin/java"
[ -x "$JAVA_HOME/bin/javac" ] || err "OpenJDK install did not produce $JAVA_HOME/bin/javac"
[ -x "$JAVA_HOME/bin/keytool" ] || err "OpenJDK install did not produce $JAVA_HOME/bin/keytool"
for java_command in java javac keytool; do
    launcher="$ROOTFS/usr/bin/$java_command"
    rm -f "$launcher"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' 'JAVA_HOME=/usr/lib/jvm/java-17-openjdk'
        printf '%s\n' 'export JAVA_HOME'
        printf '%s\n' 'export LD_LIBRARY_PATH="$JAVA_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
        printf 'exec "$JAVA_HOME/bin/%s" "$@"\n' "$java_command"
    } >"$launcher"
    chmod 0755 "$launcher"
done

# openjdk17-jdk depends on the jmods package, so apk must install/cache it to
# resolve the JDK consistently. The APK build pipeline only uses java, javac,
# and keytool; remove jmods and their launchers from the final rootfs while
# leaving the verified APK cache untouched for future full-JDK builds.
info "Pruning OpenJDK modules not used by APK builds..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    "alpine:$TAG" \
    sh -eu -c '
        java_home=/rootfs/usr/lib/jvm/java-17-openjdk
        rm -rf "$java_home/jmods"
        rm -f "$java_home/bin/jlink" "$java_home/bin/jmod"
        rm -f /rootfs/usr/bin/jlink /rootfs/usr/bin/jmod
    '

info "Baking Android SDK build-tools/platform and Ubuntu x86_64 sysroot..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    -v "$DOWNLOAD_CACHE_DIR:/downloads" \
    -e "ANDROID_BUILD_TOOLS_VERSION=$ANDROID_BUILD_TOOLS_VERSION" \
    -e "ANDROID_PLATFORM_API=$ANDROID_PLATFORM_API" \
    -e "UBUNTU_SYSROOT_VERSION=$UBUNTU_SYSROOT_VERSION" \
    -e "ANDROID_BUILD_TOOLS_URL=$ANDROID_BUILD_TOOLS_URL" \
    -e "ANDROID_PLATFORM_URL=$ANDROID_PLATFORM_URL" \
    -e "UBUNTU_SYSROOT_URL=$UBUNTU_SYSROOT_URL" \
    -e "ANDROID_BUILD_TOOLS_SHA256=$ANDROID_BUILD_TOOLS_SHA256" \
    -e "ANDROID_PLATFORM_SHA256=$ANDROID_PLATFORM_SHA256" \
    -e "UBUNTU_SYSROOT_SHA256=$UBUNTU_SYSROOT_SHA256" \
    "alpine:$TAG" \
    sh -eu -c '
        apk --repositories-file /dev/null \
            --repository "$1" --repository "$2" --cache-dir /apk-cache \
            --cache-packages --cache-predownload --no-progress \
            add ca-certificates curl tar gzip unzip

        android_root=/rootfs/opt/android
        sdk_root="$android_root/sdk"
        build_tools_dir="$sdk_root/build-tools/$ANDROID_BUILD_TOOLS_VERSION"
        platform_dir="$sdk_root/platforms/android-$ANDROID_PLATFORM_API"
        x86root_dir=/rootfs/opt/x86root
        sysroot_dir="$x86root_dir/sysroot"

        mkdir -p "$android_root" "$sdk_root/build-tools" "$sdk_root/platforms" "$x86root_dir"

        verify_archive() {
            archive_path="$1"
            expected_sha256="$2"
            archive_type="$3"

            [ -f "$archive_path" ] || return 1
            printf "%s  %s\n" "$expected_sha256" "$archive_path" \
                | sha256sum -c - >/dev/null 2>&1 || return 1
            case "$archive_type" in
                zip) unzip -tqq "$archive_path" >/dev/null 2>&1 ;;
                tar.gz) tar -tzf "$archive_path" >/dev/null 2>&1 ;;
                *) echo "[ERROR] Unknown archive type: $archive_type" >&2; return 1 ;;
            esac
        }

        download_cached() {
            cache_path="$1"
            url="$2"
            expected_sha256="$3"
            archive_type="$4"
            partial_path="$cache_path.part"

            if verify_archive "$cache_path" "$expected_sha256" "$archive_type"; then
                echo "[INFO] Using cached $(basename "$cache_path")"
                return
            fi

            if [ -e "$cache_path" ]; then
                echo "[WARN] Discarding invalid cache: $(basename "$cache_path")" >&2
                rm -f "$cache_path"
            fi

            echo "[INFO] Downloading $(basename "$cache_path")"
            if [ -s "$partial_path" ]; then
                if ! curl -fL --retry 3 --connect-timeout 20 --speed-time 30 \
                    --speed-limit 102400 -C - -o "$partial_path" "$url"; then
                    rm -f "$partial_path"
                fi
            fi
            if [ ! -s "$partial_path" ]; then
                curl -fL --retry 3 --connect-timeout 20 --speed-time 30 \
                    --speed-limit 102400 -o "$partial_path" "$url"
            fi

            if ! verify_archive "$partial_path" "$expected_sha256" "$archive_type"; then
                echo "[WARN] Download failed integrity check; retrying from scratch" >&2
                rm -f "$partial_path"
                curl -fL --retry 3 --connect-timeout 20 --speed-time 30 \
                    --speed-limit 102400 -o "$partial_path" "$url"
                if ! verify_archive "$partial_path" "$expected_sha256" "$archive_type"; then
                    rm -f "$partial_path"
                    echo "[ERROR] Downloaded archive failed integrity check: $(basename "$cache_path")" >&2
                    exit 1
                fi
            fi
            mv "$partial_path" "$cache_path"
        }

        build_tools_ready() {
            test -x "$build_tools_dir/aapt2" \
                && test -x "$build_tools_dir/d8" \
                && test -x "$build_tools_dir/apksigner" \
                && test -x "$build_tools_dir/zipalign" \
                && test -f "$build_tools_dir/lib/d8.jar" \
                && test -f "$build_tools_dir/lib/apksigner.jar" \
                && test -f "$build_tools_dir/lib64/libc++.so" \
                && test -f "$build_tools_dir/lib64/libc++.so.1"
        }

        if ! build_tools_ready; then
            build_tools_archive="/downloads/build-tools_r${ANDROID_BUILD_TOOLS_VERSION}-linux.zip"
            rm -rf "$android_root/.bt_dir" "$build_tools_dir"
            download_cached "$build_tools_archive" "$ANDROID_BUILD_TOOLS_URL" \
                "$ANDROID_BUILD_TOOLS_SHA256" zip
            unzip -q "$build_tools_archive" -d "$android_root/.bt_dir"
            mv "$android_root/.bt_dir/android-13" "$build_tools_dir"
            rm -rf "$android_root/.bt_dir"
        fi

        if [ ! -f "$platform_dir/android.jar" ]; then
            platform_archive="/downloads/platform-${ANDROID_PLATFORM_API}_r02.zip"
            rm -rf "$android_root/.platform_dir" "$platform_dir"
            download_cached "$platform_archive" "$ANDROID_PLATFORM_URL" \
                "$ANDROID_PLATFORM_SHA256" zip
            unzip -q "$platform_archive" -d "$android_root/.platform_dir"
            mv "$android_root/.platform_dir/android-13" "$platform_dir"
            rm -rf "$android_root/.platform_dir"
        fi

        sysroot_ready() {
            test -f "$sysroot_dir/lib64/ld-linux-x86-64.so.2" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/libc.so.6" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/libdl.so.2" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/libgcc_s.so.1" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/libm.so.6" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/libpthread.so.0" \
                && test -f "$sysroot_dir/usr/lib/x86_64-linux-gnu/librt.so.1"
        }

        if ! sysroot_ready; then
            ubuntu_archive="/downloads/ubuntu-base-${UBUNTU_SYSROOT_VERSION}-amd64.tar.gz"
            sysroot_tmp="/tmp/napaxi-ubuntu-sysroot"
            rm -rf "$sysroot_dir"
            rm -rf "$sysroot_tmp"
            mkdir -p "$sysroot_tmp"
            download_cached "$ubuntu_archive" "$UBUNTU_SYSROOT_URL" \
                "$UBUNTU_SYSROOT_SHA256" tar.gz
            # Extract outside the host bind mount first. Ubuntu base contains
            # absolute symlinks under /etc/alternatives and /lib64; busybox
            # tar can otherwise follow them through the bind mount.
            tar -xzf "$ubuntu_archive" -C "$sysroot_tmp"
            mkdir -p "$sysroot_dir"
            cp -a "$sysroot_tmp/." "$sysroot_dir/"
            if [ -L "$sysroot_dir/lib64" ]; then
                rm "$sysroot_dir/lib64"
            fi
            mkdir -p "$sysroot_dir/lib64"
            cp "$sysroot_dir/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" \
                "$sysroot_dir/lib64/ld-linux-x86-64.so.2"
        fi

        # Keep only the files used by the bundled android-apk-build pipeline.
        build_tools_min="$android_root/.build-tools-min"
        rm -rf "$build_tools_min"
        mkdir -p "$build_tools_min/lib" "$build_tools_min/lib64"
        cp -a "$build_tools_dir/aapt2" "$build_tools_min/aapt2"
        cp -a "$build_tools_dir/d8" "$build_tools_min/d8"
        cp -a "$build_tools_dir/apksigner" "$build_tools_min/apksigner"
        cp -a "$build_tools_dir/zipalign" "$build_tools_min/zipalign"
        cp -a "$build_tools_dir/lib/d8.jar" "$build_tools_min/lib/d8.jar"
        cp -a "$build_tools_dir/lib/apksigner.jar" "$build_tools_min/lib/apksigner.jar"
        cp -a "$build_tools_dir/lib64/libc++.so" "$build_tools_min/lib64/libc++.so"
        cp -a "$build_tools_dir/lib64/libc++.so.1" "$build_tools_min/lib64/libc++.so.1"
        rm -rf "$build_tools_dir"
        mv "$build_tools_min" "$build_tools_dir"

        platform_min="$android_root/.platform-min"
        rm -rf "$platform_min"
        mkdir -p "$platform_min"
        cp -a "$platform_dir/android.jar" "$platform_min/android.jar"
        rm -rf "$platform_dir"
        mv "$platform_min" "$platform_dir"

        sysroot_min="$x86root_dir/.sysroot-min"
        rm -rf "$sysroot_min"
        mkdir -p "$sysroot_min/lib64" "$sysroot_min/usr/lib/x86_64-linux-gnu"
        ln -s usr/lib "$sysroot_min/lib"
        cp -a "$sysroot_dir/lib64/ld-linux-x86-64.so.2" "$sysroot_min/lib64/"
        for library in libc.so.6 libdl.so.2 libgcc_s.so.1 libm.so.6 libpthread.so.0 librt.so.1; do
            cp -a "$sysroot_dir/usr/lib/x86_64-linux-gnu/$library" \
                "$sysroot_min/usr/lib/x86_64-linux-gnu/$library"
        done
        rm -rf "$sysroot_dir"
        mv "$sysroot_min" "$sysroot_dir"

        build_tools_ready
        test -f "$platform_dir/android.jar"
        sysroot_ready
    ' sh "$REPO_MAIN" "$REPO_COMMUNITY"

info "Validating baked APK toolchain executables..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    "alpine:$TAG" \
    chroot /rootfs /bin/sh -eu -c '
        python3 --version
        node --version
        npm --version
        curl --version >/dev/null
        unzip -v >/dev/null
        java -version
        javac -version
        keytool -help >/dev/null 2>&1
        qemu-x86_64 --version >/dev/null
        qemu-x86_64 -L /opt/x86root/sysroot \
            /opt/android/sdk/build-tools/33.0.2/aapt2 version
        zipalign_help="$(qemu-x86_64 -L /opt/x86root/sysroot \
            /opt/android/sdk/build-tools/33.0.2/zipalign -h 2>&1 || true)"
        test -n "$zipalign_help"
        /opt/android/sdk/build-tools/33.0.2/d8 --version
        /opt/android/sdk/build-tools/33.0.2/apksigner --version
    '

info "Repacking rootfs in Docker (gzip -9)..."
# Repack inside Linux instead of relying on host bsdtar/gzip behavior. This keeps
# the generated rootfs stable on macOS/Linux hosts and avoids host-specific
# metadata/resource issues. Runtime extraction ignores ownership metadata, so no
# owner/group normalization is needed.
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs:ro" \
    -v "$OUTPUT_DIR:/out" \
    "alpine:$TAG" \
    sh -c 'cd /rootfs && tar -cf - . | gzip -9 >"/out/$1"' \
    sh "$OUTPUT_TMP_BASENAME"
mv "$OUTPUT_TMP" "$OUTPUT"

info "Verifying baked binaries..."
ARCHIVE_LIST="$WORK/archive.list"
tar -tzf "$OUTPUT" >"$ARCHIVE_LIST"
MISSING=()
for bin in "${EXPECTED_BINARIES[@]}"; do
    grep -Fqx -- "$bin" "$ARCHIVE_LIST" || MISSING+=("$bin")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    err "Verification failed; missing: ${MISSING[*]}"
fi
for excluded_prefix in "${EXPECTED_ABSENT_PREFIXES[@]}"; do
    if grep -Fq -- "$excluded_prefix" "$ARCHIVE_LIST"; then
        err "Verification failed; excluded content is still present: $excluded_prefix"
    fi
done

OUTPUT_SIZE=$(wc -c <"$OUTPUT" | tr -d '[:space:]')
info "Output: $OUTPUT ($(human_size "$OUTPUT_SIZE"), was $(human_size "$INPUT_SIZE"))"
info "Done."
