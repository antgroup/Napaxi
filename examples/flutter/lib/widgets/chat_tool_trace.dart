part of '../main.dart';

const _toolFailureColor = Color(0xFF6B7280);
const _toolFailureSurface = Color(0xFFF9FAFB);
const _toolFailureBorder = Color(0xFFE5E7EB);
const _toolFailureTerminalColor = Color(0xFF9CA3AF);

class _AgentTraceSection extends StatefulWidget {
  const _AgentTraceSection({
    required this.message,
    required this.onLoadFullToolCall,
  });

  final ChatMessage message;
  final Future<AgentToolCall?> Function(AgentToolCall toolCall)
  onLoadFullToolCall;

  @override
  State<_AgentTraceSection> createState() => _AgentTraceSectionState();
}

class _AgentTraceSectionState extends State<_AgentTraceSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.message.isStreaming;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1, end: 0.35).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.message.isStreaming) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AgentTraceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.isStreaming && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
      if (!oldWidget.message.isStreaming) _expanded = true;
    } else if (!widget.message.isStreaming && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
      if (widget.message.content.isNotEmpty) _expanded = false;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final message = widget.message;
    final duration = _formatDuration(message.duration);
    final traceSteps = message.traceSteps.isNotEmpty
        ? message.traceSteps
        : [
            AgentTraceStep(
              reasoning: message.reasoning,
              toolCalls: message.toolCalls,
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('agent_trace_toggle'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: FadeTransition(
                  opacity: _pulseAnimation,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.psychology_alt_outlined,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        message.isStreaming
                            ? strings.thinking
                            : strings.thinkingDone,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!message.isStreaming && duration != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          duration,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (message.toolCalls.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _TraceCountChip(message: message),
                      ],
                      if (message.activatedSkills.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _SkillCountChip(skills: message.activatedSkills),
                      ],
                      const SizedBox(width: 2),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: const Color(0xFF6B7280),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          if (message.activatedSkills.isNotEmpty) ...[
            _ActivatedSkillsView(skills: message.activatedSkills),
            if (traceSteps.any((step) => !step.isEmpty))
              const SizedBox(height: 8),
          ],
          for (final step in traceSteps)
            _AgentTraceStepView(
              step: step,
              onLoadFullToolCall: widget.onLoadFullToolCall,
            ),
        ],
      ],
    );
  }
}

class _SkillCountChip extends StatelessWidget {
  const _SkillCountChip({required this.skills});

  final List<sdk.ActivatedSkillInfo> skills;

  @override
  Widget build(BuildContext context) {
    final count = skills.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.school_outlined, size: 13, color: Color(0xFF047857)),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: const TextStyle(
            color: Color(0xFF047857),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ActivatedSkillsView extends StatelessWidget {
  const _ActivatedSkillsView({required this.skills});

  final List<sdk.ActivatedSkillInfo> skills;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return DecoratedBox(
      key: const Key('activated_skills_trace'),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.school_outlined,
                  size: 15,
                  color: Color(0xFF047857),
                ),
                const SizedBox(width: 6),
                Text(
                  strings.skillsEnabled,
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final skill in skills) _ActivatedSkillPill(skill: skill),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivatedSkillPill extends StatelessWidget {
  const _ActivatedSkillPill({required this.skill});

  final sdk.ActivatedSkillInfo skill;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final reasonLabel = _skillReasonLabel(strings, skill.reason);
    final meta = [
      if (reasonLabel.isNotEmpty) reasonLabel,
      if (skill.version.trim().isNotEmpty) 'v${skill.version.trim()}',
      if (skill.trust.trim().isNotEmpty) skill.trust.trim(),
    ].join(' · ');
    final name = skill.name.trim().isEmpty ? 'skill' : skill.name.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;
        return DecoratedBox(
          key: Key('activated_skill_$name'),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      softWrap: true,
                      style: const TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        meta,
                        softWrap: true,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _skillReasonLabel(AppStrings strings, String reason) {
  switch (reason.trim()) {
    case 'matched':
      return strings.skillReasonMatched;
    case 'continued':
      return strings.skillReasonContinued;
    case 'task_context':
      return strings.skillReasonTaskContext;
    case 'loaded':
      return strings.skillReasonLoaded;
    case 'explicit':
      return strings.skillReasonExplicit;
    default:
      return '';
  }
}

class _AgentTraceStepView extends StatelessWidget {
  const _AgentTraceStepView({
    required this.step,
    required this.onLoadFullToolCall,
  });

  final AgentTraceStep step;
  final Future<AgentToolCall?> Function(AgentToolCall toolCall)
  onLoadFullToolCall;

  @override
  Widget build(BuildContext context) {
    if (step.isEmpty) return const SizedBox.shrink();
    final toolWidgets = _traceToolWidgets(step.toolCalls);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step.reasoning.trim().isNotEmpty)
          _ReasoningBlock(text: step.reasoning.trim()),
        ...toolWidgets,
      ],
    );
  }

  List<Widget> _traceToolWidgets(List<AgentToolCall> toolCalls) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < toolCalls.length) {
      final toolCall = toolCalls[index];
      if (_isReadFileToolCall(toolCall)) {
        final group = <AgentToolCall>[toolCall];
        index += 1;
        while (index < toolCalls.length &&
            _isReadFileToolCall(toolCalls[index])) {
          group.add(toolCalls[index]);
          index += 1;
        }
        widgets.add(_ReadFileTraceGroup(toolCalls: group));
        continue;
      }
      if (_isWriteFileToolCall(toolCall)) {
        final group = <AgentToolCall>[toolCall];
        index += 1;
        while (index < toolCalls.length &&
            _isWriteFileToolCall(toolCalls[index])) {
          group.add(toolCalls[index]);
          index += 1;
        }
        widgets.add(_WriteFileTraceGroup(toolCalls: group));
        continue;
      }
      widgets.add(
        _ToolCallCard(
          toolCall: toolCall,
          onLoadFullToolCall: onLoadFullToolCall,
        ),
      );
      index += 1;
    }
    return widgets;
  }
}

