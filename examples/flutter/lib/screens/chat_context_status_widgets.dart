part of '../main.dart';

enum _ContextCompactionNoticeKind { compacting, compacted, failed }

class _ContextCompactionNotice {
  const _ContextCompactionNotice._({
    required this.kind,
    required this.strategy,
    required this.updatedAt,
    this.usagePercent,
    this.tokensBefore,
    this.tokensAfter,
    this.turnsRemoved = 0,
    this.message,
  });

  factory _ContextCompactionNotice.compacting({
    required double usagePercent,
    required String strategy,
  }) {
    return _ContextCompactionNotice._(
      kind: _ContextCompactionNoticeKind.compacting,
      usagePercent: usagePercent,
      strategy: strategy,
      updatedAt: DateTime.now(),
    );
  }

  factory _ContextCompactionNotice.compacted({
    required int tokensBefore,
    required int tokensAfter,
    required int turnsRemoved,
    required String strategy,
  }) {
    return _ContextCompactionNotice._(
      kind: _ContextCompactionNoticeKind.compacted,
      tokensBefore: tokensBefore,
      tokensAfter: tokensAfter,
      turnsRemoved: turnsRemoved,
      strategy: strategy,
      updatedAt: DateTime.now(),
    );
  }

  factory _ContextCompactionNotice.failed({
    required String message,
    required String strategy,
  }) {
    return _ContextCompactionNotice._(
      kind: _ContextCompactionNoticeKind.failed,
      message: message,
      strategy: strategy,
      updatedAt: DateTime.now(),
    );
  }

  final _ContextCompactionNoticeKind kind;
  final String strategy;
  final DateTime updatedAt;
  final double? usagePercent;
  final int? tokensBefore;
  final int? tokensAfter;
  final int turnsRemoved;
  final String? message;
}

class _ContextCompactionBanner extends StatelessWidget {
  const _ContextCompactionBanner({
    super.key,
    required this.notice,
    required this.status,
    required this.onTap,
  });

  final _ContextCompactionNotice notice;
  final sdk.ContextStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCompacting = notice.kind == _ContextCompactionNoticeKind.compacting;
    final isFailed = notice.kind == _ContextCompactionNoticeKind.failed;
    final title = switch (notice.kind) {
      _ContextCompactionNoticeKind.compacting => '正在压缩上下文',
      _ContextCompactionNoticeKind.compacted => '上下文已压缩',
      _ContextCompactionNoticeKind.failed => '压缩失败',
    };
    final accent = isFailed
        ? const Color(0xFFB42318)
        : isCompacting
        ? const Color(0xFF374151)
        : const Color(0xFF067647);

