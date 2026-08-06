#!/usr/bin/env bash
# Bake a lightweight Alpine rootfs for the iOS QEMU sandbox.
#
# iOS intentionally does not ship Codex CLI, OpenJDK, Android SDK/build-tools,
# qemu-x86_64, or the x86_64 sysroot. Those belong to the Android offline APK
# build profile and are either too large or not reliable in the iOS QEMU
# backend. The iOS profile keeps only general shell/runtime utilities such as
# Python, Node/npm, curl, bash, zip/unzip, and git.
#
# Usage:
#   ./tools/scripts/bake_ios_rootfs.sh
#       Prune packages/flutter/android/assets/alpine-rootfs.bin into both iOS
#       resource locations.
#   ./tools/scripts/bake_ios_rootfs.sh <input>
#       Use <input> and write packages/ios/Sources/Napaxi/Resources/alpine-rootfs.bin,
#       then mirror to packages/flutter/ios/Resources/alpine-rootfs.bin.
#   ./tools/scripts/bake_ios_rootfs.sh <input> <output>
#       Use <input> and write only <output> unless IOS_FLUTTER_OUTPUT is set.
#
# Downloads are cached under ~/.cache/napaxi/ios-rootfs-bake by default.
# Set BAKE_CACHE_DIR to use a different persistent cache directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDK_DIR="$ROOT_DIR/packages/flutter"

readonly IOS_PACKAGES=(
    python3
    py3-pip
    nodejs
    npm
    curl
    wget
    bash
    zip
    unzip
    git
    ca-certificates
)

readonly REMOVE_PACKAGES=(
    openjdk17-jdk
    openjdk17-jmods
    openjdk17-jre
    openjdk17-jre-headless
    java-cacerts
    java-common
    qemu-x86_64
    gcompat
    zopfli
)

readonly EXPECTED_BINARIES=(
    ./usr/bin/python3
    ./usr/bin/node
    ./usr/bin/npm
    ./usr/bin/curl
    ./usr/bin/wget
    ./bin/bash
    ./usr/bin/zip
    ./usr/bin/unzip
    ./usr/bin/git
)

readonly EXPECTED_ABSENT_PREFIXES=(
    ./usr/bin/codex
    ./usr/lib/node_modules/@openai/codex
    ./usr/bin/java
    ./usr/bin/javac
    ./usr/bin/keytool
    ./usr/bin/qemu-x86_64
    ./usr/lib/jvm
    ./opt/android
    ./opt/x86root
)