class _TraceCountChip extends StatelessWidget {
  const _TraceCountChip({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final allDone = message.toolCalls.every((call) => call.isComplete);
    final color = allDone ? const Color(0xFF4B5563) : const Color(0xFF2563EB);
    final icon = allDone ? Icons.check_rounded : Icons.sync_rounded;
    final count = _groupedToolCallCount(message.toolCalls);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

int _groupedToolCallCount(List<AgentToolCall> toolCalls) {
  var count = 0;
  var index = 0;
  while (index < toolCalls.length) {
    final toolCall = toolCalls[index];
    if (_isReadFileToolCall(toolCall)) {
      count += 1;
      index += 1;
      while (index < toolCalls.length &&
          _isReadFileToolCall(toolCalls[index])) {
        index += 1;
      }
      continue;
    }
    if (_isWriteFileToolCall(toolCall)) {
      count += 1;
      index += 1;
      while (index < toolCalls.length &&
          _isWriteFileToolCall(toolCalls[index])) {
        index += 1;
      }
      continue;
    }
    count += 1;
    index += 1;
  }
  return count;
}

class _ReasoningBlock extends StatelessWidget {
  const _ReasoningBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: const Color(0xFFE5E7EB)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCallCard extends StatefulWidget {
  const _ToolCallCard({
    required this.toolCall,
    required this.onLoadFullToolCall,
  });

  final AgentToolCall toolCall;
  final Future<AgentToolCall?> Function(AgentToolCall toolCall)
  onLoadFullToolCall;

  @override
  State<_ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<_ToolCallCard> {
  bool _expanded = false;
  AgentToolCall? _fullToolCall;
  bool _isLoadingFullToolCall = false;
  Object? _fullToolCallError;

  @override
  void didUpdateWidget(_ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolCall.callId != widget.toolCall.callId ||
        oldWidget.toolCall.historyMessageId !=
            widget.toolCall.historyMessageId) {
      _fullToolCall = null;
      _isLoadingFullToolCall = false;
      _fullToolCallError = null;
    }
  }

  Future<void> _toggleExpanded() async {
    final nextExpanded = !_expanded;
    setState(() => _expanded = nextExpanded);
    if (nextExpanded) {
      unawaited(_loadFullToolCallIfNeeded());
    }
  }

  Future<void> _loadFullToolCallIfNeeded() async {
    final compactCall = widget.toolCall;
    if (_fullToolCall != null || _isLoadingFullToolCall) return;
    if (!compactCall.outputTruncated && !compactCall.argumentsTruncated) return;
    setState(() {
      _isLoadingFullToolCall = true;
      _fullToolCallError = null;
    });
    try {
      final fullToolCall = await widget.onLoadFullToolCall(compactCall);
      if (!mounted) return;
      setState(() {
        _fullToolCall = fullToolCall;
        _isLoadingFullToolCall = false;
        if (fullToolCall == null) _fullToolCallError = 'not_found';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingFullToolCall = false;
        _fullToolCallError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final toolCall = _fullToolCall ?? widget.toolCall;
    final spec = _toolDisplaySpec(toolCall);
    final hasOutput = toolCall.output != null || toolCall.completedAt != null;
    final isAwaitingHuman = toolCall.awaitingHuman && !hasOutput;
    final isInterrupted =
        toolCall.interrupted && !hasOutput && !isAwaitingHuman;
    final isRunning =
        !toolCall.isComplete && !isAwaitingHuman && !isInterrupted;
    final isError = toolCall.isError;
    final isCompactHistoryPreview =
        toolCall.outputTruncated || toolCall.argumentsTruncated;
    final accent = isError
        ? _toolFailureColor
        : isInterrupted
        ? const Color(0xFF9CA3AF)
        : isAwaitingHuman
        ? spec.accent
        : isRunning
        ? const Color(0xFF2563EB)
        : spec.accent;
    final bg = isError ? _toolFailureSurface : const Color(0xFFF9FAFB);
    final border = isError ? _toolFailureBorder : const Color(0xFFE5E7EB);
    final duration = _formatDuration(toolCall.duration);
    final preview = spec.summary.trim().isNotEmpty
        ? spec.summary
        : _firstNonEmpty([
            toolCall.output,
            toolCall.streamingOutput,
            toolCall.arguments,
          ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: Key('tool_card_${toolCall.callId}'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    if (isRunning)
                      SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    else
                      Icon(
                        isError
                            ? Icons.error_outline_rounded
                            : isAwaitingHuman
                            ? Icons.hourglass_top_rounded
                            : isInterrupted
                            ? Icons.pause_circle_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 17,
                        color: accent,
                      ),
                    const SizedBox(width: 8),
                    Icon(spec.icon, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        spec.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isError ? accent : const Color(0xFF1F2937),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isRunning)
                      Text(
                        strings.toolRunning,
                        style: TextStyle(color: accent, fontSize: 12),
                      )
                    else if (isCompactHistoryPreview)
                      Text(
                        'preview',
                        style: TextStyle(color: accent, fontSize: 12),
                      )
                    else if (isAwaitingHuman)
                      Text(
                        strings.toolAwaitingHuman,
                        style: TextStyle(color: accent, fontSize: 12),
                      )
                    else if (isInterrupted)
                      Text(
                        strings.toolInterrupted,
                        style: TextStyle(color: accent, fontSize: 12),
                      )
                    else if (duration != null)
                      Text(
                        duration,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: const Color(0xFF6B7280),
                    ),
                  ],
                ),
              ),
            ),
            if (!_expanded && preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _formatCompactText(preview),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isError ? accent : const Color(0xFF6B7280),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (_isLoadingFullToolCall) ...[
                _FullToolCallLoadingRow(accent: accent),
                const SizedBox(height: 8),
              ] else if (_fullToolCallError != null &&
                  isCompactHistoryPreview) ...[
                _FullToolCallLoadErrorRow(accent: accent),
                const SizedBox(height: 8),
              ],
              _ToolExpandedContent(
                toolCall: toolCall,
                spec: spec,
                strings: strings,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FullToolCallLoadingRow extends StatelessWidget {
  const _FullToolCallLoadingRow({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
        const SizedBox(width: 7),
        const Text(
          'Loading full raw details...',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FullToolCallLoadErrorRow extends StatelessWidget {
  const _FullToolCallLoadErrorRow({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: accent),
        const SizedBox(width: 7),
        const Expanded(
          child: Text(
            'Full raw details are unavailable; showing history preview.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

enum _ToolDisplayKind {
  shell,
  web,
  browser,
  writeFile,
  memory,
  skill,
  platform,
  mcp,
  delegation,
  plan,
  generic,
}

class _ToolDisplaySpec {
  const _ToolDisplaySpec({
    required this.kind,
    required this.title,
    required this.summary,
    required this.icon,
    required this.accent,
  });

  final _ToolDisplayKind kind;
  final String title;
  final String summary;
  final IconData icon;
  final Color accent;
}

class _ToolExpandedContent extends StatelessWidget {
  const _ToolExpandedContent({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    if (spec.kind == _ToolDisplayKind.shell) {
      return _ShellToolView(toolCall: toolCall);
    }
    if (spec.kind == _ToolDisplayKind.web) {
      return _WebToolView(toolCall: toolCall, spec: spec, strings: strings);
    }
    if (spec.kind == _ToolDisplayKind.browser) {
      return _BrowserToolView(toolCall: toolCall, spec: spec, strings: strings);
    }
    if (spec.kind == _ToolDisplayKind.memory) {
      return _MemoryToolView(toolCall: toolCall, spec: spec, strings: strings);
    }
    if (spec.kind == _ToolDisplayKind.platform) {
      return _PlatformToolView(
        toolCall: toolCall,
        spec: spec,
        strings: strings,
      );
    }
    if (spec.kind == _ToolDisplayKind.mcp) {
      return _McpToolView(toolCall: toolCall, spec: spec, strings: strings);
    }
    if (spec.kind == _ToolDisplayKind.plan) {
      return _PlanToolView(toolCall: toolCall);
    }
    return _StructuredToolView(
      toolCall: toolCall,
      spec: spec,
      strings: strings,
    );
  }
}

/// Renders a Codex `turn/plan/updated` checklist: per-step status icons
/// (pending / in progress / completed) read from `toolCall.arguments`.
class _PlanToolView extends StatelessWidget {
  const _PlanToolView({required this.toolCall});

  final AgentToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    final args = _decodeJsonMap(toolCall.arguments);
    final explanation = _stringField(args, ['explanation']).trim();
    final steps = (args['steps'] as List?)
            ?.whereType<Map>()
            .map((step) => Map<String, dynamic>.from(step))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (explanation.isNotEmpty) ...[
          Text(
            explanation,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
        ],
        for (final step in steps) _PlanStepRow(step: step),
        if (steps.isEmpty)
          const Text(
            'No plan steps yet.',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
      ],
    );
  }
}

class _PlanStepRow extends StatelessWidget {
  const _PlanStepRow({required this.step});

  final Map<String, dynamic> step;

  @override
  Widget build(BuildContext context) {
    final status = step['status']?.toString().trim().toLowerCase() ?? '';
    final text = step['step']?.toString().trim() ?? '';
    final (icon, color) = switch (status) {
      'completed' => (
        Icons.check_circle_rounded,
        const Color(0xFF059669),
      ),
      'inprogress' => (
        Icons.radio_button_checked_rounded,
        const Color(0xFF2563EB),
      ),
      _ => (
        Icons.radio_button_unchecked_rounded,
        const Color(0xFF9CA3AF),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.isEmpty ? '(unnamed step)' : text,
              style: TextStyle(
                color: status == 'completed'
                    ? const Color(0xFF6B7280)
                    : const Color(0xFF1F2937),
                fontSize: 13,
                height: 1.35,
                decoration: status == 'completed'
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _planSummary(Map<String, dynamic> args) {
  final steps = (args['steps'] as List?)?.whereType<Map>() ?? const [];
  var completed = 0;
  var total = 0;
  for (final step in steps) {
    total++;
    if (step['status']?.toString().trim().toLowerCase() == 'completed') {
      completed++;
    }
  }
  if (total == 0) return 'Planning…';
  return 'Plan · $completed/$total done';
}

class _ShellToolView extends StatelessWidget {
  const _ShellToolView({required this.toolCall});

  final AgentToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    final command = _stringField(_decodeJsonMap(toolCall.arguments), [
      'command',
      'cmd',
    ]);
    final terminalChunks = _terminalChunks(toolCall);
    final statusColor = toolCall.isError
        ? _toolFailureTerminalColor
        : toolCall.isComplete
        ? const Color(0xFF86EFAC)
        : const Color(0xFF93C5FD);
    final status = toolCall.isError
        ? 'failed'
        : toolCall.isComplete
        ? 'done'
        : 'running';
    final duration = _formatDuration(toolCall.duration);

    return Container(
      key: Key('tool_terminal_${toolCall.callId}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 15,
                  color: Color(0xFFD1D5DB),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    command.isEmpty ? 'shell' : '\$ $command',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF9FAFB),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  duration == null ? status : '$status - $duration',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF374151)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (command.isNotEmpty)
                    _TerminalLine(
                      prefix: r'$',
                      text: command,
                      color: const Color(0xFFE5E7EB),
                      alignPrefix: false,
                    ),
                  if (terminalChunks.isEmpty)
                    const _TerminalLine(
                      prefix: '',
                      text: 'No output yet.',
                      color: Color(0xFF9CA3AF),
                    )
                  else
                    for (final chunk in terminalChunks)
                      _TerminalLine(
                        prefix: chunk.isStderr ? 'stderr' : 'stdout',
                        text: chunk.content,
                        color: chunk.isStderr
                            ? _toolFailureTerminalColor
                            : const Color(0xFFD1D5DB),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalLine extends StatelessWidget {
  const _TerminalLine({
    required this.prefix,
    required this.text,
    required this.color,
    this.alignPrefix = true,
  });

  final String prefix;
  final String text;
  final Color color;
  final bool alignPrefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text.rich(
        TextSpan(
          children: [
            if (prefix.isNotEmpty)
              TextSpan(
                text: alignPrefix ? prefix.padRight(7) : '$prefix ',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(
          color: color,
          fontSize: 12,
          height: 1.35,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _WebToolView extends StatefulWidget {
  const _WebToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  State<_WebToolView> createState() => _WebToolViewState();
}

class _WebToolViewState extends State<_WebToolView> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final toolCall = widget.toolCall;
    final name = _canonicalToolName(toolCall.name);
    final args = _decodeJsonMap(toolCall.arguments);
    final output = toolCall.output ?? '';
    final outputMap = _decodeJsonMap(output);
    final searchResults = name == 'web_search'
        ? _parseWebSearchResults(output)
        : const <_WebSearchResult>[];
    final rows = _toolInfoRows(toolCall, widget.spec.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isNotEmpty) ...[
          _ToolInfoPanel(rows: rows, accent: widget.spec.accent),
          const SizedBox(height: 8),
        ],
        if (searchResults.isNotEmpty)
          _WebSearchResultsView(results: searchResults)
        else
          _WebContentPreview(
            toolName: name,
            args: args,
            output: output,
            outputMap: outputMap,
            isError: toolCall.isError,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(
              _showRaw
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 17,
            ),
            label: Text(_showRaw ? 'Hide raw details' : 'Raw details'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 6),
          _ToolPayloadSection(
            label: widget.strings.toolArguments,
            text: toolCall.arguments,
            compactPreview: toolCall.argumentsTruncated,
          ),
          if (toolCall.streamingOutput.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: widget.strings.toolOutput,
              text: toolCall.streamingOutput,
              monospace: true,
            ),
          ],
          if (toolCall.output != null) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: toolCall.isError
                  ? widget.strings.toolError
                  : widget.strings.toolResult,
              text: toolCall.output!,
              isError: toolCall.isError,
              compactPreview: toolCall.outputTruncated,
            ),
          ],
        ],
      ],
    );
  }
}

class _WebSearchResult {
  const _WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;
}

class _WebSearchResultsView extends StatelessWidget {
  const _WebSearchResultsView({required this.results});

  final List<_WebSearchResult> results;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < results.length; i++) ...[
            _WebSearchResultCard(index: i + 1, result: results[i]),
            if (i != results.length - 1)
              const Divider(height: 14, color: Color(0xFFE5E7EB)),
          ],
        ],
      ),
    );
  }
}

class _WebSearchResultCard extends StatelessWidget {
  const _WebSearchResultCard({required this.index, required this.result});

  final int index;
  final _WebSearchResult result;

  @override
  Widget build(BuildContext context) {
    final title = result.title.trim().isEmpty
        ? result.url
        : result.title.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '[$index]',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (result.url.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  result.url,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              if (result.snippet.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  result.snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WebContentPreview extends StatelessWidget {
  const _WebContentPreview({
    required this.toolName,
    required this.args,
    required this.output,
    required this.outputMap,
    required this.isError,
  });

  final String toolName;
  final Map<String, dynamic> args;
  final String output;
  final Map<String, dynamic> outputMap;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final content = _webPrimaryContent(toolName, args, output, outputMap);
    final savedTo = _stringField(outputMap, ['saved_to']);
    final size = _stringField(outputMap, ['size_bytes']);
    final truncated = _stringField(outputMap, ['truncated']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isError ? _toolFailureBorder : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (savedTo.isNotEmpty) ...[
            _WebMetaRow(
              icon: Icons.download_done_rounded,
              text: size.isEmpty
                  ? 'Saved to $savedTo'
                  : 'Saved to $savedTo ($size bytes)',
            ),
            const SizedBox(height: 8),
          ],
          Text(
            content.isEmpty ? 'No readable response body.' : content,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isError ? _toolFailureColor : const Color(0xFF374151),
              fontSize: 12,
              height: 1.4,
              fontFamily: _looksLikeStructuredText(content)
                  ? 'monospace'
                  : null,
            ),
          ),
          if (truncated == 'true') ...[
            const SizedBox(height: 8),
            const _WebMetaRow(
              icon: Icons.content_cut_rounded,
              text:
                  'Preview truncated. Open raw details for the full tool output.',
            ),
          ],
        ],
      ),
    );
  }
}

class _WebMetaRow extends StatelessWidget {
  const _WebMetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF6B7280)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MemoryToolView extends StatefulWidget {
  const _MemoryToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  State<_MemoryToolView> createState() => _MemoryToolViewState();
}

class _MemoryToolViewState extends State<_MemoryToolView> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final toolCall = widget.toolCall;
    final name = _canonicalToolName(toolCall.name);
    final args = _decodeJsonMap(toolCall.arguments);
    final output = toolCall.output ?? '';
    final result = _decodeJsonMap(output);
    final error = _memoryError(toolCall, result, output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error.isNotEmpty)
          _PlatformStatusPanel(
            icon: Icons.error_outline_rounded,
            title: 'Memory failed',
            message: error,
            color: _toolFailureColor,
          )
        else
          _MemoryResultPreview(
            toolName: name,
            args: args,
            output: output,
            result: result,
            accent: widget.spec.accent,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(
              _showRaw
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 17,
            ),
            label: Text(_showRaw ? 'Hide raw details' : 'Raw details'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 6),
          _ToolPayloadSection(
            label: widget.strings.toolArguments,
            text: toolCall.arguments,
            compactPreview: toolCall.argumentsTruncated,
          ),
          if (toolCall.output != null) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: toolCall.isError
                  ? widget.strings.toolError
                  : widget.strings.toolResult,
              text: toolCall.output!,
              isError: toolCall.isError,
              compactPreview: toolCall.outputTruncated,
            ),
          ],
        ],
      ],
    );
  }
}

class _MemoryResultPreview extends StatelessWidget {
  const _MemoryResultPreview({
    required this.toolName,
    required this.args,
    required this.output,
    required this.result,
    required this.accent,
  });

  final String toolName;
  final Map<String, dynamic> args;
  final String output;
  final Map<String, dynamic> result;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (toolName == 'memory_read') {
      return _MemoryDocumentPreview(
        title: _stringField(result, ['path']),
        content: _stringField(result, ['content']),
        wordCount: _stringField(result, ['word_count']),
        accent: accent,
      );
    }
    if (toolName == 'memory_write') {
      return _PlatformKeyResultPanel(
        icon: Icons.edit_note_rounded,
        title: _firstNonEmpty([
          _stringField(result, ['path']),
          _stringField(args, ['target']),
          'Memory written',
        ]),
        rows: [
          _platformRow('status', _stringField(result, ['status'])),
          _platformRow('append', _stringField(result, ['append'])),
          _platformRow('length', _stringField(result, ['content_length'])),
          _platformRow('message', _stringField(result, ['message'])),
        ],
        accent: accent,
      );
    }
    if (toolName == 'memory_search') {
      final results = _listField(result, ['results']);
      return _MemorySearchPreview(
        query: _firstNonEmpty([
          _stringField(result, ['query']),
          _stringField(args, ['query']),
        ]),
        results: results,
        count: _stringField(result, ['result_count']),
        accent: accent,
      );
    }
    if (toolName == 'memory_tree') {
      final lines = _memoryTreeLines(_decodeJsonValue(output));
      return _MemoryTreePreview(
        root: _stringField(args, ['path']),
        lines: lines,
        accent: accent,
      );
    }
    return _PlatformKeyResultPanel(
      icon: Icons.storage_rounded,
      title: _memorySummary(toolName, args, output, false),
      rows: [
        _platformRow('path', _stringField(result, ['path'])),
        _platformRow('result', _formatCompactText(output)),
      ],
      accent: accent,
    );
  }
}

class _MemoryDocumentPreview extends StatelessWidget {
  const _MemoryDocumentPreview({
    required this.title,
    required this.content,
    required this.wordCount,
    required this.accent,
  });

  final String title;
  final String content;
  final String wordCount;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Memory file' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (wordCount.isNotEmpty) _PlatformChip(text: '$wordCount words'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content.isEmpty ? 'No content.' : content,
            maxLines: 10,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorySearchPreview extends StatelessWidget {
  const _MemorySearchPreview({
    required this.query,
    required this.results,
    required this.count,
    required this.accent,
  });

  final String query;
  final List<Map<String, dynamic>> results;
  final String count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _McpListPreview(
      icon: Icons.manage_search_rounded,
      title: _firstNonEmpty([
        count.isEmpty ? null : '$count memory matches',
        results.isEmpty
            ? 'No memory matches'
            : '${results.length} memory matches',
      ]),
      subtitle: query.isEmpty ? '' : query,
      items: [
        for (final item in results.take(6))
          _McpListItem(
            title: _stringField(item, ['path']),
            subtitle: _stringField(item, ['content']),
            trailing: _stringField(item, ['score']),
          ),
      ],
      accent: accent,
    );
  }
}

class _MemoryTreePreview extends StatelessWidget {
  const _MemoryTreePreview({
    required this.root,
    required this.lines,
    required this.accent,
  });

  final String root;
  final List<String> lines;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  root.isEmpty ? 'Memory tree' : root,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            lines.isEmpty ? 'No files.' : lines.take(30).join('\n'),
            maxLines: 30,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              height: 1.35,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformToolView extends StatefulWidget {
  const _PlatformToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  State<_PlatformToolView> createState() => _PlatformToolViewState();
}

class _PlatformToolViewState extends State<_PlatformToolView> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final toolCall = widget.toolCall;
    final name = _canonicalToolName(toolCall.name);
    final args = _decodeJsonMap(toolCall.arguments);
    final output = toolCall.output ?? '';
    final result = _decodeJsonMap(output);
    final error = _platformErrorMessage(toolCall, result, output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error.isNotEmpty)
          _PlatformStatusPanel(
            icon: Icons.error_outline_rounded,
            title: 'Failed',
            message: error,
            color: _toolFailureColor,
          )
        else
          _PlatformResultPreview(
            toolCall: toolCall,
            toolName: name,
            args: args,
            result: result,
            output: output,
            accent: widget.spec.accent,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(
              _showRaw
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 17,
            ),
            label: Text(_showRaw ? 'Hide raw details' : 'Raw details'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 6),
          _ToolPayloadSection(
            label: widget.strings.toolArguments,
            text: toolCall.arguments,
            compactPreview: toolCall.argumentsTruncated,
          ),
          if (toolCall.streamingOutput.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: widget.strings.toolOutput,
              text: toolCall.streamingOutput,
              monospace: true,
            ),
          ],
          if (toolCall.output != null) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: toolCall.isError
                  ? widget.strings.toolError
                  : widget.strings.toolResult,
              text: toolCall.output!,
              isError: toolCall.isError,
              compactPreview: toolCall.outputTruncated,
            ),
          ],
        ],
      ],
    );
  }
}

class _PlatformResultPreview extends StatelessWidget {
  const _PlatformResultPreview({
    required this.toolCall,
    required this.toolName,
    required this.args,
    required this.result,
    required this.output,
    required this.accent,
  });

  final AgentToolCall toolCall;
  final String toolName;
  final Map<String, dynamic> args;
  final Map<String, dynamic> result;
  final String output;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (toolName == 'take_photo') {
      return _PlatformAttachmentPanel(
        icon: Icons.photo_camera_rounded,
        title: 'Photo captured',
        toolCall: toolCall,
        result: result,
        accent: accent,
        isImage: true,
      );
    }
    if (toolName == 'record_audio') {
      return _PlatformAttachmentPanel(
        icon: Icons.graphic_eq_rounded,
        title: 'Recording saved',
        toolCall: toolCall,
        result: result,
        accent: accent,
        isAudio: true,
      );
    }
    if (toolName == 'media_library') {
      final assets = _listField(result, ['assets']);
      final artifacts = _listField(result, ['artifacts', 'attachments']);
      final action = _stringField(result, ['action']).isEmpty
          ? _stringField(args, ['action'])
          : _stringField(result, ['action']);
      return _PlatformListPanel(
        icon: Icons.photo_library_rounded,
        title: _firstNonEmpty([
          artifacts.isEmpty ? '' : '${artifacts.length} media imported',
          assets.isEmpty ? '' : '${assets.length} media found',
          action.isEmpty ? '' : 'Media $action',
          'Media library',
        ]),
        items: [
          for (final item in (artifacts.isNotEmpty ? artifacts : assets).take(
            4,
          ))
            _firstNonEmpty([
              _stringField(item, ['name', 'filename']),
              _stringField(item, ['mimeType', 'mime_type', 'mediaType']),
              _stringField(item, ['assetId', 'artifactId']),
            ]),
        ],
        accent: accent,
      );
    }
    if (toolName == 'get_location') {
      return _PlatformKeyResultPanel(
        icon: Icons.location_on_rounded,
        title: _locationSummary(result).isEmpty
            ? 'Location'
            : _locationSummary(result),
        rows: [
          _platformRow('accuracy', _stringField(result, ['accuracy'])),
          _platformRow('altitude', _stringField(result, ['altitude'])),
          _platformRow('speed', _stringField(result, ['speed'])),
          _platformRow('time', _stringField(result, ['timestamp'])),
        ],
        accent: accent,
      );
    }
    if (toolName == 'get_device_info') {
      return _PlatformKeyResultPanel(
        icon: Icons.phone_iphone_rounded,
        title: _firstNonEmpty([
          _stringField(result, ['model', 'device_model']),
          _stringField(result, ['name']),
          'Device info',
        ]),
        rows: [
          _platformRow(
            'brand',
            _stringField(result, ['brand', 'manufacturer']),
          ),
          _platformRow('system', _stringField(result, ['system_name', 'os'])),
          _platformRow('version', _stringField(result, ['system_version'])),
          _platformRow('device', _stringField(result, ['device_id'])),
        ],
        accent: accent,
      );
    }
    if (toolName == 'get_contacts') {
      final contacts = _listField(result, ['contacts', 'items', 'results']);
      return _PlatformListPanel(
        icon: Icons.contacts_rounded,
        title: contacts.isEmpty
            ? 'No contacts returned'
            : '${contacts.length} contacts',
        items: [
          for (final contact in contacts.take(4))
            _firstNonEmpty([
              _stringField(contact, ['name', 'display_name']),
              _stringField(contact, ['phone', 'phone_number']),
              _stringField(contact, ['email']),
            ]),
        ],
        accent: accent,
      );
    }
    if (toolName == 'list_calendar_events') {
      final events = _listField(result, ['events', 'items', 'results']);
      return _PlatformListPanel(
        icon: Icons.event_rounded,
        title: events.isEmpty
            ? 'No events returned'
            : '${events.length} events',
        items: [
          for (final event in events.take(4))
            _firstNonEmpty([
              _stringField(event, ['title', 'summary']),
              _stringField(event, ['start']),
              _stringField(event, ['time']),
            ]),
        ],
        accent: accent,
      );
    }

    return _PlatformKeyResultPanel(
      icon: _platformToolIcon(toolName),
      title: _platformResultTitle(toolName, args, result, output),
      rows: _platformDetailRows(toolName, args, result),
      accent: accent,
    );
  }
}

class _PlatformStatusPanel extends StatelessWidget {
  const _PlatformStatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformAttachmentPanel extends StatelessWidget {
  const _PlatformAttachmentPanel({
    required this.icon,
    required this.title,
    required this.toolCall,
    required this.result,
    required this.accent,
    this.isImage = false,
    this.isAudio = false,
  });

  final IconData icon;
  final String title;
  final AgentToolCall toolCall;
  final Map<String, dynamic> result;
  final Color accent;
  final bool isImage;
  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    final filename = _stringField(result, ['filename', 'name']);
    final sandboxPath = _stringField(result, ['sandbox_path', 'path']);
    final filePath = _stringField(result, ['file_path', 'real_path']);
    final mimeType = _stringField(result, ['mime_type', 'mimeType']);
    final size = _formatByteField(
      _stringField(result, ['size_bytes', 'sizeBytes']),
    );
    final duration = _formatSecondsField(
      _stringField(result, ['duration_seconds', 'duration_secs']),
    );
    final localFile = _existingLocalFile([filePath, sandboxPath], toolCall);
    final localPath = localFile?.path ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _firstNonEmpty([filename, title]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (localPath.isNotEmpty)
                IconButton(
                  tooltip: 'Share file',
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => share.Share.shareXFiles([
                    share.XFile(localPath, name: filename, mimeType: mimeType),
                  ]),
                ),
            ],
          ),
          if (isImage && localFile != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                localFile,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ] else if (isImage) ...[
            const SizedBox(height: 8),
            _PlatformMediaPlaceholder(
              icon: Icons.image_rounded,
              text: sandboxPath.isEmpty ? 'Photo saved' : sandboxPath,
              accent: accent,
            ),
          ] else if (isAudio) ...[
            const SizedBox(height: 8),
            _PlatformAudioPreview(
              duration: duration,
              filePath: localPath,
              filename: filename,
              mimeType: mimeType,
              accent: accent,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: [
              if (mimeType.isNotEmpty) _PlatformChip(text: mimeType),
              if (size.isNotEmpty) _PlatformChip(text: size),
              if (duration.isNotEmpty) _PlatformChip(text: duration),
            ],
          ),
          if (sandboxPath.isNotEmpty) ...[
            const SizedBox(height: 6),
            _PlatformPathText(path: sandboxPath),
          ],
        ],
      ),
    );
  }
}

class _PlatformAudioPreview extends StatelessWidget {
  const _PlatformAudioPreview({
    required this.duration,
    required this.filePath,
    required this.filename,
    required this.mimeType,
    required this.accent,
  });

  final String duration;
  final String filePath;
  final String filename;
  final String mimeType;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final canShare = filePath.isNotEmpty && File(filePath).existsSync();
    final foreground = canShare ? accent : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(
            canShare ? Icons.open_in_new_rounded : Icons.graphic_eq_rounded,
            size: 26,
            color: foreground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  duration.isEmpty ? 'Audio recording' : duration,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  canShare ? 'Open or share recording' : 'Saved in sandbox',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (canShare)
            IconButton(
              tooltip: 'Open or share recording',
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => share.Share.shareXFiles([
                share.XFile(filePath, name: filename, mimeType: mimeType),
              ]),
            ),
        ],
      ),
    );
  }
}

