#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_apk.sh --project-dir <project> [--app-name <name>] [--without-agent-provider] [--validate-only]

Builds exactly one universal, pure-Java Android APK from the fixed Napaxi
project layout. Do not edit this script; pass parameters instead.

Options:
  --project-dir PATH   Android project root containing app/src/main (required)
  --app-name NAME      Final APK basename; defaults to APP_NAME or app
  --android-sdk PATH   Android SDK path; defaults to ANDROID_SDK or /opt/android/sdk
  --x86-sysroot PATH   x86_64 sysroot; defaults to X86_SYSROOT or /opt/x86root/sysroot
  --without-agent-provider
                       Explicitly build without Agent App Provider support
  --validate-only      Validate project/Provider wiring without Android build tools
  -h, --help           Show this help
USAGE
}

PROJECT_DIR="${PROJECT_DIR:-}"
APP_NAME="${APP_NAME:-app}"
ANDROID_SDK="${ANDROID_SDK:-/opt/android/sdk}"
X86_SYSROOT="${X86_SYSROOT:-/opt/x86root/sysroot}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
AGENT_PROVIDER_SDK_DIR="${AGENT_PROVIDER_SDK_DIR:-$SCRIPT_DIR/../sdk/java}"
WITHOUT_AGENT_PROVIDER=false
VALIDATE_ONLY=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ "$#" -ge 2 ] || { echo "--project-dir requires a value" >&2; exit 2; }
      PROJECT_DIR="$2"
      shift 2
      ;;
    --app-name)
      [ "$#" -ge 2 ] || { echo "--app-name requires a value" >&2; exit 2; }
      APP_NAME="$2"
      shift 2
      ;;
    --android-sdk)
      [ "$#" -ge 2 ] || { echo "--android-sdk requires a value" >&2; exit 2; }
      ANDROID_SDK="$2"
      shift 2
      ;;
    --x86-sysroot)
      [ "$#" -ge 2 ] || { echo "--x86-sysroot requires a value" >&2; exit 2; }
      X86_SYSROOT="$2"
      shift 2
      ;;
    --without-agent-provider)
      WITHOUT_AGENT_PROVIDER=true
      shift
      ;;
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  echo "missing required --project-dir" >&2
  usage >&2
  exit 2
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
APP_DIR="$PROJECT_DIR/app"
SRC_DIR="$APP_DIR/src/main"
BUILD_DIR="$PROJECT_DIR/build"
GEN_DIR="$BUILD_DIR/gen"
CLASS_DIR="$BUILD_DIR/classes"
DEX_DIR="$BUILD_DIR/dex"
RES_FLAT_DIR="$BUILD_DIR/res-flat"
APK_WORK_DIR="$BUILD_DIR/apk-work"

BUILD_TOOLS="$ANDROID_SDK/build-tools/33.0.2"
ANDROID_JAR="$ANDROID_SDK/platforms/android-33/android.jar"
MIN_API=26
FINAL_APK="$BUILD_DIR/$APP_NAME.apk"
KEYSTORE="$PROJECT_DIR/debug.keystore"

cleanup_intermediate_outputs() {
  if [ -d "$APK_WORK_DIR" ]; then
    rm -rf "$APK_WORK_DIR" 2>/dev/null || true
  fi
  if [ -d "$BUILD_DIR" ]; then
    find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' ! -path "$FINAL_APK" -delete 2>/dev/null || true
  fi
}
run_x86_64() {
  qemu-x86_64 -L "$X86_SYSROOT" "$@"
}