DEFAULT_INPUT="$SDK_DIR/android/assets/alpine-rootfs.bin"
DEFAULT_OUTPUT="$ROOT_DIR/packages/ios/Sources/Napaxi/Resources/alpine-rootfs.bin"
DEFAULT_FLUTTER_OUTPUT="$SDK_DIR/ios/Resources/alpine-rootfs.bin"
INPUT="${1:-$DEFAULT_INPUT}"
OUTPUT="${2:-$DEFAULT_OUTPUT}"
MIRROR_OUTPUT="${IOS_FLUTTER_OUTPUT:-}"
if [ $# -lt 2 ]; then
    MIRROR_OUTPUT="$DEFAULT_FLUTTER_OUTPUT"
fi
OUTPUT_TMP="${OUTPUT}.tmp"
CACHE_DIR="${BAKE_CACHE_DIR:-$HOME/.cache/napaxi/ios-rootfs-bake}"

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
if [ -n "$MIRROR_OUTPUT" ]; then
    [ -d "$(dirname "$MIRROR_OUTPUT")" ] || err "Mirror output directory not found: $(dirname "$MIRROR_OUTPUT")"
fi
if [ -e "$OUTPUT_TMP" ]; then
    info "Removing stale temp output: $OUTPUT_TMP"
    rm -f "$OUTPUT_TMP"
fi

docker info >/dev/null 2>&1 || err "Docker daemon is not running. Start Docker/OrbStack first."

mkdir -p "$CACHE_DIR/apk"
CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"

human_size() {
    awk -v bytes="$1" 'BEGIN { printf "%dM", bytes / 1024 / 1024 }'
}

INPUT_SIZE=$(wc -c <"$INPUT" | tr -d '[:space:]')
info "Input:  $INPUT ($(human_size "$INPUT_SIZE"))"
info "Output: $OUTPUT"
[ -n "$MIRROR_OUTPUT" ] && info "Mirror: $MIRROR_OUTPUT"
info "Keeping iOS packages: ${IOS_PACKAGES[*]}"
info "Removing Android/Codex packages: ${REMOVE_PACKAGES[*]}"
info "Using cache: $CACHE_DIR"

WORK="$(mktemp -d "$HOME/.napaxi-bake-ios-rootfs.XXXXXX")"
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
MAJOR="${RELEASE%%.*}"
REST="${RELEASE#*.}"
MINOR="${REST%%.*}"
BRANCH="v${MAJOR}.${MINOR}"
TAG="${MAJOR}.${MINOR}"
APK_CACHE_DIR="$CACHE_DIR/apk/$BRANCH/aarch64"
mkdir -p "$APK_CACHE_DIR"
info "Alpine release $RELEASE -> branch $BRANCH, image alpine:$TAG"

REPO_MAIN="https://mirrors.aliyun.com/alpine/${BRANCH}/main"
REPO_COMMUNITY="https://mirrors.aliyun.com/alpine/${BRANCH}/community"
mkdir -p "$ROOTFS/etc/apk"
printf '%s\n%s\n' "$REPO_MAIN" "$REPO_COMMUNITY" >"$ROOTFS/etc/apk/repositories"

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

info "Installing/refreshing lightweight iOS packages..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    /sbin/apk --root /rootfs --cache-dir /apk-cache \
        --cache-packages --cache-predownload --no-scripts --no-progress \
        add "${IOS_PACKAGES[@]}"

info "Removing Android APK/Codex-heavy packages when present..."
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs" \
    -v "$APK_CACHE_DIR:/apk-cache" \
    "alpine:$TAG" \
    sh -eu -c '
        root=/rootfs
        shift 0
        for pkg do
            if /sbin/apk --root "$root" info -e "$pkg" >/dev/null 2>&1; then
                echo "[INFO] apk del $pkg"
                /sbin/apk --root "$root" --cache-dir /apk-cache --no-scripts --no-progress del "$pkg" || true
            fi
        done
    ' sh "${REMOVE_PACKAGES[@]}"

info "Pruning Codex, Java, Android SDK, qemu-x86_64, and x86root files..."
rm -rf \
    "$ROOTFS/usr/lib/node_modules/@openai/codex" \
    "$ROOTFS/usr/lib/jvm" \
    "$ROOTFS/opt/android" \
    "$ROOTFS/opt/x86root"
rm -f \
    "$ROOTFS/usr/bin/codex" \
    "$ROOTFS/usr/bin/java" \
    "$ROOTFS/usr/bin/javac" \
    "$ROOTFS/usr/bin/keytool" \
    "$ROOTFS/usr/bin/jlink" \
    "$ROOTFS/usr/bin/jmod" \
    "$ROOTFS/usr/bin/qemu-x86_64"
find "$ROOTFS/usr/lib/node_modules/@openai" -type d -empty -delete 2>/dev/null || true

[ -e "$ROOTFS/usr/bin/python3" ] && [ ! -e "$ROOTFS/usr/bin/python" ] && \
    ln -sf python3 "$ROOTFS/usr/bin/python"
[ -e "$ROOTFS/usr/bin/pip3" ] && [ ! -e "$ROOTFS/usr/bin/pip" ] && \
    ln -sf pip3 "$ROOTFS/usr/bin/pip"

info "Validating lightweight iOS rootfs contents..."
for path in "${EXPECTED_BINARIES[@]}"; do
    real_path="$ROOTFS/${path#./}"
    [ -e "$real_path" ] || err "Expected binary missing after iOS bake: $path"
done
for prefix in "${EXPECTED_ABSENT_PREFIXES[@]}"; do
    real_prefix="$ROOTFS/${prefix#./}"
    [ ! -e "$real_prefix" ] || err "Android/Codex-only path remains after iOS bake: $prefix"
done

info "Repacking lightweight iOS rootfs (gzip -9)..."
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT_TMP_BASENAME="$(basename "$OUTPUT_TMP")"
docker run --rm --platform linux/arm64 \
    -v "$ROOTFS:/rootfs:ro" \
    -v "$OUTPUT_DIR:/out" \
    "alpine:$TAG" \
    sh -c 'cd /rootfs && tar -cf - . | gzip -9 >"/out/$1"' \
    sh "$OUTPUT_TMP_BASENAME"

info "Verifying tarball contents..."
for path in "${EXPECTED_BINARIES[@]}"; do
    tar -tzf "$OUTPUT_TMP" "$path" >/dev/null || err "Output rootfs missing expected path: $path"
done
for prefix in "${EXPECTED_ABSENT_PREFIXES[@]}"; do
    if tar -tzf "$OUTPUT_TMP" | grep -F -x "$prefix" >/dev/null || tar -tzf "$OUTPUT_TMP" | grep -F "${prefix%/}/" >/dev/null; then
        err "Output rootfs still contains Android/Codex-only path: $prefix"
    fi
done

mv "$OUTPUT_TMP" "$OUTPUT"
OUTPUT_SIZE=$(wc -c <"$OUTPUT" | tr -d '[:space:]')
info "Wrote $OUTPUT ($(human_size "$OUTPUT_SIZE"))"

if [ -n "$MIRROR_OUTPUT" ] && [ "$MIRROR_OUTPUT" != "$OUTPUT" ]; then
    cp "$OUTPUT" "$MIRROR_OUTPUT"
    info "Mirrored lightweight iOS rootfs to $MIRROR_OUTPUT"
fi