    return Material(
      color: Colors.white,
      elevation: 7,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: const Key('context_compaction_banner'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 32,
                child: Center(
                  child: isCompacting
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        )
                      : Icon(
                          isFailed
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_rounded,
                          color: accent,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final strategy = _contextCompactionStrategyLabel(notice.strategy);
    return switch (notice.kind) {
      _ContextCompactionNoticeKind.compacting => _compactingSubtitle(strategy),
      _ContextCompactionNoticeKind.compacted => _compactedSubtitle(strategy),
      _ContextCompactionNoticeKind.failed =>
        '$strategy · ${notice.message ?? '请重试'}',
    };
  }

  String _compactingSubtitle(String strategy) {
    final status = this.status;
    if (status != null) {
      return '$strategy · 当前窗口 ${_formatContextTokens(status.currentWindowTokens)} / ${_formatContextTokens(status.effectiveContextWindowTokens)}';
    }
    final usage = notice.usagePercent;
    if (usage != null && usage.isFinite && usage > 0) {
      return '$strategy · 窗口压力 ${_formatContextPercent(usage)}';
    }
    return '$strategy · 摘要生成中';
  }

  String _compactedSubtitle(String strategy) {
    final before = notice.tokensBefore ?? 0;
    final after = notice.tokensAfter ?? 0;
    final parts = <String>[strategy];
    if (before > 0 || after > 0) {
      parts.add(
        '${_formatContextTokens(before)} -> ${_formatContextTokens(after)}',
      );
    }
    if (notice.turnsRemoved > 0) {
      parts.add('压缩 ${notice.turnsRemoved} 轮');
    }
    return parts.join(' · ');
  }
}

class _ContextStatusButton extends StatelessWidget {
  const _ContextStatusButton({
    required this.status,
    required this.isLoading,
    required this.hasSession,
    required this.onTap,
  });

  final sdk.ContextStatus? status;
  final bool isLoading;
  final bool hasSession;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final usage = status?.usageFraction.clamp(0.0, 1.0) ?? 0.0;

    final double? progressValue;
    if (status != null) {
      progressValue = math.min(usage, 1.0);
    } else if (isLoading) {
      progressValue = null;
    } else {
      progressValue = 0.0;
    }

    final summary = _contextStatusSummary(status, hasSession: hasSession);
    final foreground = hasSession
        ? const Color(0xFF6B7280)
        : const Color(0xFFA3A3A3);
    final canTap = hasSession && !isLoading || status != null;

    return Semantics(
      label: summary,
      button: true,
      child: Tooltip(
        message: summary,
        child: SizedBox.square(
          dimension: 40,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkResponse(
              key: const Key('context_status_button'),
              onTap: canTap ? onTap : null,
              customBorder: const CircleBorder(),
              radius: 20,
              child: Center(
                child: SizedBox.square(
                  dimension: 15,
                  child: isLoading && status == null
                      ? CircularProgressIndicator(
                          strokeWidth: 1.4,
                          backgroundColor: const Color(0xFFE5E5E5),
                          valueColor: AlwaysStoppedAnimation<Color>(foreground),
                        )
                      : CustomPaint(
                          painter: _ContextStatusGlyphPainter(
                            value: progressValue ?? 0,
                            foreground: foreground,
                            showProgress: status != null,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextStatusGlyphPainter extends CustomPainter {
  const _ContextStatusGlyphPainter({
    required this.value,
    required this.foreground,
    required this.showProgress,
  });

  final double value;
  final Color foreground;
  final bool showProgress;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.45;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final basePaint = Paint()
      ..color = const Color(0xFFD6D6D6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, basePaint);

    if (!showProgress) return;

    final progress = value.clamp(0.0, 1.0);
    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_ContextStatusGlyphPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.foreground != foreground ||
        oldDelegate.showProgress != showProgress;
  }
}

String _contextStatusSummary(
  sdk.ContextStatus? status, {
  required bool hasSession,
}) {
  if (!hasSession) return '上下文未开始';
  if (status == null) return '上下文计算中';
  return [
    '有效窗口',
    _contextSourceLabel(status.displaySource),
    '有效预算 ${_formatContextTokens(status.effectiveContextWindowTokens)}',
    '已用 ${_formatContextTokens(status.currentWindowTokens)}',
    '会话记录 ${_formatContextTokens(status.transcriptEstimatedTokens)}',
    '剩余 ${_formatContextPercent(_contextRemainingPercent(status))}',
  ].join(' · ');
}

double _contextUsedPercent(sdk.ContextStatus status) {
  final usagePercent = status.usagePercent;
  if (usagePercent.isFinite) {
    return usagePercent.clamp(0.0, 100.0).toDouble();
  }
  if (status.effectiveContextWindowTokens <= 0) return 0;
  return ((status.currentWindowTokens / status.effectiveContextWindowTokens) *
          100)
      .clamp(0.0, 100.0)
      .toDouble();
}

double _contextRemainingPercent(sdk.ContextStatus status) {
  return (100 - _contextUsedPercent(status)).clamp(0.0, 100.0).toDouble();
}

String _formatContextPercent(double percent) {
  final text = percent.toStringAsFixed(1);
  if (text.endsWith('.0')) return '${text.substring(0, text.length - 2)}%';
  return '$text%';
}

void _showContextStatusDetails(
  BuildContext context,
  sdk.ContextStatus status, {
  VoidCallback? onConfigure,
  VoidCallback? onCompact,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final breakdown = status.breakdown;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '上下文窗口',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ContextStatusSummaryPanel(status: status),
                      if (onConfigure != null || onCompact != null) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: onConfigure == null
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        onConfigure();
                                      },
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('配置'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _configTextPrimary,
                                  side: const BorderSide(color: _configBorder),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: onCompact == null
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        onCompact();
                                      },
                                icon: const Icon(
                                  Icons.unfold_less_rounded,
                                  size: 18,
                                ),
                                label: const Text('压缩'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _configTextPrimary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      _ContextStatusAdvancedDetails(
                        status: status,
                        breakdown: breakdown,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ContextStatusSummaryPanel extends StatelessWidget {
  const _ContextStatusSummaryPanel({required this.status});

  final sdk.ContextStatus status;

  @override
  Widget build(BuildContext context) {
    final usedPercent = _contextUsedPercent(status);
    final usedFraction = (usedPercent / 100).clamp(0.0, 1.0).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ContextStatusMetric(
                    label: '有效窗口',
                    value: _formatContextTokens(
                      status.effectiveContextWindowTokens,
                    ),
                  ),
                ),
                Expanded(
                  child: _ContextStatusMetric(
                    label: '当前窗口',
                    value: _formatContextTokens(status.currentWindowTokens),
                  ),
                ),
                Expanded(
                  child: _ContextStatusMetric(
                    label: '会话记录',
                    value: _formatContextTokens(
                      status.transcriptEstimatedTokens,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: usedFraction,
                backgroundColor: const Color(0xFFE5E5E5),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextStatusMetric extends StatelessWidget {
  const _ContextStatusMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF737373),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF171717),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ContextStatusAdvancedDetails extends StatelessWidget {
  const _ContextStatusAdvancedDetails({
    required this.status,
    required this.breakdown,
  });

  final sdk.ContextStatus status;
  final sdk.ContextTokenBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        '高级详情',
        style: TextStyle(
          color: Color(0xFF525252),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      children: [
        _ContextStatusSection(
          title: '当前窗口',
          children: [
            _ContextStatusDetailRow(
              label: '用量来源',
              value: _contextSourceLabel(status.displaySource),
            ),
            _ContextStatusDetailRow(
              label: '窗口占用',
              value:
                  '${_formatContextTokens(status.currentWindowTokens)} / ${_formatContextTokens(status.effectiveContextWindowTokens)}',
            ),
            _ContextStatusDetailRow(
              label: '原生窗口',
              value:
                  '${_formatContextTokens(status.nativeContextWindowTokens)} · ${_contextWindowSourceLabel(status.nativeContextWindowSource)}',
            ),
            if (status.providerMetadataFetchedAt != null ||
                status.providerMetadataError != null)
              _ContextStatusDetailRow(
                label: 'Provider metadata',
                value: _providerMetadataLabel(status),
              ),
            _ContextStatusDetailRow(
              label: '有效预算',
              value:
                  '${_formatContextTokens(status.effectiveContextWindowTokens)} · ${_contextWindowSourceLabel(status.effectiveContextWindowSource)}',
            ),
            _ContextStatusDetailRow(
              label: '回复预留',
              value:
                  '${_formatContextTokens(status.responseReserveTokens)} · ${_contextReserveSourceLabel(status.responseReserveSource)}',
            ),
            if (status.contextGuardStatus != 'ok' &&
                status.contextGuardStatus != 'unknown')
              _ContextStatusDetailRow(
                label: '预算保护',
                value: _contextGuardLabel(
                  status.contextGuardStatus,
                  status.contextGuardReason,
                ),
              ),
            if (status.overflowTokens > 0)
              _ContextStatusDetailRow(
                label: '超出',
                value: _formatContextTokens(status.overflowTokens),
              ),
            _ContextStatusDetailRow(
              label: '剩余',
              value: _formatContextPercent(_contextRemainingPercent(status)),
            ),
            _ContextStatusDetailRow(
              label: '上次请求',
              value: status.lastPromptTokens == null
                  ? '模型未返回'
                  : _formatContextTokens(status.lastPromptTokens!),
            ),
            _ContextStatusDetailRow(
              label: '本次预估',
              value: status.preflightEstimatedTokens == null
                  ? '暂无'
                  : '~${_formatContextTokens(status.preflightEstimatedTokens!)}',
            ),
            _ContextStatusDetailRow(
              label: '变化原因',
              value: _contextDeltaLabel(status),
            ),
          ],
        ),
        _ContextStatusSection(
          title: '会话记录',
          children: [
            _ContextStatusDetailRow(
              label: '本地估算',
              value: _formatContextTokens(status.transcriptEstimatedTokens),
            ),
            _ContextStatusDetailRow(
              label: '窗口来源',
              value: _contextWindowSourceLabel(status.contextWindowSource),
            ),
            _ContextStatusDetailRow(
              label: '预算路线',
              value: _contextRouteLabel(status.contextRoute),
            ),
          ],
        ),
        if (status.compactionCount > 0 ||
            status.lastCompactedAt != null ||
            status.tokensBefore > 0 ||
            status.tokensAfter > 0)
          _ContextStatusSection(
            title: '压缩',
            children: [
              _ContextStatusDetailRow(
                label: '方式',
                value: _contextCompactionStrategyLabel(
                  status.compactionStrategy,
                ),
              ),
              _ContextStatusDetailRow(
                label: '次数',
                value: '${status.compactionCount}',
              ),
              _ContextStatusDetailRow(
                label: '上次',
                value: status.lastCompactedAt ?? '无',
              ),
              _ContextStatusDetailRow(
                label: '前/后',
                value:
                    '${_formatContextTokens(status.tokensBefore)} / ${_formatContextTokens(status.tokensAfter)}',
              ),
              _ContextStatusDetailRow(
                label: '耗时',
                value: status.lastCompactionDurationMs == null
                    ? '暂无'
                    : '${status.lastCompactionDurationMs} ms',
              ),
              _ContextStatusDetailRow(
                label: 'Adaptive chunks',
                value: status.adaptiveChunkCount <= 0
                    ? '暂无'
                    : '${status.adaptiveChunkCount}',
              ),
              if (status.oversizedMessageCount > 0)
                _ContextStatusDetailRow(
                  label: '超大消息',
                  value: '${status.oversizedMessageCount}',
                ),
              if (status.protectedTailTokens > 0)
                _ContextStatusDetailRow(
                  label: 'Tail 保护',
                  value: _formatContextTokens(status.protectedTailTokens),
                ),
              if (status.preCompactionMemoryFlushEnabled ||
                  status.preCompactionMemoryFlushStatus != null)
                _ContextStatusDetailRow(
                  label: '记忆刷新',
                  value: status.preCompactionMemoryFlushEnabled
                      ? (status.preCompactionMemoryFlushStatus ?? '已开启')
                      : '关闭',
                ),
            ],
          ),
        if (status.overflowRetryAttemptedAt != null ||
            status.overflowRetryReason != null)
          _ContextStatusSection(
            title: 'Overflow retry',
            children: [
              _ContextStatusDetailRow(
                label: '结果',
                value: _overflowRetryLabel(status),
              ),
              _ContextStatusDetailRow(
                label: '时间',
                value: status.overflowRetryAttemptedAt ?? '暂无',
              ),
              if (status.overflowRetryError != null)
                _ContextStatusDetailRow(
                  label: '错误',
                  value: status.overflowRetryError!,
                ),
            ],
          ),
        _ContextStatusSection(
          title: '细分',
          children: [
            _ContextStatusDetailRow(
              label: '历史',
              value: _formatContextTokens(breakdown?.historyTokens ?? 0),
            ),
            _ContextStatusDetailRow(
              label: '工具结果',
              value: _formatContextTokens(breakdown?.toolResultTokens ?? 0),
            ),
            _ContextStatusDetailRow(
              label: '工具裁剪',
              value:
                  '${_formatContextTokens(status.toolResultPrunedTokens)} / ${status.toolResultPrunedChars} chars',
            ),
            _ContextStatusDetailRow(
              label: '附件/图片',
              value:
                  '${_formatContextTokens(breakdown?.attachmentTokens ?? 0)} / ${_formatContextTokens(breakdown?.imageTokens ?? 0)}',
            ),
            _ContextStatusDetailRow(
              label: '缓存读/写',
              value:
                  '${_formatContextTokens(status.cacheReadTokens)} / ${_formatContextTokens(status.cacheWriteTokens)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _ContextStatusSection extends StatelessWidget {
  const _ContextStatusSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ContextStatusDetailRow extends StatelessWidget {
  const _ContextStatusDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _contextSourceLabel(String source) {
  return switch (source) {
    'provider' => '真实用量',
    'preflight' => '本次预估',
    'legacy' => '本地预估',
    'unknown' => '等待刷新',
    _ => source,
  };
}

String _contextDeltaLabel(sdk.ContextStatus status) {
  final delta = status.lastContextDeltaTokens;
  final reason = _contextDeltaReasonLabel(status.lastContextDeltaReason);
  if (delta == 0) return reason;
  final prefix = delta > 0 ? '+' : '';
  return '$reason $prefix${_formatContextTokens(delta.abs())}';
}

String _contextDeltaReasonLabel(String reason) {
  return switch (reason) {
    'provider_replaced_preflight' => '真实用量替换预估',
    'tool_result_pruned' => '工具结果裁剪',
    'overflow_retry_succeeded' => '溢出后压缩重试成功',
    'overflow_retry_failed' => '溢出后重试失败',
    'llm_compacted' => 'LLM 已压缩',
    'compacted' => '已压缩',
    'attachment_expired' => '附件未延续',
    'stable' => '暂无变化',
    _ => reason,
  };
}

String _providerMetadataLabel(sdk.ContextStatus status) {
  if (status.providerMetadataError != null &&
      status.providerMetadataError!.isNotEmpty) {
    return status.providerMetadataStale
        ? '已过期 · ${status.providerMetadataError}'
        : status.providerMetadataError!;
  }
  final fetchedAt = status.providerMetadataFetchedAt;
  if (fetchedAt == null || fetchedAt.isEmpty) return '暂无';
  return status.providerMetadataStale ? '已过期 · $fetchedAt' : fetchedAt;
}

String _overflowRetryLabel(sdk.ContextStatus status) {
  final reason = status.overflowRetryReason;
  final suffix = reason == null || reason.isEmpty ? '' : ' · $reason';
  return switch (status.overflowRetrySucceeded) {
    true => '成功$suffix',
    false => '失败$suffix',
    null => '已尝试$suffix',
  };
}

String _contextWindowSourceLabel(String source) {
  return switch (source) {
    'config' => '配置指定',
    'provider' => 'Provider 返回',
    'model_config' => '模型配置',
    'model_rule' => '模型规则',
    'default' => '默认窗口',
    'unknown' => '未知',
    _ => source,
  };
}

String _contextCompactionStrategyLabel(String strategy) {
  return switch (strategy) {
    'llm_summary' => 'LLM 摘要',
    'local_summary' => '本地摘要',
    _ => strategy,
  };
}

String _contextRouteLabel(String? route) {
  if (route == null || route.isEmpty) return '暂无';
  return switch (route) {
    'fits' => '可直接发送',
    'prune_tools' => '裁剪工具结果',
    'compact' => '需要压缩',
    'compact_then_prune' => '先压缩再裁剪',
    'reject_too_large' => '预算过低',
    'truncate_tool_results_only' => '仅裁剪工具结果',
    'compact_only' => '需要压缩',
    'compact_then_truncate' => '先压缩再裁剪',
    _ => route,
  };
}

String _contextReserveSourceLabel(String source) {
  return switch (source) {
    'config' => '配置指定',
    'model_output_limit' => '输出上限',
    'default' => '默认预留',
    'unknown' => '未知',
    _ => source,
  };
}

String _contextGuardLabel(String status, String reason) {
  final prefix = switch (status) {
    'blocked' => '已阻止',
    'warning' => '需注意',
    _ => status,
  };
  final detail = switch (reason) {
    'context_window_missing' => '窗口未知',
    'remaining_budget_below_hard_floor' => '剩余预算低于安全下限',
    'remaining_budget_below_warning_floor' => '剩余预算偏低',
    'effective_window_below_hard_floor' => '有效窗口低于安全下限',
    'effective_window_below_warning_floor' => '有效窗口偏低',
    '' => '',
    _ => reason,
  };
  return detail.isEmpty ? prefix : '$prefix · $detail';
}

String _formatContextTokens(int tokens) {
  if (tokens >= 1000000) {
    return '${(tokens / 1000000).toStringAsFixed(1)}M';
  }
  if (tokens >= 10000) {
    return '${(tokens / 1000).toStringAsFixed(0)}k';
  }
  if (tokens >= 1000) {
    return '${(tokens / 1000).toStringAsFixed(1)}k';
  }
  return '$tokens';
}
