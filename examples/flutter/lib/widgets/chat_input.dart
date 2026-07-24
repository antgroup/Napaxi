part of '../main.dart';

class _PendingInterjectionQueue extends StatelessWidget {
  const _PendingInterjectionQueue({
    required this.language,
    required this.interjections,
  });

  final AppLanguage language;
  final List<PendingInterjection> interjections;

  @override
  Widget build(BuildContext context) {
    final isChinese = language == AppLanguage.chinese;
    final visibleInterjections = interjections.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        key: const Key('pending_interjection_queue'),
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isChinese ? '等待加入当前任务' : 'Waiting to join this run',
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < visibleInterjections.length; i++) ...[
                  _PendingInterjectionRow(
                    interjection: visibleInterjections[i],
                    isChinese: isChinese,
                  ),
                  if (i != visibleInterjections.length - 1)
                    const SizedBox(height: 6),
                ],
                if (interjections.length > 3) ...[
                  const SizedBox(height: 6),
                  Text(
                    isChinese
                        ? '还有 ${interjections.length - 3} 条等待中'
                        : '${interjections.length - 3} more queued',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingInterjectionRow extends StatelessWidget {
  const _PendingInterjectionRow({
    required this.interjection,
    required this.isChinese,
  });

  final PendingInterjection interjection;
  final bool isChinese;

  @override
  Widget build(BuildContext context) {
    final isFailed = interjection.status == PendingInterjectionStatus.failed;
    final text = interjection.content.trim().isEmpty
        ? (isChinese ? '附件消息' : 'Attachment message')
        : interjection.content.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isFailed ? Icons.error_outline_rounded : Icons.schedule_rounded,
          size: 15,
          color: isFailed ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            isFailed ? (isChinese ? '未加入：$text' : 'Not accepted: $text') : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isFailed
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF111827),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
        if (interjection.attachmentCount > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+${interjection.attachmentCount}',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _SlashCommandSpec {
  const _SlashCommandSpec({
    required this.name,
    this.aliases = const [],
    required this.title,
    required this.description,
    this.isSkillCommand = false,
    this.skillName,
  });

  final String name;
  final List<String> aliases;
  final String title;
  final String description;
  final bool isSkillCommand;
  final String? skillName;

  bool matches(String value) {
    final normalized = value.trim().toLowerCase();
    if (name == normalized) return true;
    return aliases.any((alias) => alias == normalized);
  }

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || normalized == '/') return true;
    return name.startsWith(normalized) ||
        aliases.any((alias) => alias.startsWith(normalized)) ||
        title.toLowerCase().contains(normalized.replaceFirst('/', ''));
  }
}

class _SlashCommandInvocation {
  const _SlashCommandInvocation({
    required this.command,
    required this.rawCommand,
    required this.arguments,
    required this.isKnown,
  });

  final _SlashCommandSpec command;
  final String rawCommand;
  final String arguments;
  final bool isKnown;

  static _SlashCommandInvocation? parse(
    String text,
    List<_SlashCommandSpec> commands,
  ) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return null;
    final parts = trimmed.split(RegExp(r'\s+'));
    final rawCommand = parts.first.toLowerCase();
    for (final command in commands) {
      if (!command.matches(rawCommand)) continue;
      return _SlashCommandInvocation(
        command: command,
        rawCommand: rawCommand,
        arguments: trimmed.substring(parts.first.length).trim(),
        isKnown: true,
      );
    }
    return _SlashCommandInvocation(
      command: commands.first,
      rawCommand: rawCommand,
      arguments: trimmed.substring(parts.first.length).trim(),
      isKnown: false,
    );
  }
}

class _ChatInputBar extends StatefulWidget {
  const _ChatInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    this.isEditing = false,
    required this.slashCommands,
    required this.contextStatus,
    required this.isContextStatusLoading,
    required this.hasContextSession,
    this.onCancelEdit,
    required this.onContextStatusTap,
    required this.onSend,
    required this.onStop,
    this.channelInputSources = const [],
    this.channelInputBusyAccountId,
    this.channelInputActiveAccountId,
    this.onChannelInputSelected,
    this.chatClient,
    this.agentId = '',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool isEditing;
  final List<_SlashCommandSpec> slashCommands;
  final sdk.ContextStatus? contextStatus;
  final bool isContextStatusLoading;
  final bool hasContextSession;
  final VoidCallback? onCancelEdit;
  final VoidCallback onContextStatusTap;
  final Future<void> Function(
    List<ChatAttachment> attachments, {
    List<String> pinnedSkillNames,
  })
  onSend;
  final Future<void> Function() onStop;
  final List<DemoChannelInputSource> channelInputSources;
  final String? channelInputBusyAccountId;
  final String? channelInputActiveAccountId;
  final ValueChanged<DemoChannelInputSource>? onChannelInputSelected;
  final NapaxiChatClient? chatClient;
  final String agentId;

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  static const int _maxAttachments = 24;

  final List<ChatAttachment> _attachments = [];
  final List<String> _pinnedSkillNames = [];
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _inputScrollController = ScrollController();
  final LayerLink _attachmentMenuLink = LayerLink();
  final GlobalKey _attachmentButtonKey = GlobalKey();

  bool _hasText = false;

  bool get _canSend => _hasText || _attachments.isNotEmpty;

  void _addPinnedSkill(String name) {
    if (_pinnedSkillNames.contains(name)) return;
    setState(() => _pinnedSkillNames.add(name));
  }

  void _removePinnedSkill(int index) {
    setState(() => _pinnedSkillNames.removeAt(index));
  }

  String? get _slashQuery {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isCollapsed || selection.baseOffset != text.length) {
      return null;
    }
    final trimmedLeft = text.trimLeft();
    if (!trimmedLeft.startsWith('/')) return null;
    if (trimmedLeft.contains('\n')) return null;
    return trimmedLeft.split(RegExp(r'\s+')).first;
  }