class _PlatformMediaPlaceholder extends StatelessWidget {
  const _PlatformMediaPlaceholder({
    required this.icon,
    required this.text,
    required this.accent,
  });

  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 124,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: accent),
          const SizedBox(height: 8),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformKeyResultPanel extends StatelessWidget {
  const _PlatformKeyResultPanel({
    required this.icon,
    required this.title,
    required this.rows,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final List<({String label, String value})> rows;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Completed' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _PlatformInlineRow(row: row),
              ),
          ],
        ],
      ),
    );
  }
}

class _PlatformListPanel extends StatelessWidget {
  const _PlatformListPanel({
    required this.icon,
    required this.title,
    required this.items,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((item) => item.trim().isNotEmpty).toList();
    return _PlatformKeyResultPanel(
      icon: icon,
      title: title,
      rows: [
        for (var i = 0; i < visible.length; i++)
          _platformRow('${i + 1}', visible[i]),
      ],
      accent: accent,
    );
  }
}

class _PlatformInlineRow extends StatelessWidget {
  const _PlatformInlineRow({required this.row});

  final ({String label, String value}) row;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${row.label}: ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: row.value),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 12,
        height: 1.35,
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PlatformPathText extends StatelessWidget {
  const _PlatformPathText({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      path,
      maxLines: 2,
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 11,
        height: 1.3,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _McpToolView extends StatefulWidget {
  const _McpToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  State<_McpToolView> createState() => _McpToolViewState();
}

class _McpToolViewState extends State<_McpToolView> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final toolCall = widget.toolCall;
    final name = _canonicalToolName(toolCall.name);
    final args = _decodeJsonMap(toolCall.arguments);
    final output = toolCall.output ?? '';
    final result = _decodeJsonMap(output);
    final isError = toolCall.isError || _mcpError(result).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isError)
          _PlatformStatusPanel(
            icon: Icons.error_outline_rounded,
            title: 'MCP failed',
            message: _firstNonEmpty([
              _mcpError(result),
              _formatCompactText(output),
              'MCP tool failed',
            ]),
            color: _toolFailureColor,
          )
        else
          _McpResultPreview(
            toolName: name,
            args: args,
            output: output,
            result: result,
            accent: widget.spec.accent,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(
              _showRaw
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 17,
            ),
            label: Text(_showRaw ? 'Hide raw details' : 'Raw details'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 6),
          _ToolPayloadSection(
            label: widget.strings.toolArguments,
            text: toolCall.arguments,
            compactPreview: toolCall.argumentsTruncated,
          ),
          if (toolCall.output != null) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: toolCall.isError
                  ? widget.strings.toolError
                  : widget.strings.toolResult,
              text: toolCall.output!,
              isError: toolCall.isError,
              compactPreview: toolCall.outputTruncated,
            ),
          ],
        ],
      ],
    );
  }
}

