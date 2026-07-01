import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

void main() {
  test('ContextStatus parses legacy context JSON', () {
    final status = ContextStatus.fromJson(jsonEncode({
      'thread_id': 'thread',
      'engine': 'compressor',
      'summary_present': false,
      'compaction_count': 0,
      'estimated_tokens': 30000,
      'context_window_tokens': 128000,
      'trigger_tokens': 108800,
      'target_tokens': 57600,
      'response_reserve_tokens': 4096,
      'usage_percent': 23.4,
      'trigger_ratio': 0.85,
      'target_ratio': 0.45,
    }));

    expect(status.displayUsedTokens, 30000);
    expect(status.currentWindowTokens, 30000);
    expect(status.transcriptEstimatedTokens, 30000);
    expect(status.displaySource, 'legacy');
    expect(status.isLegacyEstimate, isTrue);
    expect(status.usageFraction, closeTo(30000 / 128000, 0.0001));
  });

  test('ContextStatus parses provider and preflight fields', () {
    final status = ContextStatus.fromJson(jsonEncode({
      'thread_id': 'thread',
      'engine': 'compressor',
      'estimated_tokens': 24000,
      'display_used_tokens': 24000,
      'display_source': 'provider',
      'last_prompt_tokens': 24000,
      'preflight_estimated_tokens': 31000,
      'cache_read_tokens': 8000,
      'cache_write_tokens': 1200,
      'context_window_tokens': 128000,
      'context_window_source': 'config',
      'native_context_window_tokens': 1000000,
      'native_context_window_source': 'model_rule',
      'effective_context_window_tokens': 128000,
      'effective_context_window_source': 'config',
      'response_reserve_source': 'config',
      'provider_metadata_fetched_at': '2026-05-29T09:00:00Z',
      'provider_metadata_stale': false,
      'context_guard_status': 'ok',
      'context_guard_reason': '',
      'context_route': 'prune_tools',
      'overflow_tokens': 0,
      'current_window_tokens': 24000,
      'transcript_estimated_tokens': 36000,
      'last_context_delta_tokens': -7000,
      'last_context_delta_reason': 'provider_replaced_preflight',
      'tool_result_pruned_tokens': 1200,
      'tool_result_pruned_chars': 2400,
      'context_display_label': 'current_window',
      'compaction_strategy': 'llm_summary',
      'last_compaction_duration_ms': 3210,
      'adaptive_chunk_count': 3,
      'oversized_message_count': 1,
      'protected_tail_tokens': 18000,
      'overflow_retry_attempted_at': '2026-05-29T10:01:00Z',
      'overflow_retry_succeeded': true,
      'overflow_retry_reason': 'overflow_retry_succeeded',
      'pre_compaction_memory_flush_enabled': true,
      'pre_compaction_memory_flush_status': 'disabled_for_v6a',
      'fresh': true,
      'updated_at': '2026-05-29T10:00:00Z',
      'breakdown': {
        'system_prompt_tokens': 100,
        'history_tokens': 200,
        'tool_descriptor_tokens': 300,
        'tool_result_tokens': 400,
        'tool_call_tokens': 50,
        'attachment_tokens': 25,
        'image_tokens': 2000,
        'response_reserve_tokens': 4096,
        'total_tokens': 31000,
      },
      'context_budget_status': {
        'source': 'pre-prompt-estimate',
        'provider': 'openai-compatible',
        'model': 'gpt-4o',
        'route': 'prune_tools',
        'should_compact': false,
        'estimated_prompt_tokens': 26904,
        'context_token_budget': 128000,
        'native_context_window_tokens': 1000000,
        'native_context_window_source': 'model_rule',
        'effective_context_window_tokens': 128000,
        'effective_context_window_source': 'config',
        'response_reserve_source': 'config',
        'provider_metadata_fetched_at': '2026-05-29T09:00:00Z',
        'provider_metadata_stale': false,
        'prompt_budget_before_reserve': 123904,
        'reserve_tokens': 4096,
        'effective_reserve_tokens': 4096,
        'remaining_prompt_budget_tokens': 97000,
        'overflow_tokens': 0,
        'tool_result_reducible_chars': 2000,
        'tool_result_reducible_tokens': 1000,
        'context_guard_status': 'ok',
        'context_guard_reason': '',
        'message_count': 12,
        'unwindowed_message_count': 12,
        'updated_at': '2026-05-29T10:00:00Z',
      },
    }));

    expect(status.isProviderBacked, isTrue);
    expect(status.lastPromptTokens, 24000);
    expect(status.preflightEstimatedTokens, 31000);
    expect(status.cacheReadTokens, 8000);
    expect(status.cacheWriteTokens, 1200);
    expect(status.contextWindowSource, 'config');
    expect(status.nativeContextWindowTokens, 1000000);
    expect(status.nativeContextWindowSource, 'model_rule');
    expect(status.effectiveContextWindowTokens, 128000);
    expect(status.effectiveContextWindowSource, 'config');
    expect(status.responseReserveSource, 'config');
    expect(status.providerMetadataFetchedAt, '2026-05-29T09:00:00Z');
    expect(status.contextGuardStatus, 'ok');
    expect(status.contextRoute, 'prune_tools');
    expect(status.currentWindowTokens, 24000);
    expect(status.transcriptEstimatedTokens, 36000);
    expect(status.lastContextDeltaTokens, -7000);
    expect(status.lastContextDeltaReason, 'provider_replaced_preflight');
    expect(status.toolResultPrunedTokens, 1200);
    expect(status.toolResultPrunedChars, 2400);
    expect(status.contextDisplayLabel, 'current_window');
    expect(status.compactionStrategy, 'llm_summary');
    expect(status.lastCompactionDurationMs, 3210);
    expect(status.adaptiveChunkCount, 3);
    expect(status.oversizedMessageCount, 1);
    expect(status.protectedTailTokens, 18000);
    expect(status.overflowRetrySucceeded, isTrue);
    expect(status.preCompactionMemoryFlushEnabled, isTrue);
    expect(status.fresh, isTrue);
    expect(status.breakdown?.toolDescriptorTokens, 300);
    expect(status.breakdown?.imageTokens, 2000);
    expect(status.contextBudgetStatus?.route, 'prune_tools');
    expect(status.contextBudgetStatus?.nativeContextWindowTokens, 1000000);
    expect(status.contextBudgetStatus?.toolResultReducibleTokens, 1000);
    expect(
      status.contextBudgetStatus?.providerMetadataFetchedAt,
      '2026-05-29T09:00:00Z',
    );
    expect(status.contextBudgetStatus?.shouldCompact, isFalse);
  });
}
