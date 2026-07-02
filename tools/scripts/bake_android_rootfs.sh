#!/usr/bin/env bash
# Bake a curated set of Alpine packages into the Android sandbox rootfs
# (packages/flutter/android/assets/alpine-rootfs.bin) so the sandbox ships
# common dev tools (python3, nodejs, npm, curl, bash, zip, git) offline instead of
# installing them on demand from the environment panel.
#
# The rootfs is a clean busybox Alpine aarch64 base provided externally. This
# script enriches it reproducibly with Docker (OrbStack on macOS works): drop a
# fresh clean base at the asset path (or pass it as <input>) and re-run.
#
# Requires Docker with linux/arm64 support (native on Apple Silicon, emulated
# elsewhere) and host tar/gzip. The Alpine version is read from the rootfs so
# the in-container apk matches the rootfs apk database.
#
# Usage:
#   ./tools/scripts/bake_android_rootfs.sh                   # enrich the committed asset in place
#   ./tools/scripts/bake_android_rootfs.sh <input>           # enrich <input>, overwrite it
#   ./tools/scripts/bake_android_rootfs.sh <input> <output>  # enrich <input> into <output>
#
# Edit BAKE_PACKAGES below to add or remove tools.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SDK_DIR="$ROOT_DIR/packages/flutter"

# Packages to bake in. Add or remove here; the script picks up changes on the
# next run. Mirrors the old iOS iSH rootfs toolset (python3, node, npm, curl,
# bash, zip, git) that the clean Android base lacks. `git` enables the native
# sandbox-git execution path (PlatformLlmConfig.git.mode = "native").
readonly BAKE_PACKAGES=(
    python3
    py3-pip
    nodejs
    npm
    curl
    bash
    zip
    git
)

# Binaries asserted present after baking (sanity check). Paths match tar entry
# names (./-prefixed) produced by `tar -cf - -C <rootfs> .`.
readonly EXPECTED_BINARIES=(
    ./usr/bin/python3
    ./usr/bin/node
    ./usr/bin/npm
    ./usr/bin/curl
    ./bin/bash
    ./usr/bin/zip
    ./usr/bin/git
)

DEFAULT_ASSET="$SDK_DIR/android/assets/alpine-rootfs.bin"
INPUT="${1:-$DEFAULT_ASSET}"
OUTPUT="${2:-$INPUT}"

info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || err "$1 not found"
}

require_command tar
require_command gzip
require_command docker

[ -f "$INPUT" ] || err "Input rootfs not found: $INPUT"
docker info >/dev/null 2>&1 || err "Docker daemon is not running. Start Docker/OrbStack first."

human_size() {
    awk -v bytes="$1" 'BEGIN { printf "%dM", bytes / 1024 / 1024 }'
}

INPUT_SIZE=$(wc -c <"$INPUT" | tr -d '[:space:]')
info "Input:  $INPUT ($(human_size "$INPUT_SIZE"))"
info "Baking: ${BAKE_PACKAGES[*]}"

# Keep the work dir under $HOME so Docker/Colima on macOS can bind-mount it
# into the VM. The default mktemp dir under /var/folders is not shared into
# Colima/Docker Desktop VMs, which breaks the `-v "$ROOTFS:/rootfs"` mount.
WORK="$(mktemp -d "$HOME/.napaxi-bake-rootfs.XXXXXX")"
cleanup() {
    rm -rf "$WORK"
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
info "Alpine release $RELEASE -> branch $BRANCH, image alpine:$TAG"

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
    "alpine:$TAG" \
    /sbin/apk --root /rootfs --no-cache --no-scripts --no-progress \
        add "${BAKE_PACKAGES[@]}"

# Provide unversioned python/pip symlinks to match the iOS rootfs layout.
[ -e "$ROOTFS/usr/bin/python3" ] && [ ! -e "$ROOTFS/usr/bin/python" ] && \
    ln -sf python3 "$ROOTFS/usr/bin/python"
[ -e "$ROOTFS/usr/bin/pip3" ] && [ ! -e "$ROOTFS/usr/bin/pip" ] && \
    ln -sf pip3 "$ROOTFS/usr/bin/pip"

info "Repacking rootfs (gzip -9)..."
OUTPUT_TMP="${OUTPUT}.tmp"
# Pipe through gzip explicitly for max compression and portable behavior across
# GNU tar and bsdtar (macOS). Runtime extraction ignores ownership metadata, so
# no owner/group normalization is needed.
tar -C "$ROOTFS" -cf - . | gzip -9 >"$OUTPUT_TMP"
mv "$OUTPUT_TMP" "$OUTPUT"

info "Verifying baked binaries..."
MISSING=()
for bin in "${EXPECTED_BINARIES[@]}"; do
    tar -tzf "$OUTPUT" | grep -qx "$bin" || MISSING+=("$bin")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
    err "Verification failed; missing: ${MISSING[*]}"
fi

OUTPUT_SIZE=$(wc -c <"$OUTPUT" | tr -d '[:space:]')
info "Output: $OUTPUT ($(human_size "$OUTPUT_SIZE"), was $(human_size "$INPUT_SIZE"))"
info "Done."