class _McpResultPreview extends StatelessWidget {
  const _McpResultPreview({
    required this.toolName,
    required this.args,
    required this.output,
    required this.result,
    required this.accent,
  });

  final String toolName;
  final Map<String, dynamic> args;
  final String output;
  final Map<String, dynamic> result;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final decoded = _decodeJsonValue(output);
    if (toolName == 'mcp_server_list' && decoded is List) {
      return _McpListPreview(
        icon: Icons.dns_rounded,
        title: decoded.isEmpty
            ? 'No MCP servers'
            : '${decoded.length} MCP servers',
        items: [
          for (final item in decoded)
            if (item is Map)
              _McpListItem(
                title: _stringField(Map<String, dynamic>.from(item), ['name']),
                subtitle: _firstNonEmpty([
                  _stringField(Map<String, dynamic>.from(item), ['url']),
                  _stringField(Map<String, dynamic>.from(item), ['transport']),
                ]),
                trailing: _mcpServerStatus(Map<String, dynamic>.from(item)),
              ),
        ],
        accent: accent,
      );
    }
    if (toolName == 'mcp_tool_list' && decoded is List) {
      return _McpListPreview(
        icon: Icons.extension_rounded,
        title: decoded.isEmpty ? 'No MCP tools' : '${decoded.length} MCP tools',
        items: [
          for (final item in decoded.take(8))
            if (item is Map)
              _McpListItem(
                title: _stringField(Map<String, dynamic>.from(item), ['name']),
                subtitle: _stringField(Map<String, dynamic>.from(item), [
                  'description',
                  'serverName',
                ]),
                trailing: _stringField(Map<String, dynamic>.from(item), [
                  'serverName',
                ]),
              ),
        ],
        accent: accent,
      );
    }
    if (toolName == 'mcp_server_add' || toolName == 'mcp_server_activate') {
      final tools = _stringListField(result, ['tools_loaded', 'tools']);
      return _McpListPreview(
        icon: Icons.hub_rounded,
        title: _firstNonEmpty([
          _stringField(result, ['name']),
          _stringField(args, ['name']),
          'MCP server activated',
        ]),
        subtitle: tools.isEmpty
            ? 'No tools loaded'
            : '${tools.length} tools loaded',
        items: [
          for (final tool in tools.take(6))
            _McpListItem(title: tool, subtitle: '', trailing: ''),
        ],
        accent: accent,
      );
    }
    if (toolName == 'mcp_server_deactivate' ||
        toolName == 'mcp_server_remove') {
      return _PlatformKeyResultPanel(
        icon: Icons.power_settings_new_rounded,
        title: toolName == 'mcp_server_remove'
            ? 'MCP server removed'
            : 'MCP server deactivated',
        rows: [
          _platformRow('server', _stringField(args, ['name'])),
          _platformRow('success', _stringField(result, ['success'])),
        ],
        accent: accent,
      );
    }

    return _PlatformKeyResultPanel(
      icon: Icons.hub_rounded,
      title: _mcpFriendlyTitle(toolName, args, output),
      rows: [
        _platformRow('server', _mcpServerName(toolName, args)),
        _platformRow('tool', _mcpRemoteToolName(toolName, args)),
        _platformRow('result', _formatCompactText(output)),
      ],
      accent: accent,
    );
  }
}

class _McpListItem {
  const _McpListItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;
}

class _McpListPreview extends StatelessWidget {
  const _McpListPreview({
    required this.icon,
    required this.title,
    required this.items,
    required this.accent,
    this.subtitle = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_McpListItem> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title.isEmpty ? 'Untitled' : item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.trailing.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _PlatformChip(text: item.trailing),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BrowserToolView extends StatefulWidget {
  const _BrowserToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  State<_BrowserToolView> createState() => _BrowserToolViewState();
}

class _BrowserToolViewState extends State<_BrowserToolView> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final toolCall = widget.toolCall;
    final name = _canonicalToolName(toolCall.name);
    final args = _decodeJsonMap(toolCall.arguments);
    final output = toolCall.output ?? '';
    final result = _decodeJsonMap(output);
    final error = _browserError(toolCall, result, output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error.isNotEmpty)
          _PlatformStatusPanel(
            icon: Icons.error_outline_rounded,
            title: 'Browser failed',
            message: error,
            color: _toolFailureColor,
          )
        else
          _BrowserResultPreview(
            toolName: name,
            args: args,
            result: result,
            output: output,
            accent: widget.spec.accent,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showRaw = !_showRaw),
            icon: Icon(
              _showRaw
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 17,
            ),
            label: Text(_showRaw ? 'Hide raw details' : 'Raw details'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (_showRaw) ...[
          const SizedBox(height: 6),
          _ToolPayloadSection(
            label: widget.strings.toolArguments,
            text: toolCall.arguments,
            compactPreview: toolCall.argumentsTruncated,
          ),
          if (toolCall.streamingOutput.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: widget.strings.toolOutput,
              text: toolCall.streamingOutput,
              monospace: true,
            ),
          ],
          if (toolCall.output != null) ...[
            const SizedBox(height: 8),
            _ToolPayloadSection(
              label: toolCall.isError
                  ? widget.strings.toolError
                  : widget.strings.toolResult,
              text: toolCall.output!,
              isError: toolCall.isError,
              compactPreview: toolCall.outputTruncated,
            ),
          ],
        ],
      ],
    );
  }
}

