part of '../main.dart';

bool _isA2AToolName(String name) {
  return switch (name.trim()) {
    'a2a_list_agents' ||
    'a2a_start_collaboration' ||
    'a2a_send_message' ||
    'a2a_wait_messages' ||
    'a2a_finish_collaboration' => true,
    _ => false,
  };
}

bool _isA2AToolCall(AgentToolCall call) => _isA2AToolName(call.name);

bool _hasVisibleAgentTrace(ChatMessage message) {
  if (message.reasoning.isNotEmpty || message.activatedSkills.isNotEmpty) {
    return true;
  }
  if (message.toolCalls.isEmpty) return false;
  return !message.toolCalls.every(_isA2AToolCall);
}

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({
    required this.message,
    required this.accountId,
    required this.agentId,
    required this.onOpenConfiguration,
    required this.isFavoriteAttachment,
    required this.onToggleFavoriteAttachment,
    required this.onLoadFullToolCall,
    required this.onCopyUserMessage,
    required this.onEditUserMessage,
    required this.onAnswerHumanRequest,
    required this.onOpenSkillOrganize,
    this.aggregatedAttachmentIdentities = const <String>{},
  });

  final ChatMessage message;
  final String accountId;
  final String agentId;
  final VoidCallback onOpenConfiguration;
  final bool Function(ChatAttachment attachment) isFavoriteAttachment;
  final ValueChanged<ChatAttachment> onToggleFavoriteAttachment;
  final Future<AgentToolCall?> Function(AgentToolCall toolCall)
  onLoadFullToolCall;
  final ValueChanged<ChatMessage> onCopyUserMessage;
  final ValueChanged<ChatMessage> onEditUserMessage;
  final void Function(String requestId, String response) onAnswerHumanRequest;
  final ValueChanged<ChatMessage> onOpenSkillOrganize;
  final Set<String> aggregatedAttachmentIdentities;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  final LayerLink _messageMenuLink = LayerLink();
  OverlayEntry? _messageMenuEntry;
  bool _isShowingMessageActions = false;

  @override
  void dispose() {
    _removeMessageActions(notify: false);
    super.dispose();
  }

  void _removeMessageActions({bool notify = true}) {
    _messageMenuEntry?.remove();
    _messageMenuEntry = null;
    if (notify && mounted && _isShowingMessageActions) {
      setState(() => _isShowingMessageActions = false);
    } else {
      _isShowingMessageActions = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final hasVisibleAgentTrace = !isUser && _hasVisibleAgentTrace(message);
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final maxWidth = isUser
        ? MediaQuery.sizeOf(context).width * 0.78
        : MediaQuery.sizeOf(context).width * 0.92;
    final displayAttachments = isUser
        ? message.attachments
        : [
            for (final attachment in message.attachments)
              if (!widget.aggregatedAttachmentIdentities.contains(
                _bubbleAttachmentIdentity(attachment),
              ))
                attachment,
          ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasVisibleAgentTrace)
          _AgentTraceSection(
            message: message,
            onLoadFullToolCall: widget.onLoadFullToolCall,
          ),
        if (hasVisibleAgentTrace && message.content.isNotEmpty)
          const SizedBox(height: 8),
        if (isUser && message.pinnedSkillNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final name in message.pinnedSkillNames)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.extension_rounded,
                          size: 11,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (message.content.isNotEmpty)
          isUser
              ? Text(
                  message.content,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    height: 1.42,
                  ),
                )
              : SelectionArea(
                  key: Key('assistant_message_selection_${message.id}'),
                  contextMenuBuilder: _buildAssistantSelectionMenu,
                  child: AssistantMarkdown(content: message.content),
                ),
        if (!isUser && message.humanRequest != null)
          _HumanRequestCard(
            request: message.humanRequest!,
            onAnswer: widget.onAnswerHumanRequest,
          ),
        if (!isUser && message.evolutionStatus != null) ...[
          if (message.content.isNotEmpty || message.humanRequest != null)
            const SizedBox(height: 8),
          _EvolutionStatusChip(
            status: message.evolutionStatus!,
            onTap: message.evolutionStatus!.stage == ChatEvolutionStage.pending
                ? () => widget.onOpenSkillOrganize(message)
                : null,
          ),
        ],
        if (message.content.isEmpty && !hasVisibleAgentTrace && message.isStreaming)
          const _AssistantWaitingIndicator(),
        if (displayAttachments.isNotEmpty) ...[
          if (message.content.isNotEmpty) const SizedBox(height: 10),
          _MessageAttachmentsView(
            attachments: displayAttachments,
            accountId: widget.accountId,
            agentId: widget.agentId,
            isFavoriteAttachment: widget.isFavoriteAttachment,
            onToggleFavoriteAttachment: widget.onToggleFavoriteAttachment,
          ),
        ],
        if (!isUser && message.action != null) ...[
          const SizedBox(height: 10),
          _ChatMessageActionButton(
            action: message.action!,
            onOpenConfiguration: widget.onOpenConfiguration,
          ),
        ],
      ],
    );

    if (!isUser) {
      return Align(
        alignment: alignment,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
          child: content,
        ),
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(4),
        ),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: content,
    );

    return Align(
      alignment: alignment,
      child: CompositedTransformTarget(
        link: _messageMenuLink,
        child: GestureDetector(
          key: Key('chat_message_${message.id}'),
          onLongPress: _showUserMessageActions,
          child: AnimatedScale(
            scale: _isShowingMessageActions ? 1.03 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: bubble,
          ),
        ),
      ),
    );
  }

  void _showUserMessageActions() {
    _removeMessageActions();
    final strings = AppStrings.of(context);
    final overlay = Overlay.of(context);
    setState(() => _isShowingMessageActions = true);
    _messageMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeMessageActions,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _messageMenuLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 2),
              child: _UserMessageActionOverlay(
                copyLabel: strings.copyMessage,
                editLabel: strings.editMessage,
                onCopy: () {
                  _removeMessageActions();
                  widget.onCopyUserMessage(widget.message);
                },
                onEdit: () {
                  _removeMessageActions();
                  widget.onEditUserMessage(widget.message);
                },
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_messageMenuEntry!);
  }

  Widget _buildAssistantSelectionMenu(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final strings = AppStrings.of(context);
    final buttonItems = selectableRegionState.contextMenuButtonItems
        .map(
          (item) => switch (item.type) {
            ContextMenuButtonType.copy => item.copyWith(
              label: strings.copyMessage,
            ),
            ContextMenuButtonType.selectAll => item.copyWith(
              label: strings.selectAllMessage,
            ),
            ContextMenuButtonType.share => item.copyWith(
              label: strings.shareFile,
            ),
            _ => item,
          },
        )
        .toList(growable: false);
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}