  List<_SlashCommandSpec> get _slashSuggestions {
    final query = _slashQuery;
    if (query == null) return const [];
    return widget.slashCommands
        .where((command) => command.matchesQuery(query))
        .take(5)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(_ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleTextChanged);
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _inputScrollController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText == _hasText) {
      setState(() {});
      return;
    }
    setState(() => _hasText = hasText);
  }

  void _selectSlashCommand(_SlashCommandSpec command) {
    widget.controller.value = TextEditingValue(
      text: '${command.name} ',
      selection: TextSelection.collapsed(offset: command.name.length + 1),
    );
    widget.focusNode.requestFocus();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    _addAttachments(
      result.files
          .where((file) => file.path != null)
          .map(
            (file) => ChatAttachment(
              name: file.name,
              path: file.path!,
              type: ChatAttachmentType.file,
            ),
          ),
    );
  }

  Future<void> _pickGalleryImage() async {
    final images = await _imagePicker.pickMultiImage();
    _addImageAttachments(images);
  }

  Future<void> _pickCameraImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image != null) _addImageAttachments([image]);
  }

  void _addImageAttachments(Iterable<XFile> images) {
    _addAttachments(
      images.map(
        (image) => ChatAttachment(
          name: image.name.isEmpty ? image.path.split('/').last : image.name,
          path: image.path,
          type: ChatAttachmentType.image,
        ),
      ),
    );
  }

  void _addAttachments(Iterable<ChatAttachment> attachments) {
    if (!mounted) return;
    setState(() {
      for (final attachment in attachments) {
        if (_attachments.length >= _maxAttachments) break;
        _attachments.add(attachment);
      }
    });
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _send() {
    if (!_canSend) return;
    widget.onSend(
      List<ChatAttachment>.unmodifiable(_attachments),
      pinnedSkillNames: List<String>.unmodifiable(_pinnedSkillNames),
    );
    setState(() {
      _attachments.clear();
      _pinnedSkillNames.clear();
      _hasText = false;
    });
  }

  void _openAttachmentMenu() {
    final box =
        _attachmentButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    void dismiss() => entry.remove();

    entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismiss,
            child: const SizedBox.expand(),
          ),
          CompositedTransformFollower(
            link: _attachmentMenuLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(0, -8),
            child: _AttachmentMenuOverlay(
              onFileTap: () {
                dismiss();
                _pickFile();
              },
              onGalleryTap: () {
                dismiss();
                _pickGalleryImage();
              },
              onCameraTap: () {
                dismiss();
                _pickCameraImage();
              },
              onSkillsTap: widget.chatClient != null
                  ? () {
                      dismiss();
                      _openSkillPicker();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
  }

  void _openSkillPicker() {
    final client = widget.chatClient;
    if (client == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _SkillPickerSheet(
          client: client,
          agentId: widget.agentId,
          alreadyPinned: _pinnedSkillNames.toSet(),
          scrollController: scrollController,
          onSkillSelected: (name) {
            _addPinnedSkill(name);
          },
        ),
      ),
    );
  }

  bool get _isChannelInputBusy =>
      widget.channelInputBusyAccountId?.trim().isNotEmpty == true;

  Future<void> _openChannelInputPicker() async {
    if (widget.channelInputSources.isEmpty) return;
    final callback = widget.onChannelInputSelected;
    if (callback == null) return;
    final activeAccountId = widget.channelInputActiveAccountId?.trim() ?? '';
    if (activeAccountId.isNotEmpty) {
      final activeSource = widget.channelInputSources.firstWhere(
        (source) => source.accountId == activeAccountId,
        orElse: () => widget.channelInputSources.first,
      );
      callback(activeSource);
      return;
    }
    if (_isChannelInputBusy) return;
    if (widget.channelInputSources.length == 1) {
      callback(widget.channelInputSources.first);
      return;
    }
    final selected = await showModalBottomSheet<DemoChannelInputSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) =>
          _ChannelInputPickerSheet(sources: widget.channelInputSources),
    );
    if (selected != null && mounted) callback(selected);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final slashSuggestions = _slashSuggestions;
    final isSendAction = !widget.isSending || _canSend;
    final sendColor = isSendAction && !_canSend
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF111827);
    final channelInputsAvailable =
        widget.channelInputSources.isNotEmpty &&
        widget.onChannelInputSelected != null;

    return DecoratedBox(
      decoration: const BoxDecoration(color: _appSurfaceColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          key: const Key('chat_input_container'),
          decoration: BoxDecoration(
            color: _appSurfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _appSurfaceBorderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isEditing) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
                  child: _EditingMessageHeader(
                    onCancelEdit: widget.onCancelEdit ?? () {},
                  ),
                ),
              ],
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: _AttachmentPreviewRow(
                    attachments: _attachments,
                    onRemove: _removeAttachment,
                  ),
                ),
              if (_pinnedSkillNames.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: _PinnedSkillChipsRow(
                    skills: _pinnedSkillNames,
                    onRemove: _removePinnedSkill,
                  ),
                ),
              if (slashSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _SlashCommandSuggestions(
                    commands: slashSuggestions,
                    onSelected: _selectSlashCommand,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 156),
                  child: Scrollbar(
                    controller: _inputScrollController,
                    child: TextField(
                      key: const Key('chat_input_field'),
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      scrollController: _inputScrollController,
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => widget.focusNode.unfocus(),
                      decoration: InputDecoration(
                        hintText: strings.messageHint,
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 6, 6),
                child: Row(
                  children: [
                    CompositedTransformTarget(
                      link: _attachmentMenuLink,
                      child: _ToolbarIconButton(
                        key: _attachmentButtonKey,
                        semanticKey: const Key('add_attachment_button'),
                        icon: Icons.add_rounded,
                        tooltip: strings.addAttachmentTooltip,
                        onTap: _openAttachmentMenu,
                      ),
                    ),
                    if (channelInputsAvailable) ...[
                      const SizedBox(width: 2),
                      _ChannelInputButton(
                        sources: widget.channelInputSources,
                        busyAccountId: widget.channelInputBusyAccountId,
                        activeAccountId: widget.channelInputActiveAccountId,
                        onTap: _openChannelInputPicker,
                      ),
                    ],
                    const Spacer(),
                    _ContextStatusButton(
                      status: widget.contextStatus,
                      isLoading: widget.isContextStatusLoading,
                      hasSession: widget.hasContextSession,
                      onTap: widget.onContextStatusTap,
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton.filled(
                        key: isSendAction
                            ? const Key('send_message_button')
                            : const Key('stop_message_button'),
                        tooltip: isSendAction
                            ? strings.sendTooltip
                            : strings.stopTooltip,
                        onPressed: isSendAction
                            ? (_canSend ? _send : null)
                            : widget.onStop,
                        style: IconButton.styleFrom(
                          backgroundColor: sendColor,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(
                          isSendAction
                              ? Icons.arrow_upward_rounded
                              : Icons.stop_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreviewRow extends StatelessWidget {
  const _AttachmentPreviewRow({
    required this.attachments,
    required this.onRemove,
  });

  final List<ChatAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.attach_file_rounded,
              size: 14,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 5),
            Text(
              '${attachments.length} attachment${attachments.length == 1 ? '' : 's'}',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < attachments.length; i++) ...[
                _AttachmentChip(
                  attachment: attachments[i],
                  onRemove: () => onRemove(i),
                  compact: true,
                ),
                if (i != attachments.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SlashCommandSuggestions extends StatelessWidget {
  const _SlashCommandSuggestions({
    required this.commands,
    required this.onSelected,
  });

  final List<_SlashCommandSpec> commands;
  final ValueChanged<_SlashCommandSpec> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('slash_command_suggestions'),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: commands.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final command = commands[index];
          return ActionChip(
            key: Key('slash_command_${command.name.substring(1)}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: const Color(0xFFF5F5F5),
            side: const BorderSide(color: Color(0xFFE5E5E5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  command.name,
                  style: const TextStyle(
                    color: Color(0xFF171717),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  command.title,
                  style: const TextStyle(
                    color: Color(0xFF737373),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            onPressed: () => onSelected(command),
          );
        },
      ),
    );
  }
}

class _ChannelInputButton extends StatelessWidget {
  const _ChannelInputButton({
    required this.sources,
    required this.busyAccountId,
    required this.activeAccountId,
    required this.onTap,
  });

  final List<DemoChannelInputSource> sources;
  final String? busyAccountId;
  final String? activeAccountId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final busy = busyAccountId?.trim().isNotEmpty == true;
    final active = activeAccountId?.trim().isNotEmpty == true;
    final sourceLabel = sources.length == 1 ? sources.first.label : '';
    final tooltip = active
        ? _channelText(context, zh: '停止语音输入', en: 'Stop voice input')
        : sourceLabel.isEmpty
        ? _channelText(context, zh: '语音输入', en: 'Voice input')
        : _channelText(
            context,
            zh: '使用 $sourceLabel 语音输入',
            en: 'Voice input with $sourceLabel',
          );
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          key: const Key('channel_voice_input_button'),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          onPressed: busy && !active ? null : onTap,
          icon: active
              ? const Icon(
                  Icons.stop_rounded,
                  size: 21,
                  color: Color(0xFF111827),
                )
              : busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6B7280),
                  ),
                )
              : const Icon(
                  Icons.mic_none_rounded,
                  size: 21,
                  color: Color(0xFF6B7280),
                ),
        ),
      ),
    );
  }
}

class _ChannelInputPickerSheet extends StatelessWidget {
  const _ChannelInputPickerSheet({required this.sources});

  final List<DemoChannelInputSource> sources;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _channelText(context, zh: '选择语音设备', en: 'Choose voice device'),
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sources.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return ListTile(
                    key: Key('channel_voice_input_${source.accountId}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.bluetooth_audio_rounded,
                      color: Color(0xFF374151),
                    ),
                    title: Text(
                      source.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      _channelText(
                        context,
                        zh: '绑定 Agent ${source.agentId}',
                        en: 'Bound to Agent ${source.agentId}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(source),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditingMessageHeader extends StatelessWidget {
  const _EditingMessageHeader({required this.onCancelEdit});

  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Row(
      key: const Key('editing_message_header'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.edit_rounded, size: 15, color: Color(0xFF4B5563)),
        const SizedBox(width: 6),
        Text(
          strings.editingMessageLabel,
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            key: const Key('cancel_edit_message_button'),
            tooltip: strings.cancelEditTooltip,
            padding: EdgeInsets.zero,
            onPressed: onCancelEdit,
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    this.onRemove,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.compact = false,
    this.accountId,
    this.agentId,
  });

  final ChatAttachment attachment;
  final VoidCallback? onRemove;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final bool compact;
  final String? accountId;
  final String? agentId;

  IconData get _fileIcon {
    if (attachment.isWebLink) return Icons.public_rounded;
    if (attachment.isHtml) return Icons.web_asset_outlined;
    if (attachment.isVideo) return Icons.play_circle_outline_rounded;
    if (attachment.isAudio) return Icons.audiotrack_outlined;
    return switch (attachment.extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' ||
      'docx' ||
      'txt' ||
      'json' ||
      'yaml' ||
      'yml' ||
      'xml' ||
      'csv' => Icons.description_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg' => Icons.audiotrack_outlined,
      'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => Icons.videocam_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  String _typeLabel(AppStrings strings) {
    if (attachment.isImage) return strings.imageLabel;
    if (attachment.isWebLink) return 'Web link';
    if (attachment.isHtml) return 'HTML';
    if (attachment.isVideo) return 'Video';
    if (attachment.isAudio) return 'Audio';
    if (attachment.extension.isEmpty) return strings.fileLabel;
    return attachment.typeLabel;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    if (attachment.isImage) {
      return _ImageAttachmentPreview(
        attachment: attachment,
        onRemove: onRemove,
        compact: compact,
      );
    }

    final chip = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: compact ? 176 : 188,
          height: compact ? 52 : 58,
          padding: EdgeInsets.fromLTRB(
            8,
            8,
            onRemove != null || onToggleFavorite != null ? 30 : 10,
            8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 32 : 40,
                height: compact ? 32 : 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Icon(
                  attachment.isImage ? Icons.image_outlined : _fileIcon,
                  color: const Color(0xFF6B7280),
                  size: compact ? 18 : 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _typeLabel(strings),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -5,
            right: -5,
            child: _RemoveAttachmentButton(onTap: onRemove!),
          ),
        if (onRemove == null && onToggleFavorite != null)
          Positioned(
            top: 5,
            right: 5,
            child: _FavoriteAttachmentButton(
              isFavorite: isFavorite,
              onTap: onToggleFavorite!,
            ),
          ),
      ],
    );

    if (compact && onRemove == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openAttachment(
          context,
          attachment,
          accountId: accountId,
          agentId: agentId,
        ),
        child: chip,
      );
    }

    return chip;
  }
}

class _ImageAttachmentPreview extends StatelessWidget {
  const _ImageAttachmentPreview({
    required this.attachment,
    required this.onRemove,
    this.compact = false,
  });

  final ChatAttachment attachment;
  final VoidCallback? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 58.0 : 62.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            File(attachment.path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.image_outlined, color: Color(0xFF6B7280)),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -5,
            right: -5,
            child: _RemoveAttachmentButton(onTap: onRemove!),
          ),
      ],
    );
  }
}

class _RemoveAttachmentButton extends StatelessWidget {
  const _RemoveAttachmentButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.close_rounded, size: 13),
      ),
    );
  }
}