class _BrowserResultPreview extends StatelessWidget {
  const _BrowserResultPreview({
    required this.toolName,
    required this.args,
    required this.result,
    required this.output,
    required this.accent,
  });

  final String toolName;
  final Map<String, dynamic> args;
  final Map<String, dynamic> result;
  final String output;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final rows = _browserRows(toolName, args, result);
    final candidates = _browserCandidateItems(result);
    final screenshot = _browserScreenshotPath(result);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlatformKeyResultPanel(
          icon: _browserToolIcon(toolName),
          title: _browserResultTitle(toolName, args, result, output),
          rows: rows,
          accent: accent,
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 8),
          _McpListPreview(
            icon: Icons.ads_click_rounded,
            title: 'Visible browser targets',
            subtitle: 'Top candidates from the latest page state',
            items: candidates,
            accent: accent,
          ),
        ],
        if (screenshot.isNotEmpty) ...[
          const SizedBox(height: 8),
          _PlatformKeyResultPanel(
            icon: Icons.screenshot_monitor_rounded,
            title: 'Screenshot captured',
            rows: [_platformRow('path', screenshot)],
            accent: accent,
          ),
        ],
      ],
    );
  }
}

class _StructuredToolView extends StatelessWidget {
  const _StructuredToolView({
    required this.toolCall,
    required this.spec,
    required this.strings,
  });

  final AgentToolCall toolCall;
  final _ToolDisplaySpec spec;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final rows = _toolInfoRows(toolCall, spec.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isNotEmpty) ...[
          _ToolInfoPanel(rows: rows, accent: spec.accent),
          const SizedBox(height: 8),
        ],
        _ToolPayloadSection(
          label: strings.toolArguments,
          text: toolCall.arguments,
          compactPreview: toolCall.argumentsTruncated,
        ),
        if (toolCall.streamingOutput.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _ToolPayloadSection(
            label: strings.toolOutput,
            text: toolCall.streamingOutput,
            monospace: true,
          ),
        ],
        if (toolCall.output != null) ...[
          const SizedBox(height: 8),
          _ToolPayloadSection(
            label: toolCall.isError ? strings.toolError : strings.toolResult,
            text: toolCall.output!,
            isError: toolCall.isError,
            compactPreview: toolCall.outputTruncated,
          ),
        ],
      ],
    );
  }
}

class _ToolInfoPanel extends StatelessWidget {
  const _ToolInfoPanel({required this.rows, required this.accent});

  final List<({String label, String value})> rows;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${row.label}: ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: row.value),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolPayloadSection extends StatelessWidget {
  const _ToolPayloadSection({
    required this.label,
    required this.text,
    this.monospace = false,
    this.isError = false,
    this.compactPreview = false,
  });

  final String label;
  final String text;
  final bool monospace;
  final bool isError;
  final bool compactPreview;

  @override
  Widget build(BuildContext context) {
    final displayText = _formatPrettyText(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          compactPreview ? '$label preview' : label,
          style: TextStyle(
            color: isError ? _toolFailureColor : const Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            compactPreview && displayText.isNotEmpty
                ? '$displayText\n\nFull raw details are omitted from the initial history page.'
                : displayText.isEmpty
                ? '-'
                : displayText,
            style: TextStyle(
              color: isError ? _toolFailureColor : const Color(0xFF374151),
              fontSize: 12,
              height: 1.35,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

String? _formatDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return null;
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) return '${milliseconds}ms';
  final seconds = milliseconds / 1000;
  if (seconds < 10) return '${seconds.toStringAsFixed(1)}s';
  if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
  final minutes = duration.inMinutes;
  final remainingSeconds = duration.inSeconds.remainder(60);
  return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
}

String _formatCompactText(String text) {
  return _formatPrettyText(text).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _formatPrettyText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  try {
    final decoded = jsonDecode(trimmed);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(decoded);
  } catch (_) {
    return trimmed;
  }
}

String _basename(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) return 'file';
  final withoutTrailing = normalized.replaceAll(RegExp(r'/+$'), '');
  if (withoutTrailing.isEmpty) return normalized;
  final parts = withoutTrailing.split('/');
  return parts.last.isEmpty ? withoutTrailing : parts.last;
}

_ToolDisplaySpec _toolDisplaySpec(AgentToolCall toolCall) {
  final name = _canonicalToolName(toolCall.name);
  final args = _decodeJsonMap(toolCall.arguments);
  if (name == 'ask_human') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.generic,
      title: 'Ask user',
      summary: _stringField(args, ['question']),
      icon: Icons.help_outline_rounded,
      accent: const Color(0xFFD97706),
    );
  }
  if (name == 'plan') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.plan,
      title: 'Plan',
      summary: _planSummary(args),
      icon: Icons.checklist_rounded,
      accent: const Color(0xFF4F46E5),
    );
  }
  if (name == 'shell') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.shell,
      title: 'Shell',
      summary: _stringField(args, ['command', 'cmd']),
      icon: Icons.terminal_rounded,
      accent: const Color(0xFF059669),
    );
  }
  if (name == 'web_search') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.web,
      title: 'Web search',
      summary: _webSummary(name, args, toolCall.output),
      icon: Icons.travel_explore_rounded,
      accent: const Color(0xFF2563EB),
    );
  }
  if (name == 'web_fetch' || name == 'open_url') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.web,
      title: name == 'open_url' ? 'Open URL' : 'Web fetch',
      summary: _webSummary(name, args, toolCall.output),
      icon: Icons.public_rounded,
      accent: const Color(0xFF2563EB),
    );
  }
  if (name == 'http') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.web,
      title: 'HTTP request',
      summary: _webSummary(name, args, toolCall.output),
      icon: Icons.http_rounded,
      accent: const Color(0xFF2563EB),
    );
  }
  if (_isBrowserTool(name)) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.browser,
      title: _browserDisplayTitle(name),
      summary: _browserSummary(name, args, toolCall.output, toolCall.isError),
      icon: _browserToolIcon(name),
      accent: const Color(0xFF0F766E),
    );
  }
  if (name == 'write_file' || name == 'apply_patch') {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.writeFile,
      title: 'Write file',
      summary: _writeFilePreview(toolCall),
      icon: Icons.edit_note_rounded,
      accent: const Color(0xFFB45309),
    );
  }
  if (name.startsWith('memory_')) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.memory,
      title: _friendlyToolName(name),
      summary: _memorySummary(name, args, toolCall.output, toolCall.isError),
      icon: Icons.storage_rounded,
      accent: const Color(0xFF7C3AED),
    );
  }
  if (name.startsWith('skill_')) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.skill,
      title: _friendlyToolName(name),
      summary: _firstNonEmpty([
        _stringField(args, ['name', 'slug', 'query', 'url']),
        _stringField(args, ['content']),
      ]),
      icon: Icons.extension_rounded,
      accent: const Color(0xFF0891B2),
    );
  }
  if (_isMcpTool(name)) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.mcp,
      title: _mcpDisplayTitle(name),
      summary: _mcpSummary(name, args, toolCall.output, toolCall.isError),
      icon: Icons.hub_rounded,
      accent: const Color(0xFF0D9488),
    );
  }
  if (_isPlatformTool(name)) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.platform,
      title: _friendlyToolName(name),
      summary: _platformSummary(name, args, toolCall.output, toolCall.isError),
      icon: _platformToolIcon(name),
      accent: const Color(0xFF0F766E),
    );
  }
  if (toolCall.name.startsWith('delegate ·') || name.startsWith('delegate')) {
    return _ToolDisplaySpec(
      kind: _ToolDisplayKind.delegation,
      title: toolCall.name,
      summary: toolCall.arguments,
      icon: Icons.account_tree_rounded,
      accent: const Color(0xFF4F46E5),
    );
  }
  return _ToolDisplaySpec(
    kind: _ToolDisplayKind.generic,
    title: toolCall.name,
    summary: _firstNonEmpty([toolCall.arguments, toolCall.output]),
    icon: Icons.build_circle_outlined,
    accent: const Color(0xFF4B5563),
  );
}

bool _isBrowserTool(String name) {
  return name.startsWith('browser_');
}

String _browserDisplayTitle(String name) {
  return switch (name) {
    'browser_open' => 'Browser open',
    'browser_snapshot' => 'Browser snapshot',
    'browser_click' => 'Browser click',
    'browser_type' => 'Browser type',
    'browser_scroll' => 'Browser scroll',
    'browser_wait' => 'Browser wait',
    'browser_find_text' => 'Browser find text',
    'browser_keys' => 'Browser keys',
    'browser_back' => 'Browser back',
    'browser_close' => 'Browser close',
    _ => _friendlyToolName(name),
  };
}

IconData _browserToolIcon(String name) {
  return switch (name) {
    'browser_open' => Icons.open_in_browser_rounded,
    'browser_snapshot' => Icons.visibility_rounded,
    'browser_click' => Icons.ads_click_rounded,
    'browser_type' => Icons.keyboard_alt_rounded,
    'browser_scroll' => Icons.swap_vert_rounded,
    'browser_wait' => Icons.hourglass_empty_rounded,
    'browser_find_text' => Icons.manage_search_rounded,
    'browser_keys' => Icons.keyboard_command_key_rounded,
    'browser_back' => Icons.arrow_back_rounded,
    'browser_close' => Icons.close_fullscreen_rounded,
    _ => Icons.language_rounded,
  };
}

String _browserSummary(
  String name,
  Map<String, dynamic> args,
  String? output,
  bool isError,
) {
  final result = _decodeJsonMap(output ?? '');
  final error = _browserError(
    null,
    result,
    output ?? '',
    isErrorOverride: isError,
  );
  if (error.isNotEmpty) return 'Failed: $error';
  return switch (name) {
    'browser_open' => _firstNonEmpty([
      _browserPageLabel(args, result),
      _stringField(args, ['url']),
      'Opening page',
    ]),
    'browser_snapshot' => _firstNonEmpty([
      _browserSnapshotSummary(result),
      _browserPageLabel(args, result),
      'Reading page state',
    ]),
    'browser_click' => _firstNonEmpty([
      _browserTargetSummary(name, args, result),
      _browserPageLabel(args, result),
      'Clicking page',
    ]),
    'browser_type' => _firstNonEmpty([
      _browserTargetSummary(name, args, result),
      'Typing into page',
    ]),
    'browser_scroll' => _firstNonEmpty([
      _stringField(args, ['direction']),
      'Scrolling page',
    ]),
    'browser_wait' => _firstNonEmpty([
      _stringField(args, ['text']),
      _stringField(args, ['milliseconds', 'timeout_ms']),
      'Waiting for page',
    ]),
    'browser_find_text' => _firstNonEmpty([
      _stringField(args, ['text']),
      'Finding text',
    ]),
    'browser_keys' => _firstNonEmpty([
      _stringField(args, ['keys']),
      'Sending keys',
    ]),
    'browser_back' => 'Back navigation',
    'browser_close' => 'Close browser panel',
    _ => _browserPageLabel(args, result),
  };
}

