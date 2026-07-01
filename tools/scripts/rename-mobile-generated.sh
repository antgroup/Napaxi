#!/usr/bin/env bash
# Apply just the Mobile* / mobile_* renames to the generated bridge files,
# without re-running flutter_rust_bridge_codegen.
#
# Codegen toolchain drift (FRB version, dart format version) produced a much
# larger generated diff than the actual rename semantics needed. To keep this
# PR's diff legible — and to keep the change traceable as a pure rename —
# we mutate the existing generated files in place so the diff stays
# "name swap only".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# Same ordered list as rename-mobile.sh. Longest first.
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
    "wire__crate__bridge__init__is_mobile_platform_tool_impl|wire__crate__bridge__init__is_platform_tool_impl"
    "wire__crate__bridge__init__mobile_platform_tool_descriptors_json_impl|wire__crate__bridge__init__platform_tool_descriptors_json_impl"
)

# FRB Dart codegen camelCases free functions and prefixes Rust paths into
# method names like crateBridgeInitMobilePlatformToolDescriptorsJson.
DART_PAIRS=(
    "CrateBridgeInitMobilePlatformToolDescriptorsJsonConstMeta|CrateBridgeInitPlatformToolDescriptorsJsonConstMeta"
    "CrateBridgeInitIsMobilePlatformToolConstMeta|CrateBridgeInitIsPlatformToolConstMeta"
    "kCrateBridgeInitMobilePlatformToolDescriptorsJsonConstMeta|kCrateBridgeInitPlatformToolDescriptorsJsonConstMeta"
    "kCrateBridgeInitIsMobilePlatformToolConstMeta|kCrateBridgeInitIsPlatformToolConstMeta"
    "crateBridgeInitMobilePlatformToolDescriptorsJson|crateBridgeInitPlatformToolDescriptorsJson"
    "crateBridgeInitIsMobilePlatformTool|crateBridgeInitIsPlatformTool"
    "MobilePlatformToolDescriptorsJson|PlatformToolDescriptorsJson"
    "MobilePlatformToolDescriptors|PlatformToolDescriptors"
    "IsMobilePlatformTool|IsPlatformTool"
    "mobilePlatformToolDescriptorsJson|platformToolDescriptorsJson"
    "mobilePlatformToolDescriptors|platformToolDescriptors"
    "isMobilePlatformTool|isPlatformTool"
)

apply_pair() {
    local file="$1" old="$2" new="$3"
    sed -E -i '' "s/[[:<:]]${old}[[:>:]]/${new}/g" "$file"
}

apply_all_to_file() {
    local file="$1"
    for pair in "${PAIRS[@]}"; do
        apply_pair "$file" "${pair%%|*}" "${pair##*|}"
    done
    case "$file" in
        *.dart)
            for pair in "${DART_PAIRS[@]}"; do
                apply_pair "$file" "${pair%%|*}" "${pair##*|}"
            done
            ;;
    esac
}

FILES=()
[ -f packages/api_bridge/generated/frb_generated.rs ] && FILES+=("packages/api_bridge/generated/frb_generated.rs")
[ -f packages/flutter/ios/Classes/frb_generated.h ] && FILES+=("packages/flutter/ios/Classes/frb_generated.h")
while IFS= read -r f; do
    FILES+=("$f")
done < <(find packages/flutter/lib/generated -type f -name '*.dart' 2>/dev/null | LC_ALL=C sort)

for f in "${FILES[@]}"; do
    apply_all_to_file "$f"
done

# Post-pass residue check.
if grep -E "Mobile[A-Z]|mobile_platform_tool|is_mobile_platform_tool" \
    packages/api_bridge/generated/frb_generated.rs \
    packages/flutter/ios/Classes/frb_generated.h \
    packages/flutter/lib/generated/*.dart \
    packages/flutter/lib/generated/bridge/*.dart 2>/dev/null; then
    echo "rename-generated.sh: residue still present" >&2
    exit 1
fi
echo "rename-generated.sh: generated bridge surface is clean"
