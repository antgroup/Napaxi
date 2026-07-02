part of '../main.dart';

enum _ConversationAttachmentSource { uploaded, generated }

/// One entry in the flat chat message list: either a message bubble or a
/// per-turn block aggregating the generated attachments produced in that turn.
abstract class _ChatRenderItem {
  const _ChatRenderItem();
}

class _MessageItem extends _ChatRenderItem {
  const _MessageItem(this.message);

  final ChatMessage message;
}

class _GeneratedAttachmentsItem extends _ChatRenderItem {
  const _GeneratedAttachmentsItem({
    required this.attachments,
    required this.turnIndex,
    this.turnUserMessageId,
  });

  final List<ChatAttachment> attachments;
  final int turnIndex;
  final String? turnUserMessageId;
}

class _TerminalSession {
  _TerminalSession({
    required this.id,
    required this.backend,
    required this.terminal,
  });

  final String id;
  final TerminalBackend backend;
  final Terminal terminal;
  final TerminalController controller = TerminalController();
  final TerminalModifierController modifiers = TerminalModifierController();
  StreamSubscription<String>? outputSubscription;

  void dispose() {
    outputSubscription?.cancel();
    backend.kill();
    modifiers.dispose();
  }
}

class _ConversationAttachmentItem {
  const _ConversationAttachmentItem({
    required this.attachment,
    required this.source,
    required this.createdAt,
  });

  final ChatAttachment attachment;
  final _ConversationAttachmentSource source;
  final DateTime createdAt;
}

class _ConversationAttachmentsSheet extends StatelessWidget {
  const _ConversationAttachmentsSheet({
    required this.items,
    required this.onOpenAttachment,
  });

  final List<_ConversationAttachmentItem> items;
  final ValueChanged<ChatAttachment> onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      snap: true,
      snapSizes: const [0.85],
      builder: (context, scrollController) {
        return SafeArea(
          key: const Key('conversation_attachments_panel'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.conversationAttachmentsTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? SingleChildScrollView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: _ConversationAttachmentsEmpty(strings: strings),
                      )
                    : ListView.separated(
                        key: const Key('conversation_attachments_list'),
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 16),
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ConversationAttachmentTile(
                            item: item,
                            onTap: () => onOpenAttachment(item.attachment),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationAttachmentsEmpty extends StatelessWidget {
  const _ConversationAttachmentsEmpty({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_file_rounded,
              color: Color(0xFF9CA3AF),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              strings.noConversationAttachmentsTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF171717),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.noConversationAttachmentsDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationAttachmentTile extends StatelessWidget {
  const _ConversationAttachmentTile({required this.item, required this.onTap});

  final _ConversationAttachmentItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final attachment = item.attachment;
    final path = attachment.sandboxPath?.trim().isNotEmpty == true
        ? attachment.sandboxPath!.trim()
        : attachment.path.trim();
    final source = item.source == _ConversationAttachmentSource.uploaded
        ? strings.uploadedAttachmentLabel
        : strings.generatedAttachmentLabel;

    return ListTile(
      key: Key('conversation_attachment_${_attachmentTileKey(attachment)}'),
      dense: true,
      minLeadingWidth: 36,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: _ConversationAttachmentIcon(attachment: attachment),
      title: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF171717),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        [source, attachment.typeLabel, if (path.isNotEmpty) path].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  String _attachmentTileKey(ChatAttachment attachment) {
    final identity = attachment.sandboxPath?.trim().isNotEmpty == true
        ? attachment.sandboxPath!.trim()
        : attachment.path.trim();
    return identity.hashCode.toString();
  }
}

class _ConversationAttachmentIcon extends StatelessWidget {
  const _ConversationAttachmentIcon({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final icon = switch (attachment.previewKind) {
      ChatAttachmentPreviewKind.image => Icons.image_rounded,
      ChatAttachmentPreviewKind.video => Icons.movie_rounded,
      ChatAttachmentPreviewKind.audio => Icons.graphic_eq_rounded,
      ChatAttachmentPreviewKind.html => Icons.web_asset_rounded,
      ChatAttachmentPreviewKind.webLink => Icons.link_rounded,
      ChatAttachmentPreviewKind.file => Icons.insert_drive_file_rounded,
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: const Color(0xFF374151), size: 20),
    );
  }
}