String _browserResultTitle(
  String name,
  Map<String, dynamic> args,
  Map<String, dynamic> result,
  String output,
) {
  if (name == 'browser_snapshot') {
    return _firstNonEmpty([
      _browserSnapshotSummary(result),
      _browserPageLabel(args, result),
      'Page state captured',
    ]);
  }
  if (name == 'browser_click') {
    final effect = _browserLastActionEffect(result);
    return _firstNonEmpty([
      effect,
      _browserTargetSummary(name, args, result),
      'Click completed',
    ]);
  }
  if (name == 'browser_open') {
    return _firstNonEmpty([
      _browserPageLabel(args, result),
      _stringField(args, ['url']),
      'Page opened',
    ]);
  }
  return _firstNonEmpty([
    _browserSummary(name, args, output, false),
    _browserDisplayTitle(name),
  ]);
}

List<({String label, String value})> _browserRows(
  String name,
  Map<String, dynamic> args,
  Map<String, dynamic> result,
) {
  final rows = <({String label, String value})>[];

  void add(String label, String value) {
    final trimmed = _formatCompactText(value);
    if (trimmed.isNotEmpty) rows.add((label: label, value: trimmed));
  }

  add('url', _browserUrl(args, result));
  add('title', _browserPageTitle(result));
  add('target', _browserTargetSummary(name, args, result));
  add('mode', _browserMode(result));
  add('state', _browserStatus(result));
  add('elements', _browserElementCount(result));
  add('change', _browserLastActionEffect(result));
  return rows;
}

String _browserError(
  AgentToolCall? toolCall,
  Map<String, dynamic> result,
  String output, {
  bool? isErrorOverride,
}) {
  final isError = isErrorOverride ?? toolCall?.isError ?? false;
  final success = _stringField(result, ['success']).toLowerCase();
  final failureCode = _stringField(result, ['failure_code']);
  final reason = _firstNonEmpty([
    _stringField(result, ['blocked_or_approval_reason']),
    _stringField(result, ['error', 'message', 'reason']),
  ]);
  if (success == 'false' || failureCode.isNotEmpty) {
    return [
      failureCode,
      reason,
    ].where((part) => part.trim().isNotEmpty).join(': ');
  }
  if (!isError) return '';
  return _firstNonEmpty([
    reason,
    _formatCompactText(output),
    'Browser tool failed',
  ]);
}

String _browserTargetSummary(
  String name,
  Map<String, dynamic> args,
  Map<String, dynamic> result,
) {
  final target = _mapField(result, ['target']);
  final clickPoint = _mapField(args, ['click_point']);
  final point = clickPoint.isEmpty
      ? ''
      : [
          _stringField(clickPoint, ['x']),
          _stringField(clickPoint, ['y']),
        ].where((part) => part.isNotEmpty).join(', ');
  if (name == 'browser_type') {
    return _firstNonEmpty([
      _stringField(args, ['element_id', 'label', 'selector']),
      _stringField(target, ['element_id', 'label', 'text']),
      'Text field',
    ]);
  }
  return _firstNonEmpty([
    _stringField(args, ['element_id', 'text', 'label', 'selector']),
    _stringField(target, ['element_id', 'label', 'text', 'action_hint']),
    point.isEmpty ? null : 'point $point',
    _stringField(args, ['url']),
  ]);
}

String _browserPageLabel(
  Map<String, dynamic> args,
  Map<String, dynamic> result,
) {
  final title = _browserPageTitle(result);
  final url = _browserUrl(args, result);
  final host = _urlHost(url);
  return [if (title.isNotEmpty) title, if (host.isNotEmpty) host].join(' - ');
}

String _browserUrl(Map<String, dynamic> args, Map<String, dynamic> result) {
  final pageState = _mapField(result, ['page_state']);
  return _firstNonEmpty([
    _stringField(result, ['url']),
    _stringField(pageState, ['url']),
    _stringField(args, ['url']),
  ]);
}

String _browserPageTitle(Map<String, dynamic> result) {
  final pageState = _mapField(result, ['page_state']);
  return _firstNonEmpty([
    _stringField(result, ['title']),
    _stringField(pageState, ['title']),
  ]);
}

String _browserMode(Map<String, dynamic> result) {
  final pageState = _mapField(result, ['page_state']);
  return _firstNonEmpty([
    _stringField(result, ['browser_mode']),
    _stringField(pageState, ['browser_mode']),
  ]);
}

String _browserStatus(Map<String, dynamic> result) {
  final loading = _stringField(result, ['loading']);
  final success = _stringField(result, ['success']);
  final status = _stringField(result, ['status', 'status_code']);
  if (loading.toLowerCase() == 'true') return 'loading';
  if (success.toLowerCase() == 'true') return 'success';
  if (success.toLowerCase() == 'false') return 'failed';
  return status;
}

String _browserElementCount(Map<String, dynamic> result) {
  final pageState = _mapField(result, ['page_state']);
  final elements = _firstList([result['elements'], pageState['elements']]);
  if (elements.isEmpty) return '';
  return '${elements.length} visible';
}

String _browserSnapshotSummary(Map<String, dynamic> result) {
  final count = _browserElementCount(result);
  final page = _browserPageLabel(const {}, result);
  return [
    count.isEmpty ? null : count,
    page.isEmpty ? null : page,
  ].whereType<String>().join(' - ');
}

String _browserLastActionEffect(Map<String, dynamic> result) {
  final effect = _mapField(result, ['last_action_effect']);
  if (effect.isEmpty) return '';
  final changed = _stringField(effect, ['changed']);
  final reason = _firstNonEmpty([
    _stringField(effect, ['summary']),
    _stringField(effect, ['reason']),
    _stringField(effect, ['failure_code']),
  ]);
  if (changed.toLowerCase() == 'true') {
    return reason.isEmpty ? 'Page changed' : 'Page changed: $reason';
  }
  if (changed.toLowerCase() == 'false') {
    return reason.isEmpty ? 'No visible page change' : 'No change: $reason';
  }
  return reason;
}

String _browserScreenshotPath(Map<String, dynamic> result) {
  final screenshot = _mapField(result, ['screenshot']);
  return _stringField(screenshot, ['sandbox_path', 'path']);
}

List<_McpListItem> _browserCandidateItems(Map<String, dynamic> result) {
  final pageState = _mapField(result, ['page_state']);
  final viewportMap = _firstMap([
    result['viewport_map'],
    pageState['viewport_map'],
  ]);
  final candidates = <Map<String, dynamic>>[
    ..._listField(result, ['text_candidates', 'candidates']),
    ..._listField(pageState, ['elements']),
    ..._listField(viewportMap, ['visible_clickable_elements']),
  ];
  final seen = <String>{};
  final items = <_McpListItem>[];
  for (final candidate in candidates) {
    final title = _firstNonEmpty([
      _stringField(candidate, ['text', 'label', 'action_hint']),
      _stringField(candidate, ['element_id', 'kind', 'role']),
    ]);
    if (title.isEmpty) continue;
    final id = _stringField(candidate, ['element_id']);
    final key = '$id::$title';
    if (!seen.add(key)) continue;
    items.add(
      _McpListItem(
        title: title,
        subtitle: _firstNonEmpty([
          _stringField(candidate, ['nearby_text']),
          _stringField(candidate, ['clickable_reason']),
          _stringField(candidate, ['role', 'kind', 'tag']),
        ]),
        trailing: _firstNonEmpty([
          id,
          _stringField(candidate, ['action_hint']),
          _stringField(candidate, ['risk_hint']),
        ]),
      ),
    );
    if (items.length >= 5) break;
  }
  return items;
}

String _urlHost(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  return Uri.tryParse(trimmed)?.host ?? '';
}

