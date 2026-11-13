#!/usr/bin/env bash
# Layer 2 gate: boot the Android emulator, install the demo app debug APK,
# and run the Maestro smoke flows under examples/flutter/.maestro/.
#
# Usage:
#   tools/scripts/layer2_maestro_smoke.sh [--skip-build] [--avd <name>]
#
# Env:
#   ANDROID_HOME   Android SDK root (default: $HOME/Library/Android/sdk)
#   JAVA_HOME      JDK 17; auto-detected via /usr/libexec/java_home if unset
#   AVD_NAME       emulator AVD (default: napaxi_api34)
#
# Results are written to $HOME/testing/results/<timestamp>/ with a
# result.json summary and the Maestro JUnit report.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/examples/flutter"
FLOW_DIR="$APP_DIR/.maestro"
AVD_NAME="${AVD_NAME:-napaxi_api34}"
SKIP_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --avd) AVD_NAME="$2"; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"

if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    [ -n "$JAVA_HOME" ] && export JAVA_HOME
fi

MAESTRO_BIN="$(command -v maestro || true)"
[ -n "$MAESTRO_BIN" ] || MAESTRO_BIN="$HOME/.maestro/bin/maestro"
[ -n "$MAESTRO_BIN" ] && [ -x "$MAESTRO_BIN" ] || { echo "maestro CLI not found" >&2; exit 2; }

TS="$(date +%Y%m%d-%H%M%S)"
RESULT_DIR="$HOME/testing/results/$TS"
mkdir -p "$RESULT_DIR"
cd "$ROOT_DIR"

# Environment self-heal: force every Kotlin compile task to jvmTarget 1.8.
# Third-party plugins (umeng_common_sdk, flutter_contacts, ...) compile Java
# at 1.8 but leave Kotlin's jvmTarget unset, and KGP then defaults it to the
# JDK running Gradle (JBR 21 on this machine). Gradle variant resolution
# drops those modules' classes from consumers targeting < 21, surfacing as
# "cannot find symbol" in :app:compileDebugJavaWithJavac. Forcing all Kotlin
# to 1.8 is downgrade-compatible for Java 1.8 and Java 17 consumers alike.
# The consistency validation is downgraded to a warning as a safety net.
INIT_DIR="$HOME/.gradle/init.d"
mkdir -p "$INIT_DIR"
cat > "$INIT_DIR/napaxi-jvm-align.gradle" <<'GRADLE'
allprojects {
    afterEvaluate {
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
        }
    }
}
GRADLE
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
touch "$GRADLE_PROPS"
grep -q "kotlin.jvm.target.validation.mode" "$GRADLE_PROPS" || \
    echo "kotlin.jvm.target.validation.mode=warning" >> "$GRADLE_PROPS"

step() { echo "[layer2] $*"; }
STEP_BUILD="skipped"; STEP_EMULATOR="failed"; STEP_INSTALL="failed"; STEP_MAESTRO="failed"

# 1. Build Rust android libs + debug APK.
if [ "$SKIP_BUILD" -eq 0 ]; then
    step "build.sh fast android (rust libs)"
    ./tools/scripts/build.sh fast android > "$RESULT_DIR/build-rust.log" 2>&1 || {
        echo "rust android build failed, see $RESULT_DIR/build-rust.log" >&2
    }
    step "flutter build apk --debug"
    if (cd "$APP_DIR" && flutter build apk --debug) > "$RESULT_DIR/build-apk.log" 2>&1; then
        STEP_BUILD="passed"
    else
        STEP_BUILD="failed"
        echo "flutter build apk failed, see $RESULT_DIR/build-apk.log" >&2
    fi
fi
APK="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"

# 2. Boot the emulator if no device is online.
if [ "$("$ADB" devices | grep -cw device)" -ge 1 ]; then
    step "emulator already online"
    STEP_EMULATOR="passed"
else
    step "booting AVD $AVD_NAME"
    nohup "$EMULATOR" -avd "$AVD_NAME" -no-window -gpu swiftshader_indirect \
        -no-snapshot-save > "$RESULT_DIR/emulator.log" 2>&1 &
    for i in $(seq 1 60); do
        booted="$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
        [ "$booted" = "1" ] && { STEP_EMULATOR="passed"; break; }
        sleep 5
    done
fi

# 3. Install the APK.
if [ "$STEP_EMULATOR" = "passed" ] && [ -f "$APK" ]; then
    step "installing $APK"
    if "$ADB" install -r "$APK" > "$RESULT_DIR/install.log" 2>&1 && \
       grep -q Success "$RESULT_DIR/install.log"; then
        STEP_INSTALL="passed"
    fi
fi

# 4. Run Maestro smoke flows.
if [ "$STEP_INSTALL" = "passed" ]; then
    step "maestro test $FLOW_DIR"
    if "$MAESTRO_BIN" test "$FLOW_DIR" --format junit \
        --output "$RESULT_DIR/maestro-report.xml" > "$RESULT_DIR/maestro.log" 2>&1; then
        STEP_MAESTRO="passed"
    fi
fi

VERDICT="PASS"
for s in "$STEP_EMULATOR" "$STEP_INSTALL" "$STEP_MAESTRO"; do
    [ "$s" = "passed" ] || VERDICT="FAIL"
done
[ "$SKIP_BUILD" -eq 1 ] || [ "$STEP_BUILD" = "passed" ] || VERDICT="FAIL"

cat > "$RESULT_DIR/result.json" <<EOF
{
  "layer": "maestro-smoke",
  "avd": "$AVD_NAME",
  "steps": {
    "build": "$STEP_BUILD",
    "emulator": "$STEP_EMULATOR",
    "install": "$STEP_INSTALL",
    "maestro": "$STEP_MAESTRO"
  },
  "verdict": "$VERDICT",
  "report": "$RESULT_DIR/maestro-report.xml"
}
EOF

echo "[layer2] verdict=$VERDICT results=$RESULT_DIR"
[ "$VERDICT" = "PASS" ]