class _MessageAttachmentsView extends StatelessWidget {
  const _MessageAttachmentsView({
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
    final webLinks = attachments
        .where((attachment) => attachment.isWebLink)
        .toList();
    final previewable = attachments
        .where(
          (attachment) =>
              attachment.isImage || attachment.isVideo || attachment.isHtml,
        )
        .toList();
    final files = attachments
        .where(
          (attachment) =>
              !attachment.isImage &&
              !attachment.isVideo &&
              !attachment.isHtml &&
              !attachment.isWebLink,
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (previewable.isNotEmpty)
          _AttachmentPreviewGrid(
            attachments: previewable,
            accountId: accountId,
            agentId: agentId,
            isFavoriteAttachment: isFavoriteAttachment,
            onToggleFavoriteAttachment: onToggleFavoriteAttachment,
          ),
        if (previewable.isNotEmpty && webLinks.isNotEmpty)
          const SizedBox(height: 8),
        if (webLinks.isNotEmpty)
          _WebLinkReferenceSection(
            attachments: webLinks,
            accountId: accountId,
            agentId: agentId,
            isFavoriteAttachment: isFavoriteAttachment,
            onToggleFavoriteAttachment: onToggleFavoriteAttachment,
          ),
        if ((previewable.isNotEmpty || webLinks.isNotEmpty) && files.isNotEmpty)
          const SizedBox(height: 8),
        if (files.isNotEmpty)
          _AttachmentFilesCard(
            files: files,
            accountId: accountId,
            agentId: agentId,
            isFavoriteAttachment: isFavoriteAttachment,
            onToggleFavoriteAttachment: onToggleFavoriteAttachment,
          ),
      ],
    );
  }
}