require_file() {
  if [ ! -f "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_dir() {
  if [ ! -d "$1" ]; then
    echo "missing required directory: $1" >&2
    exit 1
  fi
}

case "$APP_NAME" in
  ''|*/*|*'..'*|*.apk)
    echo "invalid --app-name: use a simple basename without slashes, '..', or .apk" >&2
    exit 2
    ;;
esac

require_file "$SRC_DIR/AndroidManifest.xml"
require_dir "$SRC_DIR/java"
require_dir "$SRC_DIR/res"

if [ -d "$SRC_DIR/assets/www" ] && [ ! -f "$SRC_DIR/assets/www/index.html" ]; then
  echo "WebView assets directory exists but index.html is missing: $SRC_DIR/assets/www/index.html" >&2
  exit 1
fi

PROVIDER_ENABLED=false
if [ -f "$SRC_DIR/assets/agent-app.json" ]; then
  if [ "$WITHOUT_AGENT_PROVIDER" = true ]; then
    echo "--without-agent-provider conflicts with assets/agent-app.json; remove the declaration and Provider manifest entries" >&2
    exit 1
  fi
  PROVIDER_ENABLED=true
elif grep -q 'agent.provider.action.INSTALL_AGENT\|agent.provider.action.HANDLE_PROPOSAL' "$SRC_DIR/AndroidManifest.xml"; then
  echo "AndroidManifest.xml exposes Agent Provider entry points but assets/agent-app.json is missing" >&2
  exit 1
elif [ "$WITHOUT_AGENT_PROVIDER" = true ]; then
  echo "      Agent App Provider explicitly disabled"
else
  echo "      Legacy project without Agent App Provider; new projects enable it by default"
fi

if [ "$PROVIDER_ENABLED" = true ]; then
  if ! grep -q '"provider_id"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"agent_id"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"display_name"' "$SRC_DIR/assets/agent-app.json" || \
     ! grep -q '"actions"' "$SRC_DIR/assets/agent-app.json"; then
    echo "invalid assets/agent-app.json: provider_id, agent_id, display_name, and actions are required" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.action.INSTALL_AGENT' "$SRC_DIR/AndroidManifest.xml" || \
     ! grep -q 'agent.provider.action.HANDLE_PROPOSAL' "$SRC_DIR/AndroidManifest.xml"; then
    echo "AndroidManifest.xml must expose Agent Provider install and action entry points" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.TRUSTED_REFRESH_SUPPORTED' "$SRC_DIR/AndroidManifest.xml"; then
    echo "AndroidManifest.xml must opt in to trusted same-identity Provider refresh" >&2
    exit 1
  fi
  if ! grep -q 'agent.provider.action.GET_DIAGNOSTICS' "$SRC_DIR/AndroidManifest.xml" || \
     ! grep -q 'AgentProviderDiagnosticsInitializer' "$SRC_DIR/AndroidManifest.xml"; then
    echo "      Existing Provider app has no Napaxi diagnostics entry point"
  fi
  if ! grep -R -q 'AgentProviderActionRegistry' "$SRC_DIR/java"; then
    echo "Provider apps must route actions through AgentProviderActionRegistry" >&2
    exit 1
  fi
  DECLARED_ACTION_IDS=()
  while IFS= read -r action_id; do
    DECLARED_ACTION_IDS+=("$action_id")
  done < <(
    sed -n 's/^[[:space:]]*"action_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$SRC_DIR/assets/agent-app.json"
  )
  if [ "${#DECLARED_ACTION_IDS[@]}" -eq 0 ]; then
    echo "assets/agent-app.json must declare at least one action_id" >&2
    exit 1
  fi
  if printf '%s\n' "${DECLARED_ACTION_IDS[@]}" | sort | uniq -d | grep -q .; then
    echo "assets/agent-app.json contains duplicate action_id values" >&2
    exit 1
  fi
  while IFS= read -r confirmation_policy; do
    case "$confirmation_policy" in
      none|provider_required)
        ;;
      provider)
        echo "      Deprecated confirmation_policy 'provider' treated as 'provider_required'; regenerate the manifest" >&2
        ;;
      *)
        echo "invalid confirmation_policy '$confirmation_policy': use 'none' or 'provider_required'" >&2
        exit 1
        ;;
    esac
  done < <(
    sed -n 's/^[[:space:]]*"confirmation_policy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$SRC_DIR/assets/agent-app.json"
  )
  REGISTERED_ACTION_IDS=()
  while IFS= read -r java_source; do
    while IFS= read -r action_id; do
      REGISTERED_ACTION_IDS+=("$action_id")
    done < <(
      sed -n 's/.*\.register[[:space:]]*([[:space:]]*"\([^"]*\)".*/\1/p' "$java_source"
    )
  done < <(find "$SRC_DIR/java" -type f -name '*.java' | sort)
  if [ "${#REGISTERED_ACTION_IDS[@]}" -eq 0 ]; then
    echo "Provider app has no AgentProviderActionRegistry handlers" >&2
    exit 1
  fi
  if printf '%s\n' "${REGISTERED_ACTION_IDS[@]}" | sort | uniq -d | grep -q .; then
    echo "Provider app contains duplicate AgentProviderActionRegistry handlers" >&2
    exit 1
  fi
  for action_id in "${DECLARED_ACTION_IDS[@]}"; do
    registered=false
    for registered_action_id in "${REGISTERED_ACTION_IDS[@]}"; do
      if [ "$registered_action_id" = "$action_id" ]; then
        registered=true
        break
      fi
    done
    if [ "$registered" = false ]; then
      echo "No AgentProviderActionRegistry handler for declared action_id: $action_id" >&2
      exit 1
    fi
  done
  for action_id in "${REGISTERED_ACTION_IDS[@]}"; do
    declared=false
    for declared_action_id in "${DECLARED_ACTION_IDS[@]}"; do
      if [ "$declared_action_id" = "$action_id" ]; then
        declared=true
        break
      fi
    done
    if [ "$declared" = false ]; then
      echo "AgentProviderActionRegistry handler is not declared in agent-app.json: $action_id" >&2
      exit 1
    fi
  done
fi

if [ "$VALIDATE_ONLY" = true ]; then
  echo "Agent App project validation passed"
  exit 0
fi