class _UserMessageActionOverlay extends StatelessWidget {
  const _UserMessageActionOverlay({
    required this.copyLabel,
    required this.editLabel,
    required this.onCopy,
    required this.onEdit,
  });

  final String copyLabel;
  final String editLabel;
  final VoidCallback onCopy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('user_message_action_overlay'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UserMessageActionButton(
                key: const Key('copy_user_message_action'),
                icon: Icons.copy_rounded,
                label: copyLabel,
                onTap: onCopy,
              ),
              const SizedBox(width: 2),
              _UserMessageActionButton(
                key: const Key('edit_user_message_action'),
                icon: Icons.edit_rounded,
                label: editLabel,
                onTap: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserMessageActionButton extends StatelessWidget {
  const _UserMessageActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF374151)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvolutionStatusChip extends StatelessWidget {
  const _EvolutionStatusChip({required this.status, this.onTap});

  final ChatEvolutionStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final (label, icon, color) = switch (status.stage) {
      ChatEvolutionStage.reviewing => (
        strings.evolutionReviewing,
        Icons.auto_awesome_motion_rounded,
        const Color(0xFF64748B),
      ),
      ChatEvolutionStage.reviewed => (
        strings.evolutionReviewed,
        Icons.check_rounded,
        const Color(0xFF64748B),
      ),
      ChatEvolutionStage.updated => (
        _updatedLabel(strings, status.reviewTypes),
        Icons.auto_awesome_rounded,
        const Color(0xFF047857),
      ),
      ChatEvolutionStage.pending => (
        strings.evolutionPendingSuggestions(status.pendingCount),
        Icons.rule_rounded,
        const Color(0xFFB45309),
      ),
      ChatEvolutionStage.failed => (
        strings.evolutionFailed,
        Icons.info_outline_rounded,
        const Color(0xFF6B7280),
      ),
    };

    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded, size: 14, color: color),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: chip,
      ),
    );
  }

  String _updatedLabel(AppStrings strings, List<String> reviewTypes) {
    if (reviewTypes.contains('skill')) return strings.evolutionSkillUpdated;
    return strings.evolutionMemoryUpdated;
  }
}