String _webSummary(String toolName, Map<String, dynamic> args, String? output) {
  final outputMap = _decodeJsonMap(output ?? '');
  if (toolName == 'web_search') {
    final results = _parseWebSearchResults(output ?? '');
    if (results.isNotEmpty) {
      final first = results.first;
      final count = results.length;
      return '$count result${count == 1 ? '' : 's'}: ${first.title}';
    }
    return _labeledSummary('query', _stringField(args, ['query', 'q']));
  }
  if (toolName == 'http') {
    final method = _stringField(args, ['method']).toUpperCase();
    final url = _stringField(args, ['url']);
    final status = _stringField(outputMap, ['status']);
    final savedTo = _stringField(outputMap, ['saved_to']);
    final prefix = [
      method,
      status.isEmpty ? null : status,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    if (savedTo.isNotEmpty) {
      return [
        prefix,
        'saved $savedTo',
      ].where((part) => part.isNotEmpty).join(' - ');
    }
    return [prefix, url].where((part) => part.isNotEmpty).join(' ');
  }
  if (toolName == 'web_fetch') {
    final status = _stringField(outputMap, ['status']);
    final content = _stringField(outputMap, ['content']);
    if (content.isNotEmpty) {
      return [
        status.isEmpty ? null : status,
        _formatCompactText(content),
      ].whereType<String>().where((part) => part.isNotEmpty).join(' - ');
    }
  }
  return _firstNonEmpty([
    _stringField(outputMap, ['url']),
    _stringField(args, ['url']),
  ]);
}

String _webPrimaryContent(
  String toolName,
  Map<String, dynamic> args,
  String output,
  Map<String, dynamic> outputMap,
) {
  if (outputMap.isEmpty) return output.trim();
  if (toolName == 'web_fetch') {
    return _stringField(outputMap, ['content']);
  }
  if (toolName == 'http') {
    return _firstNonEmpty([
      _stringField(outputMap, ['body']),
      _stringField(outputMap, ['saved_to']),
    ]);
  }
  return _firstNonEmpty([
    _stringField(outputMap, ['content', 'body']),
    _stringField(args, ['url']),
    output,
  ]);
}

String _memorySummary(
  String toolName,
  Map<String, dynamic> args,
  String? output,
  bool isError,
) {
  final result = _decodeJsonMap(output ?? '');
  final error = _memoryError(
    null,
    result,
    output ?? '',
    isErrorOverride: isError,
  );
  if (error.isNotEmpty) return 'Failed: $error';
  return switch (toolName) {
    'memory_read' => _firstNonEmpty([
      _stringField(result, ['path']),
      _stringField(args, ['path']),
    ]),
    'memory_write' => _firstNonEmpty([
      _stringField(result, ['path']),
      _stringField(args, ['target']),
    ]),
    'memory_search' => _firstNonEmpty([
      [
        _stringField(result, ['result_count']),
        _stringField(args, ['query']),
      ].where((part) => part.isNotEmpty).join(' matches for '),
      _stringField(args, ['query']),
    ]),
    'memory_tree' => _firstNonEmpty([
      _stringField(args, ['path']),
      _labeledSummary('depth', _stringField(args, ['depth'])),
      'workspace root',
    ]),
    _ => _firstNonEmpty([
      _stringField(args, ['target', 'path', 'query']),
      _stringField(args, ['content']),
    ]),
  };
}

String _memoryError(
  AgentToolCall? toolCall,
  Map<String, dynamic> result,
  String output, {
  bool? isErrorOverride,
}) {
  final isError = isErrorOverride ?? toolCall?.isError ?? false;
  final explicit = _stringField(result, ['error', 'message']);
  if (explicit.isNotEmpty) return explicit;
  if (!isError) return '';
  return _firstNonEmpty([_formatCompactText(output), 'Memory tool failed']);
}

List<String> _memoryTreeLines(Object? value, [int depth = 0]) {
  final indent = List.filled(depth, '  ').join();
  final prefix = depth == 0 ? '' : '$indent- ';
  if (value is List) {
    return [for (final item in value) ..._memoryTreeLines(item, depth)];
  }
  if (value is Map) {
    return [
      for (final entry in value.entries) ...[
        '$prefix${entry.key}',
        ..._memoryTreeLines(entry.value, depth + 1),
      ],
    ];
  }
  if (value == null) return const [];
  return ['$prefix$value'];
}

List<_WebSearchResult> _parseWebSearchResults(String output) {
  final jsonResults = _parseJsonSearchResults(output);
  if (jsonResults.isNotEmpty) return jsonResults;

  final lines = output.split('\n');
  final results = <_WebSearchResult>[];
  String? title;
  String url = '';
  final snippet = <String>[];

  void flush() {
    final currentTitle = title?.trim() ?? '';
    if (currentTitle.isEmpty && url.trim().isEmpty) return;
    results.add(
      _WebSearchResult(
        title: currentTitle.isEmpty ? url.trim() : currentTitle,
        url: url.trim(),
        snippet: snippet.join(' ').trim(),
      ),
    );
    title = null;
    url = '';
    snippet.clear();
  }

  final itemPattern = RegExp(r'^\s*\d+\.\s+(.*)$');
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('Search results for:')) continue;
    final itemMatch = itemPattern.firstMatch(line);
    if (itemMatch != null) {
      flush();
      title = _stripMarkdown(itemMatch.group(1) ?? '');
      continue;
    }
    if (line.startsWith('http://') || line.startsWith('https://')) {
      url = line;
      continue;
    }
    if (title != null) snippet.add(_stripMarkdown(line));
  }
  flush();
  return results;
}

List<_WebSearchResult> _parseJsonSearchResults(String output) {
  final decoded = _decodeJsonValue(output);
  final list = switch (decoded) {
    {'results': final List value} => value,
    {'items': final List value} => value,
    List value => value,
    _ => const [],
  };
  return [
        for (final item in list)
          if (item is Map)
            _WebSearchResult(
              title: _stringField(Map<String, dynamic>.from(item), [
                'title',
                'name',
              ]),
              url: _stringField(Map<String, dynamic>.from(item), [
                'url',
                'link',
              ]),
              snippet: _stringField(Map<String, dynamic>.from(item), [
                'snippet',
                'description',
                'summary',
              ]),
            ),
      ]
      .where((result) => result.title.isNotEmpty || result.url.isNotEmpty)
      .toList();
}

Object? _decodeJsonValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
}

String _stripMarkdown(String text) {
  return text
      .replaceAll(RegExp(r'\*\*'), '')
      .replaceAll(RegExp(r'`'), '')
      .trim();
}

bool _looksLikeStructuredText(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('{') ||
      trimmed.startsWith('[') ||
      trimmed.contains('\n');
}

List<({String label, String value})> _toolInfoRows(
  AgentToolCall toolCall,
  _ToolDisplayKind kind,
) {
  final args = _decodeJsonMap(toolCall.arguments);
  final result = _decodeJsonMap(toolCall.output ?? '');
  final rows = <({String label, String value})>[];

  void add(String label, String value) {
    final trimmed = _formatCompactText(value);
    if (trimmed.isNotEmpty) rows.add((label: label, value: trimmed));
  }

  switch (kind) {
    case _ToolDisplayKind.web:
      add('method', _stringField(args, ['method']).toUpperCase());
      add('query', _stringField(args, ['query', 'q']));
      add(
        'url',
        _firstNonEmpty([
          _stringField(args, ['url']),
          _stringField(result, ['url']),
        ]),
      );
      add('status', _stringField(result, ['status', 'status_code']));
      break;
    case _ToolDisplayKind.browser:
      add('action', _browserDisplayTitle(_canonicalToolName(toolCall.name)));
      add(
        'target',
        _browserTargetSummary(_canonicalToolName(toolCall.name), args, result),
      );
      add('url', _browserUrl(args, result));
      add('title', _browserPageTitle(result));
      add('mode', _browserMode(result));
      add('status', _browserStatus(result));
      break;
    case _ToolDisplayKind.writeFile:
      add('status', _stringField(result, ['status']));
      add('files', _stringField(result, ['file_count']));
      break;
    case _ToolDisplayKind.memory:
      add('target', _stringField(args, ['target', 'path']));
      add('query', _stringField(args, ['query']));
      break;
    case _ToolDisplayKind.skill:
      add('name', _stringField(args, ['name', 'slug']));
      add('query', _stringField(args, ['query']));
      add('url', _stringField(args, ['url']));
      break;
    case _ToolDisplayKind.platform:
      add(
        'request',
        _platformSummary(_canonicalToolName(toolCall.name), args, null, false),
      );
      add('path', _stringField(result, ['sandbox_path', 'path']));
      add('location', _locationSummary(result));
      add('success', _stringField(result, ['success']));
      break;
    case _ToolDisplayKind.mcp:
      add('server', _mcpServerName(_canonicalToolName(toolCall.name), args));
      add('tool', _mcpRemoteToolName(_canonicalToolName(toolCall.name), args));
      add('url', _stringField(args, ['url']));
      break;
    case _ToolDisplayKind.delegation:
      add('task', toolCall.arguments);
      break;
    case _ToolDisplayKind.shell:
    case _ToolDisplayKind.plan:
    case _ToolDisplayKind.generic:
      break;
  }
  return rows;
}

List<AgentToolOutputChunk> _terminalChunks(AgentToolCall toolCall) {
  if (toolCall.outputChunks.isNotEmpty) return toolCall.outputChunks;
  if (toolCall.streamingOutput.trim().isNotEmpty) {
    return [
      AgentToolOutputChunk(stream: 'stdout', content: toolCall.streamingOutput),
    ];
  }
  final output = toolCall.output;
  if (output == null || output.trim().isEmpty) return const [];
  return [
    AgentToolOutputChunk(
      stream: toolCall.isError ? 'stderr' : 'stdout',
      content: output,
    ),
  ];
}

Map<String, dynamic> _decodeJsonMap(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

String _stringField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num || value is bool) return value.toString();
  }
  return '';
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _labeledSummary(String label, String value) {
  if (value.trim().isEmpty) return '';
  return '$label: $value';
}

String _canonicalToolName(String name) {
  final separatorIndex = name.lastIndexOf(' · ');
  if (separatorIndex == -1) return name.trim();
  return name.substring(separatorIndex + 3).trim();
}

String _friendlyToolName(String name) {
  return name
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

bool _isPlatformTool(String name) {
  return const {
    'open_url',
    'make_call',
    'send_sms',
    'get_clipboard',
    'set_clipboard',
    'get_device_info',
    'get_location',
    'send_notification',
    'get_contacts',
    'create_calendar_event',
    'list_calendar_events',
    'take_photo',
    'media_library',
    'record_audio',
    'set_alarm',
    'install_apk',
  }.contains(name);
}

bool _isMcpTool(String name) {
  if (name.startsWith('mcp_server_') || name == 'mcp_tool_list') return true;
  return false;
}

String _mcpDisplayTitle(String name) {
  return switch (name) {
    'mcp_server_list' => 'MCP servers',
    'mcp_server_add' => 'Add MCP server',
    'mcp_server_activate' => 'Activate MCP server',
    'mcp_server_deactivate' => 'Deactivate MCP server',
    'mcp_server_remove' => 'Remove MCP server',
    'mcp_tool_list' => 'MCP tools',
    _ => _friendlyToolName(name),
  };
}

String _mcpSummary(
  String name,
  Map<String, dynamic> args,
  String? output,
  bool isError,
) {
  final result = _decodeJsonMap(output ?? '');
  final error = _mcpError(result);
  if (isError || error.isNotEmpty) {
    return 'Failed: ${_firstNonEmpty([error, _formatCompactText(output ?? '')])}';
  }
  final decoded = _decodeJsonValue(output ?? '');
  if (name == 'mcp_server_list' && decoded is List) {
    return '${decoded.length} server${decoded.length == 1 ? '' : 's'}';
  }
  if (name == 'mcp_tool_list' && decoded is List) {
    return '${decoded.length} tool${decoded.length == 1 ? '' : 's'}';
  }
  if (name == 'mcp_server_add' || name == 'mcp_server_activate') {
    final tools = _stringListField(result, ['tools_loaded', 'tools']);
    return [
      _firstNonEmpty([
        _stringField(result, ['name']),
        _stringField(args, ['name']),
      ]),
      tools.isEmpty ? null : '${tools.length} tools',
    ].whereType<String>().where((part) => part.isNotEmpty).join(' - ');
  }
  return _firstNonEmpty([
    _stringField(args, ['name', 'server_name']),
    _stringField(args, ['url']),
    _formatCompactText(output ?? ''),
  ]);
}

String _mcpError(Map<String, dynamic> result) {
  return _stringField(result, ['error', 'message']);
}

String _mcpServerStatus(Map<String, dynamic> server) {
  final error = _mcpError(server);
  if (error.isNotEmpty) return 'error';
  final connected = _stringField(server, ['connected', 'active']);
  if (connected.toLowerCase() == 'true') return 'active';
  final pending = _stringField(server, ['oauthPending']);
  if (pending.toLowerCase() == 'true') return 'auth';
  return 'inactive';
}

String _mcpServerName(String toolName, Map<String, dynamic> args) {
  final explicit = _stringField(args, ['server_name', 'serverName', 'name']);
  if (explicit.isNotEmpty && toolName.startsWith('mcp_')) return explicit;
  if (!toolName.startsWith('mcp_') && toolName.contains('_')) {
    return toolName.split('_').first;
  }
  return explicit;
}

String _mcpRemoteToolName(String toolName, Map<String, dynamic> args) {
  final explicit = _stringField(args, ['tool', 'tool_name', 'name']);
  if (explicit.isNotEmpty && !toolName.startsWith('mcp_server_')) {
    return explicit;
  }
  if (!toolName.startsWith('mcp_') && toolName.contains('_')) {
    return toolName.substring(toolName.indexOf('_') + 1);
  }
  return '';
}

String _mcpFriendlyTitle(
  String toolName,
  Map<String, dynamic> args,
  String output,
) {
  return _firstNonEmpty([
    _mcpRemoteToolName(toolName, args),
    _mcpDisplayTitle(toolName),
    _formatCompactText(output),
  ]);
}

List<String> _stringListField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      return [
        for (final item in value)
          if (item != null && item.toString().trim().isNotEmpty)
            item.toString().trim(),
      ];
    }
  }
  return const [];
}