require_file "$ANDROID_JAR"
require_file "$BUILD_TOOLS/aapt2"
require_file "$BUILD_TOOLS/lib/d8.jar"
require_file "$BUILD_TOOLS/zipalign"
require_file "$BUILD_TOOLS/lib/apksigner.jar"

rm -rf "$BUILD_DIR"
mkdir -p "$GEN_DIR" "$CLASS_DIR" "$DEX_DIR" "$RES_FLAT_DIR" "$APK_WORK_DIR"
trap cleanup_intermediate_outputs EXIT

echo "[1/7] aapt2 compile resources"
run_x86_64 "$BUILD_TOOLS/aapt2" compile --dir "$SRC_DIR/res" -o "$RES_FLAT_DIR"

echo "[2/7] aapt2 link resources and assets"
mapfile -t FLAT_RES < <(find "$RES_FLAT_DIR" -name '*.flat' | sort)
if [ "${#FLAT_RES[@]}" -eq 0 ]; then
  echo "aapt2 produced no .flat resources" >&2
  exit 1
fi
ASSET_ARGS=()
if [ -d "$SRC_DIR/assets" ]; then
  ASSET_ARGS=(-A "$SRC_DIR/assets")
fi
run_x86_64 "$BUILD_TOOLS/aapt2" link \
  -I "$ANDROID_JAR" \
  --manifest "$SRC_DIR/AndroidManifest.xml" \
  --java "$GEN_DIR" \
  --auto-add-overlay \
  "${ASSET_ARGS[@]}" \
  -o "$APK_WORK_DIR/base.zip" \
  "${FLAT_RES[@]}"

echo "[3/7] javac Java sources"
mapfile -t JAVA_SOURCES < <(find "$SRC_DIR/java" "$GEN_DIR" -name '*.java' | sort)
if [ "$PROVIDER_ENABLED" = true ]; then
  require_dir "$AGENT_PROVIDER_SDK_DIR"
  mapfile -t PROVIDER_SDK_SOURCES < <(find "$AGENT_PROVIDER_SDK_DIR" -name '*.java' | sort)
  if [ "${#PROVIDER_SDK_SOURCES[@]}" -eq 0 ]; then
    echo "Agent Provider Lite SDK contains no Java sources: $AGENT_PROVIDER_SDK_DIR" >&2
    exit 1
  fi
  JAVA_SOURCES+=("${PROVIDER_SDK_SOURCES[@]}")
  echo "      Agent App Provider support enabled"
fi
if [ "${#JAVA_SOURCES[@]}" -eq 0 ]; then
  echo "no Java sources found" >&2
  exit 1
fi
javac --release 11 \
  -classpath "$ANDROID_JAR" \
  -d "$CLASS_DIR" \
  "${JAVA_SOURCES[@]}"

echo "[4/7] d8 classes.dex"
mapfile -t CLASS_FILES < <(find "$CLASS_DIR" -name '*.class' | sort)
java -cp "$BUILD_TOOLS/lib/d8.jar" com.android.tools.r8.D8 \
  --min-api "$MIN_API" \
  --lib "$ANDROID_JAR" \
  --output "$DEX_DIR" \
  "${CLASS_FILES[@]}"
require_file "$DEX_DIR/classes.dex"

echo "[5/7] package classes.dex"
cp "$APK_WORK_DIR/base.zip" "$APK_WORK_DIR/unsigned.zip"
(
  cd "$DEX_DIR"
  zip -q -j "$APK_WORK_DIR/unsigned.zip" classes.dex
)

echo "[6/7] zipalign"
run_x86_64 "$BUILD_TOOLS/zipalign" -f -p 4 \
  "$APK_WORK_DIR/unsigned.zip" \
  "$APK_WORK_DIR/aligned.zip"

echo "[7/7] debug sign and verify"
if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storepass android \
    -alias androiddebugkey \
    -keypass android \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

rm -f "$BUILD_DIR"/*.apk
java -jar "$BUILD_TOOLS/lib/apksigner.jar" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias androiddebugkey \
  --ks-pass pass:android \
  --key-pass pass:android \
  --out "$FINAL_APK" \
  "$APK_WORK_DIR/aligned.zip"

java -jar "$BUILD_TOOLS/lib/apksigner.jar" verify --verbose "$FINAL_APK"

cleanup_intermediate_outputs
if [ -e "$APK_WORK_DIR" ]; then
  echo "expected no APK work directory after cleanup: $APK_WORK_DIR" >&2
  exit 1
fi
APK_COUNT=$(find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')
if [ "$APK_COUNT" != "1" ]; then
  echo "expected exactly one final APK in $BUILD_DIR, found $APK_COUNT" >&2
  find "$BUILD_DIR" -maxdepth 1 -type f -name '*.apk' -print >&2
  exit 1
fi
ls -lh "$FINAL_APK"
echo "Build complete: $FINAL_APK"
echo "Signing keystore reused from: $KEYSTORE"
