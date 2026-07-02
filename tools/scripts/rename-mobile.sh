#!/usr/bin/env bash
# Retire the legacy Mobile* / mobile_* names from the SDK surface.
#
# See docs/naming-migration.md and the plan at
# .claude (plan: luminous-percolating-robin.md) for context.
#
# Usage:
#   bash tools/scripts/rename-mobile.sh
#
# Behavior:
#   * Operates on crates/, packages/api_bridge/{bridge,*.rs},
#     packages/flutter/lib/ (non-generated), packages/android/src/,
#     examples/flutter/lib/.
#   * Skips generated bridge code, build outputs, .dart_tool/, target/.
#   * Skips docs/naming-migration.md and CHANGELOG.md so historical public
#     release notes remain intact.
#   * Uses literal word-boundary replacement so MobileToolDescriptor is
#     handled before MobileTool would otherwise eat it (table is ordered
#     longest-first).
#   * Exits non-zero if any unexpected Mobile* / mobile_platform_tool / etc.
#     residue remains after the pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

command -v grep >/dev/null 2>&1 || { echo "grep required" >&2; exit 1; }

# Prefer a real ripgrep binary if one is installed, but fall back to grep -r
# so this script works in CI environments without ripgrep.
RG_BIN=""
for cand in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    if [ -x "$cand" ]; then RG_BIN="$cand"; break; fi
done

# Ordered longest-first so substring patterns don't shadow longer ones.
PAIRS=(
    "MobileEvolutionDiagnosticRecord|EvolutionDiagnosticRecord"
    "MobileInternalToolProgressSender|InternalToolProgressSender"
    "MobileInternalToolProgressEvent|InternalToolProgressEvent"
    "MobileToolRequestDispatcher|ToolRequestDispatcher"
    "MobileSessionAppendMessage|SessionAppendMessage"
    "MobileMcpOAuthStartOptions|McpOAuthStartOptions"
    "MobileInternalToolHandler|InternalToolHandler"
    "MobileInternalToolFuture|InternalToolFuture"
    "MobileInternalToolResult|InternalToolResult"
    "MobileToolExecutionContext|ToolExecutionContext"
    "MobileEvolutionRunStatus|EvolutionRunStatus"
    "MobileGroupToolExecution|GroupToolExecution"
    "MobileEvolutionRunRecord|EvolutionRunRecord"
    "MobileEvolutionExecutor|EvolutionExecutor"
    "MobileToolRequestBridge|ToolRequestBridge"
    "MobileGroupSessionState|GroupSessionState"
    "MobileBuiltinToolContext|BuiltinToolContext"
    "MobileSessionToolContext|SessionToolContext"
    "MobileCapabilityContext|CapabilityContext"
    "MobileGroupMemberTask|GroupMemberTask"
    "MobileSessionTurnInput|SessionTurnInput"
    "MobileReviewLlmHandler|ReviewLlmHandler"
    "MobileGroupMessageType|GroupMessageType"
    "MobilePendingEvolution|PendingEvolution"
    "MobileEvolutionState|EvolutionState"
    "MobileMcpOAuthPending|McpOAuthPending"
    "MobileMcpOAuthConfig|McpOAuthConfig"
    "MobileMcpOAuthTokens|McpOAuthTokens"
    "MobileToolDescriptor|ToolDescriptor"
    "MobileLlmStreamEvent|LlmStreamEvent"
    "MobileEvolutionRun|EvolutionRun"
    "MobileMcpSecretState|McpSecretState"
    "MobileMcpSecretEntry|McpSecretEntry"
    "MobileWorkspaceEntry|WorkspaceEntry"
    "MobileWorkspaceFile|WorkspaceFile"
    "MobileToolLoopResult|ToolLoopResult"
    "MobileSessionMessage|SessionMessage"
    "MobileGroupMessage|GroupMessage"
    "MobileSessionRecord|SessionRecord"
    "MobileToolRateLimiter|ToolRateLimiter"
    "MobileToolRateLimit|ToolRateLimit"
    "MobileMcpTransport|McpTransport"
    "MobileMcpActivation|McpActivation"
    "MobilePendingStatus|PendingStatus"
    "MobileAppliedAction|AppliedAction"
    "MobileChannelConfig|ChannelConfig"
    "MobileSkillPackage|SkillPackage"
    "MobileFileBridge|FileBridge"
    "MobileToolRegistry|ToolRegistry"
    "MobileToolTraceCall|ToolTraceCall"
    "MobileGroupState|GroupState"
    "MobileSessionInfo|SessionInfo"
    "MobileGroupInfo|GroupInfo"
    "MobileLlmToolCall|LlmToolCall"
    "MobileSessionKey|SessionKey"
    "MobileToolEffect|ToolEffect"
    "MobileToolTrace|ToolTrace"
    "MobileMcpState|McpState"
    "MobileLlmUsage|LlmUsage"
    "MobileMcpServer|McpServer"
    "MobileLlmTurn|LlmTurn"
    "MobileMcpTool|McpTool"
    "MobileEngine|Engine"
    "MobileGroup|Group"
    "mobile_platform_tool_descriptors_json|platform_tool_descriptors_json"
    "mobile_platform_tool_descriptors|platform_tool_descriptors"
    "is_mobile_platform_tool|is_platform_tool"
)