class _WebLinkReferenceSection extends StatefulWidget {
  const _WebLinkReferenceSection({
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
  State<_WebLinkReferenceSection> createState() =>
      _WebLinkReferenceSectionState();
}

class _WebLinkReferenceSectionState extends State<_WebLinkReferenceSection> {
  late bool _expanded = widget.attachments.length <= 2;

  bool get _isCollapsible => widget.attachments.length > 2;

  @override
  Widget build(BuildContext context) {
    final summary = _referenceSummary(widget.attachments);
    return Container(
      key: const Key('message_web_link_reference_section'),
      width: double.infinity,
      padding: const EdgeInsets.only(left: 10),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('toggle_web_link_reference_section'),
            borderRadius: BorderRadius.circular(8),
            onTap: _isCollapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.link_rounded,
                    size: 14,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'References',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.attachments.length}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_isCollapsible)
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: const Color(0xFF94A3B8),
                    ),
                ],
              ),
            ),
          ),
          if (!_expanded && summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      key: const Key('message_web_link_reference_list'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < widget.attachments.length; i++) ...[
                          _WebLinkReferenceItem(
                            index: i + 1,
                            attachment: widget.attachments[i],
                            accountId: widget.accountId,
                            agentId: widget.agentId,
                            isFavorite: widget.isFavoriteAttachment(
                              widget.attachments[i],
                            ),
                            onToggleFavorite: () =>
                                widget.onToggleFavoriteAttachment(
                                  widget.attachments[i],
                                ),
                          ),
                          if (i != widget.attachments.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _referenceSummary(List<ChatAttachment> attachments) {
    final labels = [
      for (final attachment in attachments.take(2)) _referenceTitle(attachment),
    ];
    if (labels.isEmpty) return '';
    if (attachments.length <= 2) return labels.join('  ');
    return '${labels.join('  ')}  +${attachments.length - 2} more';
  }

  String _referenceTitle(ChatAttachment attachment) {
    final trimmedName = attachment.name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final uri = Uri.tryParse(attachment.path);
    if (uri?.host.isNotEmpty == true) return uri!.host;
    return attachment.path;
  }
}

class _WebLinkReferenceItem extends StatelessWidget {
  const _WebLinkReferenceItem({
    required this.index,
    required this.attachment,
    required this.accountId,
    required this.agentId,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final int index;
  final ChatAttachment attachment;
  final String accountId;
  final String agentId;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final title = attachment.name.trim().isEmpty
        ? attachment.path
        : attachment.name.trim();
    return InkWell(
      key: Key('web_link_reference_$index'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openAttachment(
        context,
        attachment,
        accountId: accountId,
        agentId: agentId,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '[$index]',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
                      color: Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attachment.path,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ReferenceFavoriteButton(
              isFavorite: isFavorite,
              onTap: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceFavoriteButton extends StatelessWidget {
  const _ReferenceFavoriteButton({
    required this.isFavorite,
    required this.onTap,
  });

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Tooltip(
      message: isFavorite ? strings.removeFavorite : strings.addFavorite,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
            color: isFavorite
                ? const Color(0xFFF59E0B)
                : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreviewGrid extends StatelessWidget {
  const _AttachmentPreviewGrid({
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

  double _bounded(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width * 0.68;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;

        if (attachments.length == 1) {
          final attachment = attachments.first;
          if (!attachment.isImage) {
            return _AttachmentChip(
              attachment: attachment,
              compact: true,
              accountId: accountId,
              agentId: agentId,
              isFavorite: isFavoriteAttachment(attachment),
              onToggleFavorite: () => onToggleFavoriteAttachment(attachment),
            );
          }
          final width = _bounded(availableWidth, 160, 280);
          return _MessageAttachmentPreviewTile(
            attachment: attachment,
            width: width,
            height: _bounded(width * 0.72, 120, 190),
            radius: 12,
            accountId: accountId,
            agentId: agentId,
            isFavorite: isFavoriteAttachment(attachment),
            onToggleFavorite: () => onToggleFavoriteAttachment(attachment),
          );
        }

        const spacing = 6.0;
        final itemWidth = _bounded(availableWidth * 0.34, 96, 132);

        return SingleChildScrollView(
          key: const Key('message_attachment_preview_list'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < attachments.length; i++) ...[
                _MessageAttachmentPreviewTile(
                  key: Key('attachment_preview_tile_$i'),
                  attachment: attachments[i],
                  width: itemWidth,
                  height: itemWidth,
                  radius: 10,
                  accountId: accountId,
                  agentId: agentId,
                  isFavorite: isFavoriteAttachment(attachments[i]),
                  onToggleFavorite: () =>
                      onToggleFavoriteAttachment(attachments[i]),
                ),
                if (i != attachments.length - 1) const SizedBox(width: spacing),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MessageAttachmentPreviewTile extends StatelessWidget {
  const _MessageAttachmentPreviewTile({
    super.key,
    required this.attachment,
    required this.width,
    required this.height,
    required this.radius,
    required this.accountId,
    required this.agentId,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  final ChatAttachment attachment;
  final double width;
  final double height;
  final double radius;
  final String accountId;
  final String agentId;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openAttachment(
        context,
        attachment,
        accountId: accountId,
        agentId: agentId,
      ),
      child: Container(
        key: Key(
          'attachment_preview_${attachment.previewKind.name}_${attachment.path.hashCode}',
        ),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AttachmentTileBody(attachment: attachment),
            if (attachment.isVideo || attachment.isHtml || attachment.isWebLink)
              Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    attachment.isVideo
                        ? Icons.play_arrow_rounded
                        : Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                attachment.typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 5)],
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: _FavoriteAttachmentButton(
                isFavorite: isFavorite,
                onTap: onToggleFavorite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteAttachmentButton extends StatelessWidget {
  const _FavoriteAttachmentButton({
    required this.isFavorite,
    required this.onTap,
  });

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Tooltip(
      message: isFavorite ? strings.removeFavorite : strings.addFavorite,
      child: Material(
        color: Colors.black.withValues(alpha: isFavorite ? 0.62 : 0.38),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            key: Key('favorite_attachment_${isFavorite ? 'on' : 'off'}'),
            width: 28,
            height: 28,
            child: Icon(
              isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: isFavorite ? const Color(0xFFFFC857) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentTileBody extends StatelessWidget {
  const _AttachmentTileBody({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return Image.file(
        File(attachment.path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.image_outlined, color: Color(0xFF6B7280)),
        ),
      );
    }
    final icon = attachment.isVideo
        ? Icons.videocam_outlined
        : attachment.isWebLink
        ? Icons.public_rounded
        : Icons.web_asset_outlined;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF374151)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white70, size: 30)),
    );
  }
}

class _AttachmentFilesCard extends StatefulWidget {
  const _AttachmentFilesCard({
    required this.files,
    required this.accountId,
    required this.agentId,
    required this.isFavoriteAttachment,
    required this.onToggleFavoriteAttachment,
  });

  final List<ChatAttachment> files;
  final String accountId;
  final String agentId;
  final bool Function(ChatAttachment attachment) isFavoriteAttachment;
  final ValueChanged<ChatAttachment> onToggleFavoriteAttachment;

  static const int _collapsedVisibleCount = 3;

  @override
  State<_AttachmentFilesCard> createState() => _AttachmentFilesCardState();
}

class _AttachmentFilesCardState extends State<_AttachmentFilesCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final hiddenCount =
        files.length - _AttachmentFilesCard._collapsedVisibleCount;
    final isCollapsible = hiddenCount > 0;
    final visible = !isCollapsible || _expanded
        ? files
        : files.take(_AttachmentFilesCard._collapsedVisibleCount).toList();

    return Container(
      key: const Key('message_attachment_files_card'),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AttachmentFilesCardHeader(count: files.length),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEF1F5)),
          for (var i = 0; i < visible.length; i++) ...[
            _AttachmentFileListRow(
              attachment: visible[i],
              accountId: widget.accountId,
              agentId: widget.agentId,
              isFavorite: widget.isFavoriteAttachment(visible[i]),
              onToggleFavorite: () =>
                  widget.onToggleFavoriteAttachment(visible[i]),
            ),
            if (i != visible.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFEEF1F5),
                indent: 14,
                endIndent: 14,
              ),
          ],
          if (isCollapsible) ...[
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEF1F5)),
            _AttachmentExpandToggle(
              hiddenCount: hiddenCount,
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentFilesCardHeader extends StatelessWidget {
  const _AttachmentFilesCardHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.attach_file_rounded,
              size: 16,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            strings.editedFilesHeader(count),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentFileListRow extends StatelessWidget {
  const _AttachmentFileListRow({
    required this.attachment,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.accountId,
    required this.agentId,
  });

  final ChatAttachment attachment;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final String accountId;
  final String agentId;

  IconData get _fileIcon {
    if (attachment.isWebLink) return Icons.public_rounded;
    if (attachment.isHtml) return Icons.web_asset_outlined;
    if (attachment.isVideo) return Icons.play_circle_outline_rounded;
    if (attachment.isAudio) return Icons.audiotrack_outlined;
    return switch (attachment.extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' ||
      'docx' ||
      'txt' ||
      'json' ||
      'yaml' ||
      'yml' ||
      'xml' ||
      'csv' => Icons.description_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'mp3' || 'wav' || 'aac' || 'flac' || 'ogg' => Icons.audiotrack_outlined,
      'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => Icons.videocam_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openAttachment(
        context,
        attachment,
        accountId: accountId,
        agentId: agentId,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Icon(_fileIcon, size: 18, color: const Color(0xFF64748B)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FavoriteAttachmentButton(
              isFavorite: isFavorite,
              onTap: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentExpandToggle extends StatelessWidget {
  const _AttachmentExpandToggle({
    required this.hiddenCount,
    required this.expanded,
    required this.onTap,
  });

  final int hiddenCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return InkWell(
      key: const Key('message_attachment_files_card_toggle'),
      onTap: onTap,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                expanded
                    ? strings.showLessFiles
                    : strings.showMoreFiles(hiddenCount),
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
              color: const Color(0xFF475569),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openAttachment(
  BuildContext context,
  ChatAttachment attachment, {
  String? accountId,
  String? agentId,
}) async {
  final resolved = _resolveAttachmentForOpen(
    attachment,
    accountId: accountId,
    agentId: agentId,
  );
  if (resolved == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File is not available on this device')),
    );
    return;
  }
  if (resolved.isWebLink || resolved.isHtml) {
    await _showWebAttachmentPreview(context, resolved);
    return;
  }
  if (resolved.isImage) {
    await _showAttachmentImagePreview(context, resolved);
    return;
  }
  if (resolved.isVideo) {
    await _showVideoAttachmentPreview(context, resolved);
    return;
  }
  await share.Share.shareXFiles([
    share.XFile(
      resolved.path,
      name: resolved.name,
      mimeType: resolved.mimeType,
    ),
  ]);
}

ChatAttachment? _resolveAttachmentForOpen(
  ChatAttachment attachment, {
  String? accountId,
  String? agentId,
}) {
  if (attachment.isWebLink) return attachment;

  final candidates = <String>[
    attachment.path.trim(),
    ..._attachmentSandboxPathCandidates(
      attachment.sandboxPath,
      accountId: accountId,
      agentId: agentId,
    ),
  ];
  for (final path in candidates) {
    if (path.isEmpty) continue;
    if (File(path).existsSync()) {
      if (path == attachment.path) return attachment;
      return ChatAttachment(
        name: attachment.name,
        path: path,
        type: attachment.type,
        sandboxPath: attachment.sandboxPath,
        mimeTypeOverride: attachment.mimeTypeOverride,
      );
    }
  }
  return null;
}

List<String> _attachmentSandboxPathCandidates(
  String? sandboxPath, {
  String? accountId,
  String? agentId,
}) {
  final path = sandboxPath?.trim();
  if (path == null || path.isEmpty || !sdk.NapaxiFileBridge.isInitialized) {
    return const [];
  }
  final bridge = sdk.NapaxiFileBridge.instance;
  final candidates = <String>[];
  final effectiveAccountId = accountId?.trim().isNotEmpty == true
      ? accountId!.trim()
      : sdk.NapaxiEngine.defaultAccountId;
  final effectiveAgentId = agentId?.trim().isNotEmpty == true
      ? agentId!.trim()
      : sdk.NapaxiEngine.defaultAgentId;
  final scoped = bridge.sandboxToRealScoped(
    path,
    accountId: effectiveAccountId,
    agentId: effectiveAgentId,
  );
  if (scoped != null && scoped.isNotEmpty) candidates.add(scoped);
  final unscoped = bridge.sandboxToReal(path);
  if (unscoped != null && unscoped.isNotEmpty) candidates.add(unscoped);
  return candidates.toSet().toList(growable: false);
}

Future<void> _showWebAttachmentPreview(
  BuildContext context,
  ChatAttachment attachment,
) {
  final initialUrl = attachment.isWebLink
      ? Uri.tryParse(attachment.path)
      : null;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WebPreviewPage(
        title: 'Preview',
        displayUrl: attachment.isWebLink ? attachment.path : attachment.name,
        initialUrl: initialUrl,
        initialFilePath: attachment.isWebLink ? null : attachment.path,
        shareText: attachment.isWebLink ? attachment.path : null,
        shareFilePath: attachment.isWebLink ? null : attachment.path,
        shareFileName: attachment.isWebLink ? null : attachment.name,
        shareFileMimeType: attachment.isWebLink ? null : attachment.mimeType,
      ),
    ),
  );
}

Future<void> _showVideoAttachmentPreview(
  BuildContext context,
  ChatAttachment attachment,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _AttachmentVideoPreviewPage(attachment: attachment),
    ),
  );
}

Future<void> _showAttachmentImagePreview(
  BuildContext context,
  ChatAttachment attachment,
) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(18),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  File(attachment.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Icon(
                      Icons.image_outlined,
                      color: Colors.white70,
                      size: 42,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AttachmentVideoPreviewPage extends StatefulWidget {
  const _AttachmentVideoPreviewPage({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_AttachmentVideoPreviewPage> createState() =>
      _AttachmentVideoPreviewPageState();
}

class _AttachmentVideoPreviewPageState
    extends State<_AttachmentVideoPreviewPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.attachment.path));
    _initialize = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.attachment.name),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: () => _shareAttachment(widget.attachment),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initialize,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not play this video.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          return Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller),
                  IconButton.filled(
                    key: const Key('video_preview_play_button'),
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Future<void> _shareAttachment(ChatAttachment attachment) {
  if (attachment.isWebLink) {
    return share.Share.share(attachment.path);
  }
  return share.Share.shareXFiles([
    share.XFile(
      attachment.path,
      name: attachment.name,
      mimeType: attachment.mimeType,
    ),
  ]);
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.semanticKey,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final Key semanticKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          key: semanticKey,
          width: 40,
          height: 40,
          child: Center(
            child: Icon(icon, size: 22, color: const Color(0xFF6B7280)),
          ),
        ),
      ),
    );
  }
}

class _AttachmentMenuOverlay extends StatelessWidget {
  const _AttachmentMenuOverlay({
    required this.onFileTap,
    required this.onGalleryTap,
    required this.onCameraTap,
    this.onSkillsTap,
  });

  final VoidCallback onFileTap;
  final VoidCallback onGalleryTap;
  final VoidCallback onCameraTap;
  final VoidCallback? onSkillsTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AttachmentMenuItem(
              icon: Icons.insert_drive_file_outlined,
              label: strings.fileLabel,
              onTap: onFileTap,
            ),
            _AttachmentMenuItem(
              icon: Icons.photo_library_outlined,
              label: strings.galleryLabel,
              onTap: onGalleryTap,
            ),
            _AttachmentMenuItem(
              icon: Icons.camera_alt_outlined,
              label: strings.cameraLabel,
              onTap: onCameraTap,
            ),
            if (onSkillsTap != null)
              _AttachmentMenuItem(
                icon: Icons.extension_rounded,
                label: strings.skillsMenuLabel,
                onTap: onSkillsTap!,
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMenuItem extends StatelessWidget {
  const _AttachmentMenuItem({
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF374151)),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skill Picker Sheet
// ---------------------------------------------------------------------------

class _SkillPickerSheet extends StatefulWidget {
  const _SkillPickerSheet({
    required this.client,
    required this.agentId,
    required this.alreadyPinned,
    required this.scrollController,
    required this.onSkillSelected,
  });

  final NapaxiChatClient client;
  final String agentId;
  final Set<String> alreadyPinned;
  final ScrollController scrollController;
  final ValueChanged<String> onSkillSelected;

  @override
  State<_SkillPickerSheet> createState() => _SkillPickerSheetState();
}

class _SkillPickerSheetState extends State<_SkillPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<sdk.SkillInfo>> _installedFuture;
  late Future<sdk.SkillStatusReport> _statusFuture;
  late Future<sdk.CatalogSearchResult> _catalogFuture;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};
  final Set<String> _installedNames = {};
  String? _installingSlug;
  String? _installMessage;
  bool _installSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selected.addAll(widget.alreadyPinned);
    _installedFuture = _loadInstalled();
    _statusFuture = widget.client.listSkillStatus(agentId: widget.agentId);
    _catalogFuture = widget.client.listCatalogPackages(limit: 50);
  }

  Future<List<sdk.SkillInfo>> _loadInstalled() async {
    final skills = await widget.client.listSkills(agentId: widget.agentId);
    final prefs = await SharedPreferences.getInstance();
    final slugMapRaw = prefs.getStringList('skill_slug_to_name') ?? [];
    final slugKeys = <String>[];
    for (final entry in slugMapRaw) {
      final sep = entry.indexOf('=');
      if (sep > 0) slugKeys.add(entry.substring(0, sep));
    }
    if (mounted) {
      setState(() {
        _installedNames
          ..clear()
          ..addAll(slugKeys);
      });
    }
    return skills;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _autoDismissMessage() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _installMessage = null);
    });
  }

  void _searchCatalog() {
    final query = _searchController.text.trim();
    setState(() {
      _query = query;
      _catalogFuture = query.isNotEmpty
          ? widget.client.searchCatalog(query)
          : widget.client.listCatalogPackages(limit: 50);
    });
  }

  Future<void> _installSkill(sdk.CatalogSkillInfo skill) async {
    if (_installingSlug != null) return;
    final strings = AppStrings.of(context);
    final slugLower = skill.slug.toLowerCase();
    final wasInstalled = _installedNames.contains(slugLower);
    setState(() => _installingSlug = skill.slug);
    try {
      final target = (skill.slug.trim().isNotEmpty ? skill.slug : skill.name)
          .trim();
      final result = await widget.client.installFromCatalog(
        target,
        agentId: widget.agentId,
      );
      if (!mounted) return;
      if (result.success) {
        _installedNames.add(slugLower);
        // Persist slug→name mapping (same as main skill store).
        final installedName = result.name?.toLowerCase().trim() ?? '';
        if (installedName.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getStringList('skill_slug_to_name') ?? [];
          final map = <String, String>{};
          for (final entry in raw) {
            final sep = entry.indexOf('=');
            if (sep > 0) {
              map[entry.substring(0, sep)] = entry.substring(sep + 1);
            }
          }
          map[slugLower] = installedName;
          await prefs.setStringList(
            'skill_slug_to_name',
            map.entries.map((e) => '${e.key}=${e.value}').toList(),
          );
        }
        if (!mounted) return;
        setState(() {
          _installedFuture = _loadInstalled();
          _statusFuture = widget.client.listSkillStatus(
            agentId: widget.agentId,
          );
          _installMessage = wasInstalled
              ? strings.skillUpdated(result.name ?? skill.name)
              : strings.skillInstalled(result.name ?? skill.name);
          _installSuccess = true;
        });
      } else {
        setState(() {
          _installMessage = result.error ?? 'Install failed';
          _installSuccess = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _installMessage = '$error';
          _installSuccess = false;
        });
      }
    }
    _autoDismissMessage();
    if (mounted) setState(() => _installingSlug = null);
  }

  void _selectSkill(String name) {
    setState(() => _selected.add(name));
    widget.onSkillSelected(name);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Column(
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            strings.selectSkillsTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF111827),
          labelColor: const Color(0xFF111827),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: const Color(0xFFE5E7EB),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: strings.installedSkillsTitle),
            Tab(text: strings.skillStoreTitle),
          ],
        ),
        if (_installMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _installSuccess
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFFEF2F2),
            child: Text(
              _installMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _installSuccess
                    ? const Color(0xFF14532D)
                    : const Color(0xFF991B1B),
              ),
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildInstalledTab(), _buildStoreTab(strings)],
          ),
        ),
      ],
    );
  }

  Widget _buildInstalledTab() {
    return FutureBuilder<List<sdk.SkillInfo>>(
      future: _installedFuture,
      builder: (context, skillsSnapshot) {
        if (skillsSnapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF111827)),
          );
        }
        final skills = skillsSnapshot.data ?? [];
        if (skills.isEmpty) {
          return const Center(
            child: Text(
              'No skills installed',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          );
        }
        return FutureBuilder<sdk.SkillStatusReport>(
          future: _statusFuture,
          builder: (context, statusSnapshot) {
            final statusByName = <String, sdk.SkillStatusEntry>{};
            if (statusSnapshot.data != null) {
              for (final entry in statusSnapshot.data!.entries) {
                statusByName[entry.name.toLowerCase()] = entry;
              }
            }
            return ListView.separated(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: skills.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final skill = skills[index];
                final status = statusByName[skill.name.toLowerCase()];
                final isReady = status?.isReady ?? false;
                final isSelected = _selected.contains(skill.name);
                return _SkillPickerTile(
                  name: skill.name,
                  description: skill.description,
                  isReady: isReady,
                  isSelected: isSelected,
                  onSelect: isReady && !isSelected
                      ? () => _selectSkill(skill.name)
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStoreTab(AppStrings strings) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchCatalog(),
            decoration: InputDecoration(
              hintText: strings.searchSkillsHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF111827)),
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<sdk.CatalogSearchResult>(
            future: _catalogFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF111827)),
                );
              }
              final results = snapshot.data?.results ?? [];
              if (results.isEmpty) {
                return Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No skills available'
                        : 'No results for "$_query"',
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: results.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final skill = results[index];
                  final installing = _installingSlug == skill.slug;
                  final installed = _installedNames.contains(
                    skill.slug.toLowerCase(),
                  );
                  return _SkillPickerCatalogTile(
                    skill: skill,
                    installing: installing,
                    installed: installed,
                    onInstall: () => _installSkill(skill),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkillPickerTile extends StatelessWidget {
  const _SkillPickerTile({
    required this.name,
    required this.description,
    required this.isReady,
    required this.isSelected,
    this.onSelect,
  });

  final String name;
  final String description;
  final bool isReady;
  final bool isSelected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.extension_rounded,
              size: 20,
              color: isReady
                  ? const Color(0xFF4B5563)
                  : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isReady
                          ? const Color(0xFF111827)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: Color(0xFF4B5563),
              )
            else if (isReady)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onSelect,
                child: const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 20,
                  color: Color(0xFF4B5563),
                ),
              )
            else
              const Text(
                'N/A',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkillPickerCatalogTile extends StatelessWidget {
  const _SkillPickerCatalogTile({
    required this.skill,
    required this.installing,
    required this.installed,
    required this.onInstall,
  });

  final sdk.CatalogSkillInfo skill;
  final bool installing;
  final bool installed;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final displayName = skill.name.isEmpty ? skill.slug : skill.name;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.storefront_rounded,
              size: 20,
              color: Color(0xFF4B5563),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (skill.description.isNotEmpty)
                    Text(
                      skill.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: installing ? null : onInstall,
              style: _skillTextButtonStyle(),
              icon: installing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF111827),
                      ),
                    )
                  : Icon(
                      installed ? Icons.sync_rounded : Icons.add_rounded,
                      size: 16,
                    ),
              label: Text(
                installed
                    ? AppStrings.of(context).updateSkill
                    : AppStrings.of(context).installSkill,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned Skill Chips Row
// ---------------------------------------------------------------------------

class _PinnedSkillChipsRow extends StatelessWidget {
  const _PinnedSkillChipsRow({required this.skills, required this.onRemove});

  final List<String> skills;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: skills.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.extension_rounded,
                  size: 13,
                  color: Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Text(
                  skills[index],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => onRemove(index),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