IconData _platformToolIcon(String name) {
  return switch (name) {
    'open_url' => Icons.open_in_browser_rounded,
    'make_call' || 'send_sms' => Icons.phone_rounded,
    'get_clipboard' || 'set_clipboard' => Icons.content_paste_rounded,
    'get_device_info' => Icons.phone_iphone_rounded,
    'get_location' => Icons.location_on_rounded,
    'send_notification' => Icons.notifications_rounded,
    'get_contacts' => Icons.contacts_rounded,
    'create_calendar_event' || 'list_calendar_events' => Icons.event_rounded,
    'take_photo' => Icons.photo_camera_rounded,
    'media_library' => Icons.photo_library_rounded,
    'record_audio' => Icons.mic_rounded,
    'set_alarm' => Icons.alarm_rounded,
    'install_apk' => Icons.install_mobile_rounded,
    _ => Icons.phone_iphone_rounded,
  };
}

String _platformSummary(
  String name,
  Map<String, dynamic> args,
  String? output,
  bool isError,
) {
  final result = _decodeJsonMap(output ?? '');
  final error = _platformErrorMessage(
    null,
    result,
    output ?? '',
    isErrorOverride: isError,
  );
  if (error.isNotEmpty) return 'Failed: $error';
  final hasResult = result.isNotEmpty;
  if (hasResult && name == 'take_photo') {
    return _firstNonEmpty([
      _stringField(result, ['filename', 'sandbox_path', 'file_path']),
      'Photo captured',
    ]);
  }
  if (hasResult && name == 'media_library') {
    final action = _firstNonEmpty([
      _stringField(result, ['action']),
      _stringField(args, ['action']),
    ]);
    final count = _stringField(result, ['count']);
    if (count.isNotEmpty) {
      return '$count media ${action.isEmpty ? 'items' : action}';
    }
    return action.isEmpty ? 'Media library' : 'Media $action';
  }
  if (hasResult && name == 'record_audio') {
    final duration = _formatSecondsField(
      _stringField(result, ['duration_seconds', 'duration_secs']),
    );
    return _firstNonEmpty([
      [
        'Recording saved',
        duration,
      ].where((part) => part.isNotEmpty).join(' - '),
      _stringField(result, ['filename', 'sandbox_path', 'file_path']),
    ]);
  }
  if (hasResult && name == 'get_location') {
    return _firstNonEmpty([_locationSummary(result), 'Location']);
  }
  return switch (name) {
    'open_url' => _stringField(args, ['url']),
    'make_call' || 'send_sms' => _stringField(args, ['phone_number']),
    'set_clipboard' => _stringField(args, ['text']),
    'send_notification' => _stringField(args, ['title']),
    'get_contacts' => _stringField(args, ['query']),
    'create_calendar_event' => _firstNonEmpty([
      _stringField(args, ['title']),
      _stringField(args, ['start']),
    ]),
    'list_calendar_events' => [
      _stringField(args, ['start']),
      _stringField(args, ['end']),
    ].where((part) => part.isNotEmpty).join(' - '),
    'record_audio' => _labeledSummary(
      'duration',
      _stringField(args, ['duration_seconds']),
    ),
    'media_library' => _firstNonEmpty([
      _stringField(args, ['action']),
      _labeledSummary('limit', _stringField(args, ['limit', 'max_count'])),
    ]),
    'set_alarm' => _firstNonEmpty([
      _stringField(args, ['time']),
      _stringField(args, ['message']),
    ]),
    'install_apk' => _stringField(args, ['path', 'apk_path']),
    _ => '',
  };
}

String _locationSummary(Map<String, dynamic> result) {
  final lat = _stringField(result, ['latitude', 'lat']);
  final lng = _stringField(result, ['longitude', 'lng', 'lon']);
  if (lat.isEmpty || lng.isEmpty) return '';
  return '$lat, $lng';
}

String _platformErrorMessage(
  AgentToolCall? toolCall,
  Map<String, dynamic> result,
  String output, {
  bool? isErrorOverride,
}) {
  final isError = isErrorOverride ?? toolCall?.isError ?? false;
  final explicit = _firstNonEmpty([
    _stringField(result, ['error', 'message', 'reason']),
    _stringField(result, ['error_message']),
  ]);
  if (explicit.isNotEmpty && (isError || result.containsKey('error'))) {
    return explicit;
  }
  if (_stringField(result, ['success']).toLowerCase() == 'false') {
    return explicit.isEmpty
        ? 'The platform action did not complete.'
        : explicit;
  }
  if (!isError) return '';
  return _firstNonEmpty([explicit, _formatCompactText(output), 'Tool failed']);
}

({String label, String value}) _platformRow(String label, String value) {
  return (label: label, value: _formatCompactText(value));
}

List<({String label, String value})> _platformDetailRows(
  String name,
  Map<String, dynamic> args,
  Map<String, dynamic> result,
) {
  final rows = <({String label, String value})>[];

  void add(String label, String value) {
    final trimmed = _formatCompactText(value);
    if (trimmed.isNotEmpty) rows.add((label: label, value: trimmed));
  }

  switch (name) {
    case 'open_url':
      add('url', _stringField(args, ['url']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'make_call':
      add('phone', _stringField(args, ['phone_number']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'send_sms':
      add('phone', _stringField(args, ['phone_number']));
      add('message', _stringField(args, ['message', 'body']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'get_clipboard':
      add('text', _stringField(result, ['text', 'content']));
      break;
    case 'set_clipboard':
      add('text', _stringField(args, ['text', 'content']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'send_notification':
      add('title', _stringField(args, ['title']));
      add('body', _stringField(args, ['body', 'message']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'create_calendar_event':
      add('title', _stringField(args, ['title', 'summary']));
      add('start', _stringField(args, ['start', 'start_time']));
      add('end', _stringField(args, ['end', 'end_time']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'set_alarm':
      add('time', _stringField(args, ['time']));
      add('message', _stringField(args, ['message', 'label']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    case 'install_apk':
      add('apk', _stringField(args, ['path', 'apk_path']));
      add('status', _stringField(result, ['status', 'success']));
      break;
    default:
      add('status', _stringField(result, ['status', 'success']));
      add('path', _stringField(result, ['sandbox_path', 'path', 'file_path']));
      break;
  }
  return rows;
}

String _platformResultTitle(
  String name,
  Map<String, dynamic> args,
  Map<String, dynamic> result,
  String output,
) {
  final success = _stringField(result, ['success']);
  final status = _stringField(result, ['status']);
  final completed = success.toLowerCase() == 'true' || status.isNotEmpty;
  final fallback = completed
      ? 'Completed'
      : _firstNonEmpty([output, 'Completed']);
  return switch (name) {
    'open_url' => _firstNonEmpty([
      _stringField(args, ['url']),
      fallback,
    ]),
    'make_call' => _firstNonEmpty([
      _stringField(args, ['phone_number']),
      'Call prepared',
    ]),
    'send_sms' => _firstNonEmpty([
      _stringField(args, ['phone_number']),
      'Message prepared',
    ]),
    'get_clipboard' => _firstNonEmpty([
      _stringField(result, ['text', 'content']),
      'Clipboard content',
    ]),
    'set_clipboard' => 'Copied to clipboard',
    'send_notification' => _firstNonEmpty([
      _stringField(args, ['title']),
      'Notification sent',
    ]),
    'create_calendar_event' => _firstNonEmpty([
      _stringField(args, ['title', 'summary']),
      'Calendar event created',
    ]),
    'set_alarm' => _firstNonEmpty([
      _stringField(args, ['time']),
      'Alarm set',
    ]),
    'install_apk' => 'APK install requested',
    _ => fallback,
  };
}

List<Map<String, dynamic>> _listField(
  Map<String, dynamic> map,
  List<String> keys,
) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map<String, dynamic>)
            item
          else if (item is Map)
            Map<String, dynamic>.from(item),
      ];
    }
  }
  return const [];
}

Map<String, dynamic> _mapField(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
  }
  return const {};
}

Map<String, dynamic> _firstMap(List<Object?> values) {
  for (final value in values) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
  }
  return const {};
}

List<Object?> _firstList(List<Object?> values) {
  for (final value in values) {
    if (value is List) return value;
  }
  return const [];
}

String _formatByteField(String value) {
  final bytes = int.tryParse(value);
  if (bytes == null) return value;
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

String _formatSecondsField(String value) {
  final seconds = double.tryParse(value);
  if (seconds == null) return value;
  if (seconds < 60) return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)}s';
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).round().toString().padLeft(2, '0');
  return '${minutes}m ${remainder}s';
}

File? _existingLocalFile(List<String> candidates, AgentToolCall toolCall) {
  for (final candidate in candidates) {
    for (final path in _localPathCandidates(candidate, toolCall)) {
      final file = File(path);
      if (file.existsSync()) return file;
    }
  }
  return null;
}

List<String> _localPathCandidates(String path, AgentToolCall toolCall) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return const [];
  final candidates = <String>[];
  if (!trimmed.startsWith('/workspace/') &&
      !trimmed.startsWith('/tmp/') &&
      !trimmed.startsWith('/skills/')) {
    candidates.add(trimmed);
  }
  if (sdk.NapaxiFileBridge.isInitialized) {
    final bridge = sdk.NapaxiFileBridge.instance;
    final agentId = _agentIdForToolCall(toolCall);
    final scoped = bridge.sandboxToRealScoped(
      trimmed,
      accountId: sdk.NapaxiEngine.defaultAccountId,
      agentId: agentId,
    );
    if (scoped != null) candidates.add(scoped);
    final unscoped = bridge.sandboxToReal(trimmed);
    if (unscoped != null) candidates.add(unscoped);
  }
  return candidates.toSet().toList();
}

String _agentIdForToolCall(AgentToolCall toolCall) {
  final separatorIndex = toolCall.name.lastIndexOf(' · ');
  if (separatorIndex == -1) return sdk.NapaxiEngine.defaultAgentId;
  final agentId = toolCall.name.substring(0, separatorIndex).trim();
  return agentId.isEmpty ? sdk.NapaxiEngine.defaultAgentId : agentId;
}