# Roots to rewrite.
ROOTS=(
    "crates"
    "packages/api_bridge/bridge"
    "packages/api_bridge/c_api.rs"
    "packages/api_bridge/android_jni.rs"
    "packages/api_bridge/android_assets.rs"
    "packages/api_bridge/lib.rs"
    "packages/flutter/lib"
    "packages/android/src"
    "examples/flutter/lib"
)

# Glob exclusions for rg file enumeration.
RG_GLOBS=(
    "--glob=!packages/flutter/lib/generated/**"
    "--glob=!packages/api_bridge/generated/**"
    "--glob=!**/build/**"
    "--glob=!**/.dart_tool/**"
    "--glob=!**/.gradle/**"
    "--glob=!**/.kotlin/**"
    "--glob=!**/target/**"
)

# Collect the union of files that contain any of the legacy identifiers.
collect_files() {
    local files=()
    if [ -n "$RG_BIN" ]; then
        while IFS= read -r f; do
            files+=("$f")
        done < <("$RG_BIN" -l "Mobile[A-Z]|mobile_platform_tool|is_mobile_platform_tool" "${ROOTS[@]}" "${RG_GLOBS[@]}" 2>/dev/null | LC_ALL=C sort -u)
    else
        # grep -r fallback. -l prints filenames; -E for alternation; -I skips binary.
        # Roots that are individual files are handled by passing them straight.
        while IFS= read -r f; do
            case "$f" in
                */generated/*|*/build/*|*/.dart_tool/*|*/.gradle/*|*/.kotlin/*|*/target/*)
                    continue;;
            esac
            files+=("$f")
        done < <(grep -rlIE "Mobile[A-Z]|mobile_platform_tool|is_mobile_platform_tool" "${ROOTS[@]}" 2>/dev/null | LC_ALL=C sort -u)
    fi
    printf '%s\n' "${files[@]}"
}

apply_pairs_to_file() {
    local file="$1"
    local sed_script=""
    for pair in "${PAIRS[@]}"; do
        local old="${pair%%|*}"
        local new="${pair##*|}"
        # \b word boundaries work in BSD sed via -E; we use [[:<:]]/[[:>:]]
        # which BSD sed supports natively.
        sed_script+="s/[[:<:]]${old}[[:>:]]/${new}/g;"
    done
    # macOS / BSD sed: in-place with empty backup arg.
    sed -E -i '' "${sed_script}" "$file"
}

TARGET_FILES=()
while IFS= read -r f; do
    [ -z "$f" ] && continue
    TARGET_FILES+=("$f")
done < <(collect_files)

if [ "${#TARGET_FILES[@]}" -eq 0 ]; then
    echo "rename-mobile.sh: nothing to rename; SDK surface is already clean."
    exit 0
fi

echo "rename-mobile.sh: rewriting ${#TARGET_FILES[@]} files"
for f in "${TARGET_FILES[@]}"; do
    apply_pairs_to_file "$f"
done

# Post-pass: verify nothing slipped through outside known exclusions.
LEAK_GLOBS=(
    "--glob=!packages/flutter/lib/generated/**"
    "--glob=!packages/api_bridge/generated/**"
    "--glob=!**/build/**"
    "--glob=!**/.dart_tool/**"
    "--glob=!**/.gradle/**"
    "--glob=!**/.kotlin/**"
    "--glob=!**/target/**"
    "--glob=!docs/naming-migration.md"
    "--glob=!CHANGELOG.md"
    "--glob=!tools/scripts/rename-mobile.sh"
)

check_residue() {
    local pattern="$1" message="$2"
    local hits=""
    if [ -n "$RG_BIN" ]; then
        hits=$("$RG_BIN" -n "$pattern" "${ROOTS[@]}" "${LEAK_GLOBS[@]}" 2>/dev/null || true)
    else
        local raw
        raw=$(grep -rnIE "$pattern" "${ROOTS[@]}" 2>/dev/null || true)
        # Filter out the known exclusions in shell.
        hits=$(printf '%s\n' "$raw" | grep -Ev '/generated/|/build/|/\.dart_tool/|/\.gradle/|/\.kotlin/|/target/|docs/naming-migration\.md|^CHANGELOG\.md:|tools/scripts/rename-mobile\.sh' || true)
    fi
    if [ -n "$hits" ]; then
        echo "$hits"
        echo "rename-mobile.sh: $message" >&2
        return 1
    fi
    return 0
}

failed=0
check_residue '\bMobile[A-Z][A-Za-z0-9]*' "residual Mobile* identifiers; investigate hits above." || failed=1
check_residue '\b(mobile_platform_tool|mobile_platform_tool_descriptors|is_mobile_platform_tool)\b' "residual mobile_* function identifiers." || failed=1

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "rename-mobile.sh: rename pass complete; SDK surface is clean."