class _ChatMessageActionButton extends StatelessWidget {
  const _ChatMessageActionButton({
    required this.action,
    required this.onOpenConfiguration,
  });

  final ChatMessageAction action;
  final VoidCallback onOpenConfiguration;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final (label, onPressed) = switch (action) {
      ChatMessageAction.openConfiguration => (
        strings.openConfiguration,
        onOpenConfiguration,
      ),
    };

    return TextButton.icon(
      key: Key('chat_action_${action.name}'),
      onPressed: onPressed,
      icon: const Icon(Icons.tune_rounded, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _HumanRequestCard extends StatelessWidget {
  const _HumanRequestCard({required this.request, required this.onAnswer});

  final HumanRequest request;
  final void Function(String requestId, String response) onAnswer;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isCancelled = request.cancelled;
    return Container(
      key: Key('human_request_${request.requestId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCancelled ? const Color(0xFFF3F4F6) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCancelled
              ? const Color(0xFFE5E7EB)
              : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.question,
            style: TextStyle(
              color: isCancelled
                  ? const Color(0xFF6B7280)
                  : const Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (request.context?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text(
              request.context!,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (isCancelled) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pause_circle_outline_rounded,
                  size: 14,
                  color: Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 4),
                Text(
                  strings.humanRequestCancelled,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (!isCancelled && request.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in request.options)
                  OutlinedButton(
                    key: Key('human_option_${request.requestId}_$option'),
                    onPressed: request.answered
                        ? null
                        : () => onAnswer(request.requestId, option),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111827),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(option),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantWaitingIndicator extends StatefulWidget {
  const _AssistantWaitingIndicator();

  @override
  State<_AssistantWaitingIndicator> createState() =>
      _AssistantWaitingIndicatorState();
}

class _AssistantWaitingIndicatorState extends State<_AssistantWaitingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.35,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            strings.thinking,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _bubbleAttachmentIdentity(ChatAttachment attachment) {
  final sandboxPath = attachment.sandboxPath?.trim();
  if (sandboxPath != null && sandboxPath.isNotEmpty) return sandboxPath;
  return attachment.path;
}

class _ConversationGeneratedAttachmentsView extends StatelessWidget {
  const _ConversationGeneratedAttachmentsView({
    super.key,
    required this.attachments,
    required this.accountId,
    required this.agentId,
    required this.isFavoriteAttachment,
    required this.onToggleFavoriteAttachment,
  });

  final List<ChatAttachment> attachments;
  final String accountId;
  final String agentId;
  final bool Function(ChatAttachment attachment) isFavoriteAttachment;
  final ValueChanged<ChatAttachment> onToggleFavoriteAttachment;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final maxWidth = MediaQuery.sizeOf(context).width * 0.92;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(top: 4, bottom: 14),
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: _MessageAttachmentsView(
          attachments: attachments,
          accountId: accountId,
          agentId: agentId,
          isFavoriteAttachment: isFavoriteAttachment,
          onToggleFavoriteAttachment: onToggleFavoriteAttachment,
        ),
      ),
    );
  }
}
